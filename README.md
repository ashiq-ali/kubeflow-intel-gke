# kubeflow-intel-gke

> Production Kubeflow deployment on GKE using Intel Xeon C3 instances — Anthos Config Controller, Istio service mesh, Identity-Aware Proxy, and fully automated bootstrap.

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![GKE](https://img.shields.io/badge/GKE-Kubeflow_v1.7-4285F4?logo=googlecloud&logoColor=white)](https://github.com/googlecloudplatform/kubeflow-distribution)
[![Intel](https://img.shields.io/badge/Intel-Xeon_C3-0071C5?logo=intel&logoColor=white)](https://cloud.google.com/compute/docs/general-purpose-machines#c3_series)

```
┌──────────────────────────────────────────────────────────────────┐
│  kubeflow-intel-gke                                               │
│                                                                   │
│  scripts/                                                         │
│  ├── bootstrap.sh        ──► Enable APIs, OAuth, IAM setup        │
│  ├── deploy-mgmt.sh      ──► Anthos Config Controller cluster     │
│  ├── deploy-kubeflow.sh  ──► Kubeflow cluster + workloads        │
│  └── cleanup.sh          ──► Teardown in correct order           │
│                                                                   │
│  management/                                                      │
│  ├── env.sh              Management cluster config               │
│  └── kpt-set.sh          kpt setter for management resources     │
│                                                                   │
│  kubeflow/                                                        │
│  ├── env.sh              Kubeflow cluster config                 │
│  ├── kpt-set.sh          kpt setter for Kubeflow resources       │
│  └── patches/            YAML fixes for known v1.7 issues        │
│                                                                   │
│  terraform/                                                       │
│  ├── main.tf             GKE + networking (alternative IaC)      │
│  ├── variables.tf                                                 │
│  └── outputs.tf                                                   │
└──────────────────────────────────────────────────────────────────┘
```

## Architecture

```
                    ┌─────────────────────────────────────────┐
                    │           GCP Project                    │
                    │                                          │
                    │  ┌──────────────────┐                   │
                    │  │ Management       │                    │
                    │  │ Cluster          │                    │
                    │  │ (Anthos CC)      │──► provisions ──► │
                    │  │ 3x e2-standard-2 │                   │
                    │  └──────────────────┘                   │
                    │           │                              │
                    │           ▼                              │
                    │  ┌──────────────────────────────────┐   │
                    │  │ Kubeflow Cluster                  │   │
                    │  │ Intel Xeon C3 (c3-standard-8)    │   │
                    │  │                                   │   │
                    │  │  Istio ──► IAP ──► Kubeflow UI   │   │
                    │  │  Pipelines · Notebooks · KFServe  │   │
                    │  └──────────────────────────────────┘   │
                    └─────────────────────────────────────────┘
```

**Why Intel Xeon C3 on GCP?**
- Custom Intel IPUs (Infrastructure Processing Units) offload networking and storage
- Higher memory bandwidth vs E2/N2 — critical for ML data loading
- AVX-512 VNNI instructions accelerate inference without GPU cost
- Up to 192 vCPUs / 1.5TB RAM per node for large model training

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| gcloud CLI | latest | [cloud.google.com/sdk](https://cloud.google.com/sdk) |
| kubectl | ≥ 1.27 | `gcloud components install kubectl` |
| kpt | ≥ 1.0 | `gcloud components install kpt` |
| kustomize | ≥ 5.0 | `brew install kustomize` |

**GCP requirements:**
- Project with Owner role
- Billing enabled
- Quota for C3 instances in target region

## Quickstart

```bash
# 1. Clone and configure
git clone https://github.com/ashiq-ali/kubeflow-intel-gke.git
cd kubeflow-intel-gke

# 2. Set your project variables
cp management/env.sh.example management/env.sh
cp kubeflow/env.sh.example kubeflow/env.sh
# Edit both files with your PROJECT_ID, region, OAuth credentials

# 3. Enable APIs and configure OAuth
bash scripts/bootstrap.sh

# 4. Deploy management cluster (~10 min)
bash scripts/deploy-mgmt.sh

# 5. Deploy Kubeflow cluster (~15 min)
bash scripts/deploy-kubeflow.sh

# 6. Get your Kubeflow URL
kubectl -n istio-system get ingress
```

## Configuration

### management/env.sh

```bash
export MGMT_PROJECT=my-gcp-project
export MGMT_NAME=kubeflow-mgmt
export LOCATION=us-central1           # Anthos CC supported regions only
```

### kubeflow/env.sh

```bash
export KF_PROJECT=my-gcp-project
export KF_NAME=kubeflow
export ZONE=us-central1-a
export CLIENT_ID=<oauth-client-id>
export CLIENT_SECRET=<oauth-client-secret>
export KF_INSTANCE_TYPE=c3-standard-8  # Intel Xeon C3
```

## GCP APIs Enabled

`scripts/bootstrap.sh` enables all required APIs automatically:

| API | Purpose |
|-----|---------|
| `container.googleapis.com` | GKE clusters |
| `krmapihosting.googleapis.com` | Anthos Config Controller |
| `meshconfig.googleapis.com` | Anthos Service Mesh / Istio |
| `iap.googleapis.com` | Identity-Aware Proxy |
| `ml.googleapis.com` | Vertex AI / Cloud ML |
| `cloudbuild.googleapis.com` | Image builds |

## Known Issues (v1.7.0)

Three upstream YAML bugs fixed automatically by `scripts/deploy-kubeflow.sh`:

| File | Fix |
|------|-----|
| `cluster.yaml` | Remove deprecated `metadata.clusterName` field |
| `nodepool.yaml` | Remove deprecated `metadata.clusterName` field |
| `kubeflow.org_profiles.yaml` | Remove spurious `creationTimestamp: null` |

## Cleanup

```bash
# Full teardown — kubeflow first, then management
bash scripts/cleanup.sh
```

## Tech Stack

**GCP:** GKE · Anthos Config Controller · Anthos Service Mesh · IAP · Cloud Build
**ML Platform:** Kubeflow Pipelines · KFServe · Jupyter Hub
**Infrastructure:** Istio · Config Connector (KCC) · kpt · kustomize
**Compute:** Intel Xeon C3 (AVX-512 VNNI · custom IPU offload)
