terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ── VPC ────────────────────────────────────────────────────────────────────────
resource "google_compute_network" "kubeflow" {
  name                    = "${var.kubeflow_cluster_name}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "kubeflow" {
  name          = "${var.kubeflow_cluster_name}-subnet"
  ip_cidr_range = "10.0.0.0/18"
  region        = var.region
  network       = google_compute_network.kubeflow.id

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.48.0.0/14"
  }
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.52.0.0/20"
  }

  private_ip_google_access = true
}

# ── GKE Cluster ────────────────────────────────────────────────────────────────
resource "google_container_cluster" "kubeflow" {
  name     = var.kubeflow_cluster_name
  location = var.zone

  network    = google_compute_network.kubeflow.name
  subnetwork = google_compute_subnetwork.kubeflow.name

  # Remove default node pool — we manage our own Intel C3 pool
  remove_default_node_pool = true
  initial_node_count       = 1

  min_master_version = var.k8s_version

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  addons_config {
    http_load_balancing {
      disabled = false
    }
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
  }

  release_channel {
    channel = "REGULAR"
  }
}

# ── Intel Xeon C3 Node Pool ────────────────────────────────────────────────────
resource "google_container_node_pool" "intel_xeon" {
  name       = "intel-xeon-c3"
  location   = var.zone
  cluster    = google_container_cluster.kubeflow.name
  node_count = var.node_count

  node_config {
    machine_type = var.machine_type   # c3-standard-8 (Intel Xeon, custom IPU)
    disk_size_gb = 200
    disk_type    = "pd-ssd"
    image_type   = "COS_CONTAINERD"

    # Workload Identity
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    labels = {
      workload = "kubeflow"
      cpu-type = "intel-xeon-c3"
    }

    # Intel AVX-512 VNNI is available on C3 without any extra config
    # Enable node local DNS for faster service discovery in ML workloads
    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }
}
