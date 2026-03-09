
build {
  name    = "ubuntu"
  sources = ["source.proxmox-iso.ubuntu-server"]


  # Proxmox cloud-init tweaks
  provisioner "file" {
    source      = "files/99-pve.cfg"
    destination = "/opt/99-pve.cfg"
  }

  provisioner "shell" {
    inline = ["mkdir -p /opt/scripts"]
  }

  provisioner "file" {
    source      = "scripts/"
    destination = "/opt/scripts/"
  }

  provisioner "shell" {
    inline = [
      "sudo chmod +x /opt/scripts/provision-redstack.sh",
      "cd /opt/scripts && sudo -E bash ./provision-redstack.sh"
    ]
  }

  provisioner "shell" {
    inline = ["sudo cp /opt/99-pve.cfg /etc/cloud/cloud.cfg.d/99-pve.cfg"]
  }
}
