
build {
  name    = "ubuntu"
  sources = ["source.proxmox-iso.ubuntu-server"]


  # Proxmox cloud-init tweaks
  provisioner "file" {
    source      = "files/99-pve.cfg"
    destination = "/tmp/99-pve.cfg"
  }

  # Red lab assistant payload
  provisioner "shell" {
    inline = ["mkdir -p /tmp/capstone-userstack"]
  }

  provisioner "file" {
    source      = "files/red-lab-assistant/"
    destination = "/tmp/capstone-userstack/red-lab-assistant"
  }

  provisioner "file" {
    source      = "files/red-lab-assistant.service"
    destination = "/tmp/capstone-userstack/red-lab-assistant.service"
  }

  provisioner "shell" {
    inline = ["mkdir -p /tmp/scripts"]
  }

  provisioner "file" {
    source      = "scripts/"
    destination = "/tmp/scripts/"
  }

  provisioner "shell" {
    inline = [
      "sudo chmod +x /tmp/scripts/provision-redstack.sh",
      "cd /tmp/scripts && sudo -E bash ./provision-redstack.sh"
    ]
  }

  provisioner "shell" {
    inline = ["sudo cp /tmp/99-pve.cfg /etc/cloud/cloud.cfg.d/99-pve.cfg"]
  }
}
