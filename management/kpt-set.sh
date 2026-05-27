#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/env.sh"

kpt fn eval --image gcr.io/kpt-fn/apply-setters:v0.2 ./upstream -- \
  mgmt-project="${MGMT_PROJECT}" \
  mgmt-name="${MGMT_NAME}" \
  location="${LOCATION}"
