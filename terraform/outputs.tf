output "k3s_api_endpoint" {
  description = "Dia chi Kubernetes API Server"
  value       = "https://:6443"
}

output "cluster_nodes" {
  description = "Danh sach hostname va IP cac node trong cluster"
  value = {
    server = " ()"
    agent  = " ()"
  }
}
