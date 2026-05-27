variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone for Kubeflow cluster"
  type        = string
  default     = "us-central1-a"
}

variable "kubeflow_cluster_name" {
  description = "Name of the Kubeflow GKE cluster"
  type        = string
  default     = "kubeflow"
}

variable "machine_type" {
  description = "Intel Xeon C3 instance type for Kubeflow nodes"
  type        = string
  default     = "c3-standard-8"
  # Options: c3-standard-8, c3-standard-22, c3-standard-44, c3-standard-88
}

variable "node_count" {
  description = "Number of nodes in the Kubeflow node pool"
  type        = number
  default     = 2
}

variable "k8s_version" {
  description = "Kubernetes version for GKE cluster"
  type        = string
  default     = "1.27"
}
