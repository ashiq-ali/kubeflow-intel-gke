#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/env.sh"

kpt fn eval --image gcr.io/kpt-fn/apply-setters:v0.2 ./upstream -- \
  kf-project="${KF_PROJECT}" \
  kf-name="${KF_NAME}" \
  location="${REGION}" \
  zone="${ZONE}" \
  client-id="${CLIENT_ID}" \
  client-secret="${CLIENT_SECRET}" \
  gke-machine-type="${KF_INSTANCE_TYPE}"
