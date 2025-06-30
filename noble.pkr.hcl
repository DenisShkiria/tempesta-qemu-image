variable "ssh_password" {
  type    = string
  default = "ubuntu"
}

variable "ssh_username" {
  type    = string
  default = "ubuntu"
}

packer {
  required_plugins {
    qemu = {
      version = ">= 1.1.3"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

source "qemu" "noble" {
  accelerator      = "kvm"
  boot_command     = []
  disk_compression = true
  disk_interface   = "virtio"
  disk_image       = true
  disk_size        = "50G"
  format           = "qcow2"
  headless         = "true"
  iso_checksum     = "sha256:92d2c4591af9a82785464bede56022c49d4be27bde1bdcf4a9fccc62425cda43"
  iso_url          = "https://cloud-images.ubuntu.com/noble/20250610/noble-server-cloudimg-amd64.img"
  net_device       = "virtio-net"
  output_directory = "artifacts/qemu/noble"
  cd_files         = ["./cloud-init-config/*"]
  cd_label         = "cidata"
  communicator     = "ssh"
  shutdown_command = "echo '${var.ssh_password}' | sudo -S shutdown -P now"
  ssh_password     = var.ssh_password
  ssh_username     = var.ssh_username
  ssh_timeout      = "10m"
  qemuargs = [
    ["-m", "8196M"],
    ["-smp", "4"]
  ]
}

build {
  sources = ["source.qemu.noble"]

  provisioner "shell" {
    script = "scripts/setup-serial-autologin.sh"
    execute_command = "sudo /bin/sh {{.Path}}"
  }

  provisioner "shell" {
    script = "scripts/build-kernel.sh"
    execute_command = "sudo /bin/sh {{.Path}}"
  }
}
