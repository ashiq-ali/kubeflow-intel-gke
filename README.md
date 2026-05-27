# kubeflow-intel-gke

> Production Kubeflow deployment on GKE with Intel Xeon C3 instances — automated bootstrap, Anthos Config Controller, Istio service mesh, and Identity-Aware Proxy.

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![GKE](https://img.shields.io/badge/GKE-Kubeflow_v1.7-4285F4?logo=googlecloud&logoColor=white)](https://github.com/googlecloudplatform/kubeflow-distribution)
[![Intel](https://img.shields.io/badge/Intel-Xeon_C3-0071C5?logo=intel&logoColor=white)](https://cloud.google.com/compute/docs/general-purpose-machines#c3_series)
[![Terraform](https://img.shields.io/badge/Terraform-≥1.5-7B42BC?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![CI](https://img.shields.io/github/actions/workflow/status/ashiq-ali/kubeflow-intel-gke/validate.yml?label=CI)](https://github.com/ashiq-ali/kubeflow-intel-gke/actions)

---

## Table of Contents

- [Overview](#overview)
- [Why Intel Xeon C3?](#why-intel-xeon-c3)
- [Architecture](#architecture)
- [Repository Structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [Step-by-Step Deployment](#step-by-step-deployment)
  - [1. Clone and configure](#1-clone-and-configure)
  - [2. Bootstrap GCP project](#2-bootstrap-gcp-project)
  - [3. Configure OAuth](#3-configure-oauth)
  - [4. Deploy management cluster](#4-deploy-management-cluster)
  - [5. Deploy Kubeflow cluster](#5-deploy-kubeflow-cluster)
  - [6. Access Kubeflow UI](#6-access-kubeflow-ui)
- [Configuration Reference](#configuration-reference)
- [Choosing an Intel C3 Instance Type](#choosing-an-intel-c3-instance-type)
- [What Gets Deployed](#what-gets-deployed)
- [Known Issues and Fixes](#known-issues-and-fixes)
- [Troubleshooting](#troubleshooting)
- [Cleanup](#cleanup)
- [Cost Estimate](#cost-estimate)
- [Alternative: Terraform-only Deployment](#alternative-terraform-only-deployment)

---

## Overview

This repository automates the deployment of [Kubeflow](https://www.kubeflow.org/) — the ML platform for Kubernetes — on Google Kubernetes Engine using **Intel Xeon Scalable (C3) instances**. It handles the full lifecycle:

- Enabling all required GCP APIs
- Deploying an Anthos Config Controller management cluster
- Deploying a Kubeflow workload cluster with Intel C3 nodes
- Automatically patching known upstream YAML bugs (v1.7.0)
- Configuring IAP-secured access to the Kubeflow UI
- Teardown in the correct dependency order

You can have a fully working Kubeflow installation in **~25 minutes** with a single command sequence.

---

## Why Intel Xeon C3?

Google Cloud's **C3 machines** run on 4th Gen Intel Xeon Scalable processors and offer several advantages for ML workloads:

| Feature | Benefit |
|---------|---------|
| **AVX-512 VNNI** | Accelerates INT8 inference — up to 4× vs AVX2 |
| **Intel IPU** (Infrastructure Processing Unit) | Offloads networking/storage from the CPU, freeing cores for ML |
| **High memory bandwidth** | Critical for data loading in training loops |
| **Up to 192 vCPUs / 1.5TB RAM** | Large-scale distributed training without GPUs |
| **DDR5 memory** | ~50% higher bandwidth vs DDR4 in N2 instances |

For CPU-only ML workloads (inference, feature engineering, small model training), C3 instances often deliver **better price-performance than GPUs** for batch jobs.

---

## Architecture

```
                        ┌──────────────────────────────────────────────────────┐
                        │                    GCP Project                        │
                        │                                                        │
                        │   ┌─────────────────────────────────┐                 │
                        │   │      Management Cluster          │                 │
                        │   │   (Anthos Config Controller)     │                 │
                        │   │                                  │                 │
                        │   │   • Provisions GCP resources     │                 │
                        │   │     via Kubernetes CRDs          │                 │
                        │   │   • 3× e2-standard-2 nodes       │                 │
                        │   └──────────────┬──────────────────┘                 │
                        │                  │ provisions                          │
                        │                  ▼                                     │
                        │   ┌─────────────────────────────────┐                 │
                        │   │       Kubeflow Cluster           │                 │
                        │   │   Intel Xeon C3 node pool        │                 │
                        │   │                                  │                 │
                        │   │  ┌──────────┐  ┌─────────────┐  │                 │
                        │   │  │  Istio   │  │     IAP     │  │                 │
                        │   │  │  (mesh)  │  │  (auth)     │  │                 │
                        │   │  └────┬─────┘  └──────┬──────┘  │                 │
                        │   │       └────────────────┘         │                 │
                        │   │                │                  │                 │
                        │   │                ▼                  │                 │
                        │   │  ┌──────────────────────────┐    │                 │
                        │   │  │      Kubeflow UI          │    │                 │
                        │   │  ├──────────────────────────┤    │                 │
                        │   │  │  Pipelines  │  Notebooks  │    │                 │
                        │   │  │  KFServe   │  Katib      │    │                 │
                        │   │  └──────────────────────────┘    │                 │
                        │   └─────────────────────────────────┘                 │
                        └──────────────────────────────────────────────────────┘
```

**Two-cluster model explained:**

The management cluster runs Anthos Config Controller, which is a hosted version of Config Connector (KCC). It manages GCP resources (VPCs, GKE clusters, IAM bindings) via Kubernetes CRDs — meaning your infrastructure is declared as Kubernetes objects and reconciled continuously. The Kubeflow cluster is what KCC provisions, and it hosts all ML workloads.

---

## Repository Structure

```
kubeflow-intel-gke/
│
├── scripts/
│   ├── bootstrap.sh         # Enable APIs, init ASM, configure IAM
│   ├── deploy-mgmt.sh       # Deploy Anthos Config Controller cluster
│   ├── deploy-kubeflow.sh   # Deploy Kubeflow on Intel C3 nodes
│   └── cleanup.sh           # Teardown in correct dependency order
│
├── management/
│   ├── env.sh.example       # Template — copy to env.sh (gitignored)
│   └── kpt-set.sh           # Apply kpt setters to management manifests
│
├── kubeflow/
│   ├── env.sh.example       # Template — copy to env.sh (gitignored)
│   └── kpt-set.sh           # Apply kpt setters to Kubeflow manifests
│
├── terraform/               # Alternative IaC path (optional)
│   ├── main.tf              # VPC, GKE cluster, Intel C3 node pool
│   ├── variables.tf
│   └── outputs.tf
│
└── .github/
    └── workflows/
        └── validate.yml     # CI: shellcheck + terraform validate
```

---

## Prerequisites

### Tools

| Tool | Minimum Version | Install |
|------|----------------|---------|
| `gcloud` CLI | latest | [Install guide](https://cloud.google.com/sdk/docs/install) |
| `kubectl` | ≥ 1.27 | `gcloud components install kubectl` |
| `kpt` | ≥ 1.0 | `gcloud components install kpt` |
| `kustomize` | ≥ 5.0 | `brew install kustomize` or [releases](https://github.com/kubernetes-sigs/kustomize/releases) |
| `git` | any | pre-installed on most systems |

> **Tip:** Google Cloud Shell has all of these pre-installed. If you want zero local setup, use Cloud Shell at [shell.cloud.google.com](https://shell.cloud.google.com).

### GCP Requirements

- A GCP project with **Owner** role
- Billing enabled on the project
- Quota for C3 instances in your target region (`us-central1` by default). Request a quota increase at `IAM & Admin → Quotas` if needed.

### Authenticate locally

```bash
gcloud auth login
gcloud auth application-default login
```

---

## Step-by-Step Deployment

### 1. Clone and configure

```bash
git clone https://github.com/ashiq-ali/kubeflow-intel-gke.git
cd kubeflow-intel-gke

# Create management cluster config
cp management/env.sh.example management/env.sh

# Create Kubeflow cluster config
cp kubeflow/env.sh.example kubeflow/env.sh
```

Edit `management/env.sh`:

```bash
export MGMT_PROJECT=my-gcp-project   # Your GCP project ID
export MGMT_NAME=kubeflow-mgmt       # Name for the management cluster
export LOCATION=us-central1          # Must support Anthos Config Controller
```

Leave `kubeflow/env.sh` for now — you'll fill in `CLIENT_ID` and `CLIENT_SECRET` after step 3.

---

### 2. Bootstrap GCP project

```bash
bash scripts/bootstrap.sh
```

This script:
- Sets your active GCP project
- Enables all 10 required APIs (takes ~2 minutes)
- Initialises Anthos Service Mesh
- Grants the Cloud Build service account required roles
- Prints instructions for the manual OAuth step

---

### 3. Configure OAuth

Kubeflow uses Google OAuth + Identity-Aware Proxy to secure its UI. This step requires the GCP Console:

1. Go to **APIs & Services → OAuth Consent Screen**
   - User Type: **External**
   - Fill in app name, support email
   - Add authorised domain: `<YOUR_PROJECT_ID>.cloud.goog`

2. Go to **APIs & Services → Credentials → Create Credentials → OAuth 2.0 Client ID**
   - Application type: **Web application**
   - Add authorised redirect URI:
     ```
     https://iap.googleapis.com/v1/oauth/clientIds/<CLIENT_ID>:handleRedirect
     ```
   - Save the **Client ID** and **Client Secret**

3. Add them to `kubeflow/env.sh`:
   ```bash
   export CLIENT_ID=<paste-client-id>
   export CLIENT_SECRET=<paste-client-secret>
   ```

4. Optionally change the instance type in `kubeflow/env.sh`:
   ```bash
   export KF_INSTANCE_TYPE=c3-standard-8   # See sizing guide below
   ```

---

### 4. Deploy management cluster

```bash
bash scripts/deploy-mgmt.sh
```

This will:
- Clone `kubeflow-distribution` at tag `v1.7.0`
- Apply kpt setters for your project/region
- Create the Anthos Config Controller cluster via `gcloud anthos config controller create`
- Configure kubectl context
- Grant owner permissions to the Config Connector service account

⏱ **Expected time: 8–12 minutes**

You will see output like:
```
==> Creating Anthos Config Controller cluster (this takes ~10 minutes)...
...
✓ Management cluster deployed: kubeflow-mgmt
  Next: bash scripts/deploy-kubeflow.sh
```

---

### 5. Deploy Kubeflow cluster

```bash
bash scripts/deploy-kubeflow.sh
```

This will:
- Pull upstream Kubeflow manifests
- Apply kpt setters for your project, zone, OAuth credentials
- **Automatically patch 3 known v1.7.0 upstream YAML bugs** (see [Known Issues](#known-issues-and-fixes))
- Override the node pool machine type to your chosen Intel C3 instance
- Apply KCC resources (creates VPC, GKE cluster in GCP)
- Wait for GKE cluster to reach `RUNNING` state
- Deploy Kubeflow workloads — retries up to 3× on webhook timeout errors
- Grant your account IAP access
- Print the Kubeflow URL

⏱ **Expected time: 15–20 minutes**

---

### 6. Access Kubeflow UI

Once deployment completes, get your URL:

```bash
kubectl -n istio-system get ingress
```

Output:
```
NAME            CLASS   HOSTS                                          ADDRESS        PORTS   AGE
envoy-ingress   <none>  kubeflow.endpoints.my-project.cloud.goog      34.x.x.x       80      5m
```

Open `https://kubeflow.endpoints.<YOUR_PROJECT_ID>.cloud.goog` in your browser. You will be prompted to sign in with your Google account (the one granted IAP access).

> **Note:** DNS propagation can take 2–5 minutes after the ingress is created.

To grant access to additional users:

```bash
gcloud projects add-iam-policy-binding "${KF_PROJECT}" \
  --member="user:colleague@example.com" \
  --role=roles/iap.httpsResourceAccessor
```

Verify all pods are running:

```bash
kubectl -n kubeflow get pods
```

Expected output (all pods `Running` or `Completed`):

```
NAME                                              READY   STATUS    RESTARTS   AGE
admission-webhook-deployment-xxx                  1/1     Running   0          10m
centraldashboard-xxx                              1/1     Running   0          10m
jupyter-web-app-deployment-xxx                    1/1     Running   0          10m
katib-controller-xxx                              1/1     Running   0          10m
kfp-api-server-xxx                                2/2     Running   0          10m
kfp-ui-xxx                                        2/2     Running   0          10m
...
```

---

## Configuration Reference

### management/env.sh

| Variable | Default | Description |
|----------|---------|-------------|
| `MGMT_PROJECT` | — | GCP project ID for the management cluster |
| `MGMT_NAME` | `kubeflow-mgmt` | Name of the Anthos Config Controller cluster |
| `LOCATION` | `us-central1` | Region (must support Anthos CC — see [supported regions](https://cloud.google.com/anthos-config-management/docs/how-to/config-controller-setup#location)) |

### kubeflow/env.sh

| Variable | Default | Description |
|----------|---------|-------------|
| `KF_PROJECT` | — | GCP project ID for Kubeflow |
| `KF_NAME` | `kubeflow` | Name of the Kubeflow GKE cluster |
| `ZONE` | `us-central1-a` | Zone for the GKE cluster |
| `REGION` | `us-central1` | Region |
| `CLIENT_ID` | — | OAuth 2.0 Client ID (from GCP Console) |
| `CLIENT_SECRET` | — | OAuth 2.0 Client Secret |
| `KF_INSTANCE_TYPE` | `c3-standard-8` | Intel Xeon C3 machine type |
| `KF_NODE_COUNT` | `2` | Number of nodes in the Kubeflow node pool |
| `MGMTCTXT` | `kubeflow-mgmt` | kubectl context name for the management cluster |

---

## Choosing an Intel C3 Instance Type

| Machine Type | vCPUs | RAM | Use Case |
|-------------|-------|-----|----------|
| `c3-standard-4` | 4 | 16 GB | Dev/test, light workloads |
| `c3-standard-8` | 8 | 32 GB | **Recommended starting point** |
| `c3-standard-22` | 22 | 88 GB | Mid-size model training |
| `c3-standard-44` | 44 | 176 GB | Large model training |
| `c3-standard-88` | 88 | 352 GB | Distributed training, LLM fine-tuning |
| `c3-standard-176` | 176 | 704 GB | Largest single-node ML jobs |

All C3 machines include **AVX-512 VNNI** for accelerated INT8 inference and are backed by **Intel IPUs** that offload network/storage processing from the main CPU cores.

Set your choice in `kubeflow/env.sh`:

```bash
export KF_INSTANCE_TYPE=c3-standard-22
```

---

## What Gets Deployed

Once complete, your Kubeflow cluster includes:

| Component | Description |
|-----------|-------------|
| **Central Dashboard** | Unified web UI for all Kubeflow components |
| **Jupyter Notebooks** | Managed notebook servers with configurable CPU/memory |
| **Kubeflow Pipelines** | DAG-based ML workflow orchestration |
| **KFServe** | Model serving — REST/gRPC endpoints for trained models |
| **Katib** | Hyperparameter tuning and neural architecture search |
| **Training Operators** | TFJob, PyTorchJob, MXJob for distributed training |
| **Istio** | Service mesh — mTLS, traffic management, observability |
| **IAP** | Identity-Aware Proxy — Google account authentication |

---

## Known Issues and Fixes

`deploy-kubeflow.sh` automatically applies these patches to `kubeflow-distribution v1.7.0`:

| File | Bug | Fix Applied |
|------|-----|-------------|
| `common/cluster/upstream/cluster.yaml` | Deprecated `metadata.clusterName` field causes apply failure | Field removed |
| `common/cluster/upstream/nodepool.yaml` | Same deprecated field | Field removed |
| `apps/profiles/upstream/crd/bases/kubeflow.org_profiles.yaml` | Spurious `creationTimestamp: null` causes CRD rejection | Line removed |

These patches are applied in-place before `make apply` runs. They have been upstreamed — later versions of `kubeflow-distribution` should not require them.

---

## Troubleshooting

### `make apply` fails with webhook timeout

**Symptom:**
```
Error from server (Timeout): error when creating "...": context deadline exceeded
```

**Cause:** Admission webhooks are not yet ready when Kubeflow resources are applied — a race condition on first install.

**Fix:** `deploy-kubeflow.sh` retries up to 3 times automatically. If it still fails, run manually:
```bash
cd ~/kubeflow-distribution/kubeflow && make apply
```

---

### Kubeflow UI returns 403

**Symptom:** Browser shows `Error 403: access_denied` after OAuth login.

**Cause:** Your Google account hasn't been granted the IAP role.

**Fix:**
```bash
gcloud projects add-iam-policy-binding "${KF_PROJECT}" \
  --member="user:your-email@gmail.com" \
  --role=roles/iap.httpsResourceAccessor
```

---

### Pods stuck in `Pending`

**Symptom:** `kubectl -n kubeflow get pods` shows pods in `Pending` state.

**Diagnosis:**
```bash
kubectl -n kubeflow describe pod <pod-name> | grep -A5 Events
```

**Common causes:**

| Error | Fix |
|-------|-----|
| `Insufficient cpu` | Increase `KF_NODE_COUNT` or use larger `KF_INSTANCE_TYPE` |
| `Insufficient memory` | Same as above |
| `no nodes available` | Check node pool is `RUNNING`: `gcloud container node-pools list --cluster=${KF_NAME} --zone=${ZONE}` |

---

### ASM initialisation returns non-empty response

**Symptom:** `scripts/bootstrap.sh` shows unexpected output from the ASM init endpoint.

**Cause:** The project may need a temporary cluster before ASM can be initialised.

**Fix:** Create and immediately delete a temporary cluster:
```bash
gcloud container clusters create temp-cluster --zone us-central1-a --num-nodes=1
gcloud container clusters delete temp-cluster --zone us-central1-a --quiet
# Then re-run bootstrap.sh
```

---

### C3 instances not available in zone

**Symptom:** Node pool creation fails with quota or availability error.

**Fix:** Check C3 availability in your target zone:
```bash
gcloud compute machine-types list --filter="name~c3" --zones=us-central1-a
```

Try an adjacent zone (`us-central1-b`, `us-central1-c`) or request a quota increase.

---

## Cleanup

```bash
bash scripts/cleanup.sh
```

The cleanup script tears down resources in the correct order:
1. Deletes the `kubeflow` namespace and waits for termination
2. Runs `make delete` to remove KCC-managed GCP resources (VPC, GKE cluster)
3. Removes the project namespace from the management cluster
4. Deletes the Anthos Config Controller management cluster

> **Cost note:** GKE clusters continue to incur charges until fully deleted. Verify deletion in the GCP Console under `Kubernetes Engine → Clusters`.

---

## Cost Estimate

Approximate costs for a standard deployment in `us-central1` (USD/month):

| Resource | Spec | Est. Cost |
|----------|------|-----------|
| Management cluster | 3× e2-standard-2 | ~$75 |
| Kubeflow node pool | 2× c3-standard-8 | ~$280 |
| Persistent disks | ~200 GB SSD | ~$35 |
| Load balancer | 1× L7 LB | ~$20 |
| **Total** | | **~$410/month** |

Costs scale linearly with node count and machine type. For development, use `c3-standard-4` with `KF_NODE_COUNT=1` to reduce costs to ~$200/month.

---

## Alternative: Terraform-only Deployment

For teams that prefer pure Terraform IaC, the `terraform/` directory provisions the VPC and GKE cluster with an Intel C3 node pool directly — without Anthos Config Controller:

```bash
cd terraform

# Create a terraform.tfvars file
cat > terraform.tfvars << EOF
project_id   = "my-gcp-project"
region       = "us-central1"
zone         = "us-central1-a"
machine_type = "c3-standard-8"
node_count   = 2
EOF

terraform init
terraform plan
terraform apply
```

After the cluster is created, follow steps 3, 5 (skipping `make apply-kcc`), and 6 to deploy Kubeflow workloads.

---

## Tech Stack

**Compute:** Intel Xeon C3 (AVX-512 VNNI · DDR5 · custom IPU offload)
**Platform:** GKE · Anthos Config Controller · Anthos Service Mesh
**Networking:** Istio · Identity-Aware Proxy · Cloud Load Balancing
**ML Platform:** Kubeflow Pipelines · KFServe · Katib · Training Operators · Jupyter Hub
**IaC:** kpt · kustomize · Config Connector · Terraform
