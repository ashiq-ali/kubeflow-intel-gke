#!/usr/bin/env bash
# deploy-kubeflow.sh — Deploy Kubeflow cluster on Intel Xeon C3 nodes
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/.."
KF_DIST="${HOME}/kubeflow-distribution"

source "${REPO_ROOT}/kubeflow/env.sh"

echo "==> Deploying Kubeflow: ${KF_NAME} (${KF_INSTANCE_TYPE} nodes)"

# ── Pull upstream manifests ────────────────────────────────────────────────────
echo "==> Pulling upstream Kubeflow manifests..."
cd "${KF_DIST}/kubeflow"
cp "${REPO_ROOT}/kubeflow/env.sh" ./env.sh
source ./env.sh
bash ./pull-upstream.sh

# ── Apply kpt setters ─────────────────────────────────────────────────────────
echo "==> Applying kpt setters..."
bash "${REPO_ROOT}/kubeflow/kpt-set.sh"

# ── Apply known v1.7.0 upstream YAML fixes ────────────────────────────────────
echo "==> Applying upstream YAML patches for v1.7.0..."

CLUSTER_YAML="${KF_DIST}/kubeflow/common/cluster/upstream/cluster.yaml"
NODEPOOL_YAML="${KF_DIST}/kubeflow/common/cluster/upstream/nodepool.yaml"
PROFILES_CRD="${KF_DIST}/kubeflow/apps/profiles/upstream/crd/bases/kubeflow.org_profiles.yaml"

# Fix 1 & 2: Remove deprecated metadata.clusterName field
for f in "${CLUSTER_YAML}" "${NODEPOOL_YAML}"; do
  if [[ -f "${f}" ]]; then
    sed -i '/^\s*clusterName:/d' "${f}"
    echo "    Patched: $(basename ${f})"
  fi
done

# Fix 3: Remove spurious creationTimestamp: null
if [[ -f "${PROFILES_CRD}" ]]; then
  sed -i '/^\s*creationTimestamp: null/d' "${PROFILES_CRD}"
  echo "    Patched: $(basename ${PROFILES_CRD})"
fi

# ── Override instance type to Intel Xeon C3 ───────────────────────────────────
echo "==> Setting node pool to Intel Xeon C3: ${KF_INSTANCE_TYPE} x${KF_NODE_COUNT}"
if [[ -f "${NODEPOOL_YAML}" ]]; then
  sed -i "s/machineType:.*/machineType: ${KF_INSTANCE_TYPE}/" "${NODEPOOL_YAML}"
  sed -i "s/initialNodeCount:.*/initialNodeCount: ${KF_NODE_COUNT}/" "${NODEPOOL_YAML}"
fi

# ── Deploy GCP resources via Config Controller ────────────────────────────────
echo "==> Applying KCC resources (VPC, GKE cluster)..."
make apply-kcc

# Wait for GKE cluster to be ready
echo "==> Waiting for GKE cluster to be ready..."
timeout 900 bash -c "
  until gcloud container clusters describe ${KF_NAME} \
    --zone ${ZONE} --project ${KF_PROJECT} \
    --format='value(status)' 2>/dev/null | grep -q RUNNING; do
    echo '    Waiting for cluster...'; sleep 30
  done
"

# ── Get cluster credentials ────────────────────────────────────────────────────
echo "==> Fetching cluster credentials..."
gcloud container clusters get-credentials "${KF_NAME}" \
  --zone "${ZONE}" \
  --project "${KF_PROJECT}"

# ── Deploy Kubeflow workloads ─────────────────────────────────────────────────
echo "==> Deploying Kubeflow workloads (may take 10-15 minutes)..."
MAX_ATTEMPTS=3
for attempt in $(seq 1 ${MAX_ATTEMPTS}); do
  echo "    Attempt ${attempt}/${MAX_ATTEMPTS}..."
  if make apply; then
    break
  elif [[ ${attempt} -lt ${MAX_ATTEMPTS} ]]; then
    echo "    Deploy failed (webhook timeout likely) — retrying in 30s..."
    sleep 30
  else
    echo "ERROR: Kubeflow deploy failed after ${MAX_ATTEMPTS} attempts."
    exit 1
  fi
done

# ── Grant IAP access ──────────────────────────────────────────────────────────
CURRENT_USER=$(gcloud config get-value account)
echo "==> Granting IAP access to: ${CURRENT_USER}"
gcloud projects add-iam-policy-binding "${KF_PROJECT}" \
  --member="user:${CURRENT_USER}" \
  --role=roles/iap.httpsResourceAccessor \
  --quiet

# ── Print access URL ──────────────────────────────────────────────────────────
echo ""
echo "✓ Kubeflow deployed successfully on Intel Xeon ${KF_INSTANCE_TYPE}"
echo ""
echo "  Kubeflow URL (may take 2-3 min for DNS propagation):"
kubectl -n istio-system get ingress -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null \
  && echo "" || echo "  Run: kubectl -n istio-system get ingress"
echo ""
echo "  Verify pods: kubectl -n kubeflow get pods"
echo ""
