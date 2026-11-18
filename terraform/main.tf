terraform {
  required_version = ">= 1.5.0"
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

# Luu y: VMware Workstation Desktop khong ho tro API tao VM truc tiep.
# Terraform o day kiem tra ket noi SSH an toan va sinh Ansible inventory tu variables.
resource "null_resource" "verify_nodes_ssh" {
  for_each = {
    server = var.k3s_server
    agent  = var.k3s_agent
  }

  triggers = {
    node_ip   = each.value.ip
    node_name = each.value.hostname
  }

  connection {
    type        = "ssh"
    host        = each.value.ip
    user        = var.vm_user
    private_key = file(pathexpand(var.ssh_private_key_path))
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Ket noi SSH an toan thanh cong toi  ()'"
    ]
  }
}

resource "local_file" "ansible_inventory" {
  filename = "/../ansible/inventory.ini"
  content  = <<-EOT
    [k3s_server]
     ansible_host=

    [k3s_agent]
     ansible_host=

    [k3s_cluster:children]
    k3s_server
    k3s_agent

    [all:vars]
    ansible_user=
    ansible_ssh_private_key_file=
    ansible_python_interpreter=/usr/bin/python3
  EOT

  depends_on = [null_resource.verify_nodes_ssh]
}
