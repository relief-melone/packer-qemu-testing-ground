packer {
  required_plugins {
    qemu = {
      version = ">= 1.0.10"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

variable "ubuntu_version" {
    type = string
    default = "22.04.3"
}

variable "ubuntu_iso_file" {
    type = string
    default = "ubuntu-22.04.3-live-server-amd64.iso"
}

variable "vm_template_name" {
    type = string
    default = "ubuntu"
}

locals {
    image_version = "0.1.0"

    vm_name = "${var.vm_template_name}-${var.ubuntu_version}-${local.image_version}"
    output_dir = "output/${local.vm_name}"
}

source "qemu" "my_image" {
    vm_name     = "${local.vm_name}"
    
    iso_url      = "https://releases.ubuntu.com/${var.ubuntu_version}/${var.ubuntu_iso_file}"
    iso_checksum = "file:https://releases.ubuntu.com/${var.ubuntu_version}/SHA256SUMS"

    # Location of Cloud-Init / Autoinstall Configuration files
    # Will be served via an HTTP Server from Packer
    http_directory = "http"

    boot_command = [
        "<spacebar><wait><spacebar><wait><spacebar><wait><spacebar><wait><spacebar><wait>",
        "e<wait>",
        "<down><down><down><end>",
        " autoinstall ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/",
        "<f10>"
    ]
    
    boot_wait = "5s"

    # QEMU specific configuration
    cpus             = 4
    memory           = 4096
    accelerator      = "kvm" # use none here if not using KVM
    disk_size        = "30G"
    disk_compression = true
    format           = "qcow2"

    # Final Image will be available in `output/packerubuntu-*/`
    output_directory = "${local.output_dir}"

    # SSH configuration so that Packer can log into the Image
    ssh_password    = "packerubuntu"
    ssh_username    = "admin"
    ssh_timeout     = "20m"
    shutdown_command = "echo 'packerubuntu' | sudo -S shutdown -P now"
    headless        = true # NOTE: set this to true when using in CI Pipelines
}

build {
    name    = "custom_build"
    sources = [ "source.qemu.my_image" ]

    # Wait till Cloud-Init has finished setting up the image on first-boot
    provisioner "shell" {
        inline = [
            "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for Cloud-Init...'; sleep 1; done" 
        ]
    }

    # Finally Generate a Checksum (SHA256) which can be used for further stages in the `output` directory
    post-processor "checksum" {
        checksum_types      = [ "sha256" ]
        output              = "${local.output_dir}/${local.vm_name}.{{.ChecksumType}}"
        keep_input_artifact = true
    }
}