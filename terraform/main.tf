terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

resource "null_resource" "prepare_k3s_nodes" {
  for_each = var.k3s_nodes

  triggers = {
    node_ip = each.value
  }

  connection {
    type        = "ssh"
    user        = var.ssh_user
    host        = each.value
    private_key = file(var.ssh_private_key_path)
    timeout     = "30s"
  }

  provisioner "remote-exec" {
    inline = [
      "echo '=== Provisioning ${each.key} (${each.value}) ==='",
      "sudo swapoff -a",
      "sudo sed -i '/ swap / s/^/#/' /etc/fstab",
      "printf 'overlay\nbr_netfilter\n' | sudo tee /etc/modules-load.d/k8s.conf",
      "sudo modprobe overlay",
      "sudo modprobe br_netfilter",
      "printf 'net.bridge.bridge-nf-call-iptables  = 1\nnet.bridge.bridge-nf-call-ip6tables = 1\nnet.ipv4.ip_forward                 = 1\n' | sudo tee /etc/sysctl.d/k8s.conf",
      "sudo sysctl --system > /dev/null",
      "echo '=== Node ${each.key} Ready for k3s ==='"
    ]
  }
}

resource "local_file" "ansible_inventory" {
  depends_on = [null_resource.prepare_k3s_nodes]
  filename   = "${path.module}/../ansible/inventory.ini"
  content    = <<-EOT
    [k3s_server]
    k3s-server ansible_host=${var.k3s_nodes["k3s-server"]} ansible_connection=local

    [k3s_agent]
    k3s-agent ansible_host=${var.k3s_nodes["k3s-agent"]}

    [k3s_cluster:children]
    k3s_server
    k3s_agent

    [k3s_cluster:vars]
    ansible_user=${var.ssh_user}
    ansible_ssh_private_key_file=~/.ssh/id_ed25519
    ansible_ssh_common_args='-o StrictHostKeyChecking=no'
  EOT
}
