output "cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.kubeflow.name
}

output "cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = google_container_cluster.kubeflow.endpoint
  sensitive   = true
}

output "get_credentials_command" {
  description = "Command to configure kubectl"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.kubeflow.name} --zone ${var.zone} --project ${var.project_id}"
}

output "node_pool_machine_type" {
  description = "Intel Xeon C3 instance type in use"
  value       = google_container_node_pool.intel_xeon.node_config[0].machine_type
}
