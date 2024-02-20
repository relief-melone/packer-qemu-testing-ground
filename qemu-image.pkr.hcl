packer {
  required_plugins {
    qemu = {
      version = ">= 1.0.10"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

variable "ubuntu_version" {
  type    = string
  default = "22.04.3"
}

variable "ubuntu_iso_file" { 
  type    = string 
  default = "ubuntu-22.04.3-live-server-amd64.iso" 
} 

variable "vm_template_name" { 
  type    = string 
  default = "ubuntu" 
} 

variable "source_headless" { 
  type    = bool 
  default = false 
} 

variable "source_accelerator" { 
  type    = string 
  default = "kvm" 
} 

locals { 
  image_version = "0.1.0" 
  vm_name    = "${var.vm_template_name}-${var.ubuntu_version}-${local.image_version}" 
  output_dir = "output/${local.vm_name}" 
} 

source "qemu" "my_image" { 
  vm_name = "${local.vm_name}.qcow2" 
  iso_url      = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img" 
  iso_checksum = "file:https://cloud-images.ubuntu.com/jammy/current/SHA256SUMS" # Location of Cloud-Init / Autoinstall Configuration files Will be served via an HTTP Server from Packer http_directory = "http" #  

#  boot_command = [ "<spacebar><wait><spacebar><wait><spacebar><wait><spacebar><wait><spacebar><wait>", "e<wait>",
#    "<down><down><down><end>",
#    " autoinstall ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/",
#    "<f10>"
#  ]

  boot_wait = "5s"

  # QEMU specific configuration
  cpus             = 6
  memory           = 8192
  accelerator      = var.source_accelerator # use none here if not using KVM
  disk_size        = "30G"
  disk_compression = true
  disk_image       = true
  disk_interface   = "virtio"
  format           = "qcow2"

  cd_files = [ "./http/user-data", "./http/meta-data" ]
  cd_label = "cidata"

  vga="virtio"

  # Final Image will be available in `output/packerubuntu-*/`
  output_directory = "${local.output_dir}"

  # SSH configuration so that Packer can log into the Image
  ssh_password     = "packer"
  ssh_username     = "user"
  ssh_timeout      = "20m"
  shutdown_command = "echo 'packerubuntu' | sudo -S shutdown -P now"
  headless         = var.source_headless # NOTE: set this to true when using in CI Pipelines
  qemuargs         = [
#    ["-drive", "file=/tmp/temp/jammy-server-cloudimg-amd64.img,if=virtio,format=qcow2" ]
#    ["-m", "12G"], 
#    ["-smp", "8"], 
#    ["-vga", "virtio"],
#    ["-cdrom", "seed.img"], 
    ["-serial", "mon:stdio"], 
#    ["-smbios", "type=1,serial=ds=nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/"]
  ]
}

build {
  name    = "custom_build"
  sources = ["source.qemu.my_image"]

  #provisioner "shell-local" {
  #  inline = [
  #    "genisoimage -output cidata.iso",
  #    "-input-charset utf8",
  #    "-volid cidata",
  #    "-joliet -r user-data meta-data"
  #  ]
  #}

  # Wait till Cloud-Init has finished setting up the image on first-boot
  provisioner "shell" {
    inline = [
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for Cloud-Init...'; sleep 1; done"
    ]
  }

  provisioner "file" {
    source      = "scripts/nginx.service"
    destination = "/tmp/nginx.service"
  }

  provisioner "file" {
    source      = "scripts/bin"
    destination = "/tmp/"
  }

  provisioner "shell" {
    script = "scripts/install_dependencies.sh"
  }

  provisioner "shell" {
    inline = [
      "sudo mv /tmp/nginx.service /etc/systemd/system/nginx.service",
      "sudo mv /tmp/bin/* /usr/bin/",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable nginx.service"
    ]
  }

  # Finally Generate a Checksum (SHA256) which can be used for further stages in the `output` directory
  post-processor "checksum" {
    checksum_types      = ["sha256"]
    output              = "${local.output_dir}/${local.vm_name}.{{.ChecksumType}}"
    keep_input_artifact = true
  }
}
