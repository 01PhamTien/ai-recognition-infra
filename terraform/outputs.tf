output "provisioned_nodes" {
  value = var.k3s_nodes
}

output "ansible_inventory_path" {
  value = local_file.ansible_inventory.filename
}
