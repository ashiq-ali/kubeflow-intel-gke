#!/usr/bin/env bash
# bootstrap.sh — Enable GCP APIs and configure prerequisites
# Run once per project before deploying management or Kubeflow clusters
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Load config ────────────────────────────────────────────────────────────────
if [[ ! -f "${SCRIPT_DIR}/../management/env.sh" ]]; then
  echo "ERROR: management/env.sh not found. Copy env.sh.example and fill in values."
  exit 1
fi
source "${SCRIPT_DIR}/../management/env.sh"

PROJECT_ID="${MGMT_PROJECT}"

echo "==> Configuring project: ${PROJECT_ID}"
gcloud config set project "${PROJECT_ID}"

# ── Enable required APIs ───────────────────────────────────────────────────────
echo "==> Enabling GCP APIs (this takes ~2 minutes)..."
APIS=(
  serviceusage.googleapis.com
  compute.googleapis.com
  container.googleapis.com
  iam.googleapis.com
  ml.googleapis.com
  iap.googleapis.com
  krmapihosting.googleapis.com
  meshconfig.googleapis.com
  endpoints.googleapis.com
  cloudbuild.googleapis.com
  cloudresourcemanager.googleapis.com
  anthos.googleapis.com
  gkeconnect.googleapis.com
  gkehub.googleapis.com
)

gcloud services enable "${APIS[@]}" --project="${PROJECT_ID}"
echo "    APIs enabled."

# ── Initialize Anthos Service Mesh ────────────────────────────────────────────
echo "==> Initializing Anthos Service Mesh..."
curl --silent --fail --request POST \
  --header "Authorization: Bearer $(gcloud auth print-access-token)" \
  --data '' \
  "https://meshconfig.googleapis.com/v1alpha1/projects/${PROJECT_ID}:initialize"
echo ""
echo "    ASM initialized."

# ── IAM — grant Cloud Build service account ───────────────────────────────────
echo "==> Granting Cloud Build service account required roles..."
PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')
CB_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"

for role in roles/container.admin roles/iam.serviceAccountUser roles/container.clusterViewer; do
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${CB_SA}" \
    --role="${role}" \
    --quiet
done
echo "    IAM bindings applied."

# ── OAuth reminder ─────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════"
echo "  MANUAL STEP REQUIRED: Configure OAuth Consent Screen"
echo "════════════════════════════════════════════════════════"
echo ""
echo "  1. Go to: https://console.cloud.google.com/apis/credentials/consent"
echo "  2. Set User Type: External"
echo "  3. Add authorized domain: ${PROJECT_ID}.cloud.goog"
echo "  4. Go to: https://console.cloud.google.com/apis/credentials"
echo "  5. Create OAuth 2.0 Client ID (Web application)"
echo "  6. Add redirect URI:"
echo "       https://iap.googleapis.com/v1/oauth/clientIds/<CLIENT_ID>:handleRedirect"
echo "  7. Copy CLIENT_ID and CLIENT_SECRET into kubeflow/env.sh"
echo ""
echo "  Once done, run: bash scripts/deploy-mgmt.sh"
echo ""
