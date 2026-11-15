variable "ssh_user" {
  default = "devops"
}

variable "ssh_private_key_path" {
  default = "C:/Users/ASUS/.ssh/id_ed25519"
}

variable "k3s_nodes" {
  type = map(string)
  default = {
    "k3s-server" = "192.168.174.101"
    "k3s-agent"  = "192.168.174.102"
  }
}
