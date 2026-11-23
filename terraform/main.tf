locals {
  node        = "furina"
  datastore   = "nvme-02"
  template_id = 99994 # template ubuntu24
  mgmt_gw     = "192.168.19.1"

  # vmid 
  vmid = {
    deployer   = 4061
    synology   = 4062
    controller = 4063
  }

  # compute + ceph (HCI)
  computes = {
    "01" = 4064
    "02" = 4065
    "03" = 4066
  }
}

# === [Ubuntu 24 Deployer VM] ===
resource "proxmox_virtual_environment_vm" "kp_ubuntu24_deployer" {
  node_name = local.node
  vm_id     = local.vmid.deployer
  name      = "kp-ubuntu24-deployer"
  tags      = ["openstack", "kp", "jumphost"]

  clone {
    vm_id        = local.template_id
    datastore_id = local.datastore
    full         = true
  }

  agent { enabled = true }

  cpu {
    cores = 2
    type  = "host"
  }

  memory { dedicated = 4096 }

  disk {
    datastore_id = local.datastore
    interface    = "scsi0"
    size         = 80
    discard      = "on"
    ssd          = true
  }

  network_device { bridge = "vmbr0" } # management

  serial_device { device = "socket" }
  vga { type = "serial0" }

  initialization {
    datastore_id = local.datastore

    ip_config { # management
      ipv4 {
        address = "192.168.19.${local.vmid.deployer % 100}/24"
        gateway = local.mgmt_gw
      }
    }

    user_account {
      username = "rizwan"
      keys     = [var.ssh_proxmox_key]
    }
  }

  on_boot = true
}

# === [Synology Central Storage VM] ===
resource "proxmox_virtual_environment_vm" "kp_synology_iscsi" {
  node_name = local.node
  vm_id     = local.vmid.synology
  name      = "kp-synology-iscsi"
  tags      = ["openstack", "kp"]

  bios          = "seabios"
  scsi_hardware = "virtio-scsi-pci"
  boot_order    = ["sata0"]

  operating_system { type = "l26" }

  agent { enabled = false }

  cpu {
    cores   = 4
    sockets = 1
    type    = "host"
    numa    = false
  }

  memory {
    dedicated = 8192
    floating  = 2048
  }

  # boot disk (loader synology-v4.0.5.img)
  disk {
    datastore_id = local.datastore
    file_id      = "iso-template:iso/synology-v4.0.5.img"
    interface    = "sata0"
    size         = 50
  }

  # data disk 4x 50gb (nvme-02)
  disk {
    datastore_id = local.datastore
    interface    = "sata1"
    size         = 50
    ssd          = true
  }
  disk {
    datastore_id = local.datastore
    interface    = "sata2"
    size         = 50
    ssd          = true
  }
  disk {
    datastore_id = local.datastore
    interface    = "sata3"
    size         = 50
    ssd          = true
  }
  disk {
    datastore_id = local.datastore
    interface    = "sata4"
    size         = 50
    ssd          = true
  }

  network_device { bridge = "vmbr0" }  # management
  network_device { bridge = "dsmos1" } # storage01
  network_device { bridge = "dsmos2" } # storage02

  lifecycle {
    ignore_changes = [disk]
  }
}

# === [OpenStack Controller 01] ===
resource "proxmox_virtual_environment_vm" "kp_openstack_controller_01" {
  node_name = local.node
  vm_id     = local.vmid.controller
  name      = "kp-openstack-controller-01"
  tags      = ["openstack", "kp"]

  clone {
    vm_id        = local.template_id
    datastore_id = local.datastore
    full         = true
  }

  agent { enabled = true }

  cpu {
    cores = 4
    type  = "host"
  }

  memory { dedicated = 8192 }

  disk {
    datastore_id = local.datastore
    interface    = "scsi0"
    size         = 60
    discard      = "on"
    ssd          = true
  }

  network_device { bridge = "vmbr0" }  # management
  network_device { bridge = "intos1" } # internal openstack
  network_device { bridge = "dsmos1" } # storage01
  network_device { bridge = "dsmos2" } # storage02
  network_device { bridge = "vmbr0" }  # external provider

  serial_device { device = "socket" }
  vga { type = "serial0" }

  initialization {
    datastore_id = local.datastore

    ip_config { # management
      ipv4 {
        address = "192.168.19.${local.vmid.controller % 100}/24"
        gateway = local.mgmt_gw
      }
    }
    ip_config { # internal openstack
      ipv4 { address = "172.16.1.${local.vmid.controller % 100}/24" }
    }
    ip_config { # storage01
      ipv4 { address = "172.16.2.${local.vmid.controller % 100}/24" }
    }
    ip_config { # storage02
      ipv4 { address = "172.16.3.${local.vmid.controller % 100}/24" }
    }
    ip_config {} # external provider

    user_account {
      username = "rizwan"
      keys     = [var.ssh_proxmox_key]
    }
  }

  on_boot = true
}

# === [OpenStack Compute 01-03 + Ceph OSD (HCI)] ===
resource "proxmox_virtual_environment_vm" "kp_openstack_compute" {
  for_each = local.computes

  node_name = local.node
  vm_id     = each.value
  name      = "kp-openstack-compute-${each.key}"
  tags      = ["openstack", "kp", "ceph"]

  clone {
    vm_id        = local.template_id
    datastore_id = local.datastore
    full         = true
  }

  agent { enabled = true }

  cpu {
    cores = 8
    type  = "host"
  }

  memory { dedicated = 16384 }

  # root disk
  disk {
    datastore_id = local.datastore
    interface    = "scsi0"
    size         = 80
    discard      = "on"
    ssd          = true
  }

  # ceph osd 3x 50gb (nvme-02) -> scsi1..scsi3
  dynamic "disk" {
    for_each = [1, 2, 3]
    content {
      datastore_id = local.datastore
      interface    = "scsi${disk.value}"
      size         = 50
      discard      = "on"
      ssd          = true
    }
  }

  network_device { bridge = "vmbr0" }  # management
  network_device { bridge = "intos1" } # internal openstack
  network_device { bridge = "dsmos1" } # storage01
  network_device { bridge = "dsmos2" } # storage02
  network_device { bridge = "vmbr0" }  # external provider

  serial_device { device = "socket" }
  vga { type = "serial0" }

  initialization {
    datastore_id = local.datastore

    ip_config { # management
      ipv4 {
        address = "192.168.19.${each.value % 100}/24"
        gateway = local.mgmt_gw
      }
    }
    ip_config { # internal openstack
      ipv4 { address = "172.16.1.${each.value % 100}/24" }
    }
    ip_config { # storage01
      ipv4 { address = "172.16.2.${each.value % 100}/24" }
    }
    ip_config { # storage02
      ipv4 { address = "172.16.3.${each.value % 100}/24" }
    }
    ip_config {} # external provider

    user_account {
      username = "rizwan"
      keys     = [var.ssh_proxmox_key]
    }
  }

  on_boot = true
}