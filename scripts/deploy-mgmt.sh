#!/usr/bin/env bash
# deploy-mgmt.sh — Deploy Anthos Config Controller management cluster
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/.."

source "${REPO_ROOT}/management/env.sh"

echo "==> Deploying management cluster: ${MGMT_NAME} in ${LOCATION}"

# ── Clone kubeflow-distribution if not present ────────────────────────────────
KF_DIST="${HOME}/kubeflow-distribution"
if [[ ! -d "${KF_DIST}" ]]; then
  echo "==> Cloning kubeflow-distribution v1.7.0..."
  git clone https://github.com/googlecloudplatform/kubeflow-distribution.git "${KF_DIST}"
  cd "${KF_DIST}"
  git checkout tags/v1.7.0 -b v1.7.0
else
  echo "    kubeflow-distribution already cloned."
fi

# ── Apply kpt setters ─────────────────────────────────────────────────────────
echo "==> Applying kpt setters..."
cd "${KF_DIST}/management"
cp "${REPO_ROOT}/management/env.sh" ./env.sh
source ./env.sh
bash "${REPO_ROOT}/management/kpt-set.sh"

# ── Create Anthos Config Controller cluster ────────────────────────────────────
echo "==> Creating Anthos Config Controller cluster (this takes ~10 minutes)..."
gcloud anthos config controller create "${MGMT_NAME}" \
  --location="${LOCATION}" \
  --project="${MGMT_PROJECT}"

# ── Set up kubeconfig context ─────────────────────────────────────────────────
echo "==> Fetching cluster credentials..."
gcloud anthos config controller get-credentials "${MGMT_NAME}" \
  --location="${LOCATION}" \
  --project="${MGMT_PROJECT}"

# ── Grant owner permissions to Config Controller SA ───────────────────────────
echo "==> Granting owner permissions to Config Controller service account..."
SA_EMAIL="$(kubectl get ConfigConnectorContext -n config-control \
  -o jsonpath='{.items[0].spec.googleServiceAccount}' 2>/dev/null || echo '')"

if [[ -n "${SA_EMAIL}" ]]; then
  gcloud projects add-iam-policy-binding "${MGMT_PROJECT}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role=roles/owner \
    --quiet
  echo "    Granted owner to: ${SA_EMAIL}"
else
  echo "    WARNING: Could not retrieve Config Connector SA — grant owner manually."
fi

echo ""
echo "✓ Management cluster deployed: ${MGMT_NAME}"
echo "  Next: bash scripts/deploy-kubeflow.sh"
echo ""
