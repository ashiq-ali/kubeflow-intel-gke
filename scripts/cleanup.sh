#!/usr/bin/env bash
# cleanup.sh — Teardown Kubeflow and management clusters in correct order
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/.."
KF_DIST="${HOME}/kubeflow-distribution"

source "${REPO_ROOT}/kubeflow/env.sh"
source "${REPO_ROOT}/management/env.sh"

echo "WARNING: This will permanently delete all Kubeflow resources."
read -r -p "Type 'yes' to confirm: " CONFIRM
if [[ "${CONFIRM}" != "yes" ]]; then
  echo "Aborted."
  exit 0
fi

# ── Step 1: Delete Kubeflow namespace and workloads ───────────────────────────
echo "==> [1/4] Deleting Kubeflow namespace..."
gcloud container clusters get-credentials "${KF_NAME}" \
  --zone "${ZONE}" --project "${KF_PROJECT}" 2>/dev/null || true

kubectl delete namespace kubeflow --wait --timeout=300s 2>/dev/null || true

# ── Step 2: Tear down KCC-managed GCP resources ───────────────────────────────
echo "==> [2/4] Deleting KCC-managed GCP resources (VPC, cluster)..."
cd "${KF_DIST}/kubeflow"
source ./env.sh 2>/dev/null || true
make delete 2>/dev/null || echo "    make delete completed (some errors may be expected)"

# ── Step 3: Delete Kubeflow project namespace from management cluster ──────────
echo "==> [3/4] Deleting project namespace from management cluster..."
kubectl config use-context "${MGMTCTXT}" 2>/dev/null || true
kubectl delete namespace --wait "${KF_PROJECT}" 2>/dev/null || true

# ── Step 4: Delete management cluster ─────────────────────────────────────────
echo "==> [4/4] Deleting Anthos Config Controller management cluster..."
cd "${KF_DIST}/management"
source ./env.sh 2>/dev/null || true
make delete-cluster 2>/dev/null || \
  gcloud anthos config controller delete "${MGMT_NAME}" \
    --location="${LOCATION}" --project="${MGMT_PROJECT}" --quiet

echo ""
echo "✓ Cleanup complete."
echo ""
