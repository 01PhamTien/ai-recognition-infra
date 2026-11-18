variable "vm_user" {
  description = "User quan tri SSH tren cac VM Ubuntu"
  type        = string
  default     = "devops"
}

variable "ssh_private_key_path" {
  description = "Duong dan toi SSH private key tren may chay Terraform"
  type        = string
  default     = "~/.ssh/id_ed25519"
}

variable "k3s_server" {
  description = "Thong tin may ao Control Plane"
  type = object({
    hostname = string
    ip       = string
  })
  default = {
    hostname = "k3s-server"
    ip       = "192.168.174.101"
  }
}

variable "k3s_agent" {
  description = "Thong tin may ao Worker Node"
  type = object({
    hostname = string
    ip       = string
  })
  default = {
    hostname = "k3s-agent"
    ip       = "192.168.174.102"
  }
}
