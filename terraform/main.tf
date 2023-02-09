provider "vault" {
  address         = "http://127.0.0.1:8200/"
  skip_tls_verify = true
  token           = var.vault_token
}

# vc password store in vault
data "vault_generic_secret" "vcenterpass" {
  path = "vcenter/vcenterpass"
}

provider "vsphere" {
  user                 = var.vsphere_user
  password             = data.vault_generic_secret.vcenterpass.data["password"]
  vsphere_server       = var.vsphere_server
  allow_unverified_ssl = true
}

data "vsphere_datacenter" "dc" {
  name = var.vsphere_datacenter
}

data "vsphere_datastore" "datastore" {
  name          = var.vsphere_datastore
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_compute_cluster" "cluster" {
  name          = var.vsphere_cluster
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "network" {
  name          = var.vsphere_network
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_content_library" "iso_library" {
  name = var.iso_library
}

resource "random_id" "server" {
  byte_length = 8
}

# Upload iso file to content lib, note it will take time..
resource "vsphere_content_library_item" "photon_iso" {
  name        = "${var.photon_iso_catalog_name}-${random_id.server.hex}"
  description = "${var.photon_iso_catalog_name}-${random_id.server.hex}"
  file_url    = "${var.photon_iso_catalog_name}.iso"
  library_id  = data.vsphere_content_library.iso_library.id
  type        = "iso"
}

# Upload iso file to datacenter
# Note normally we would like to use content lib
# I open a bug to fix issue so we can boot VM with CDROM that uses iso from content library.
# For now we just use vsan datastore.
resource "vsphere_file" "photon_iso_upload" {
  datacenter         = var.vsphere_datacenter
  datastore          = var.vsphere_datastore
  source_file        = var.photon_iso_image_name
  destination_file   = "/ISO/${var.photon_iso_image_name}"
  create_directories = true
}

resource "vsphere_virtual_machine" "vm" {
  name                 = "foo01-${random_id.server.hex}"
  resource_pool_id     = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id         = data.vsphere_datastore.datastore.id
  num_cpus             = var.default_vm_cpu_size
  num_cores_per_socket = var.default_vm_num_cores_per_socket
  memory               = var.default_vm_mem_size
  guest_id             = "other3xLinux64Guest"
  latency_sensitivity  = var.default_vm_latency_sensitivity
  tools_upgrade_policy = "upgradeAtPowerCycle"
  # we set true so later we can adjsut if needed
  memory_hot_add_enabled = true
  cpu_hot_add_enabled    = true
  cpu_hot_remove_enabled = true
  # set zero , later will put to tfvars
  cpu_reservation = 0

  cdrom {
    datastore_id = data.vsphere_datastore.datastore.id
    path         = "/ISO/${var.photon_iso_image_name}"
  }

  network_interface {
    network_id = data.vsphere_network.network.id
  }
  disk {
    label            = "disk0"
    size             = var.default_vm_disk_size
    thin_provisioned = var.default_vm_disk_thin
  }
  depends_on = [vsphere_file.photon_iso_upload]

  extra_config = {
    # "guestinfo.metadata"          = base64encode(file("${path.cwd}/metadata.yaml"))
    # "guestinfo.metadata.encoding" = "base64"
    "guestinfo.userdata"          = base64encode(file("${path.cwd}/userdata.yaml"))
    "guestinfo.userdata.encoding" = "base64"
  }
}


#   triggers {
#     public_ip = vsphere_virtual_machine.vm.default_ip_address
#   }
# }

# Note make sure your DHCP env is stable. 
# We assume that network will allocate IP address.
resource "null_resource" "tinytkg" {
  depends_on = [vsphere_virtual_machine.vm]
  connection {
    type = "ssh"
    host = vsphere_virtual_machine.vm.default_ip_address
    user = "root"
    private_key = file(pathexpand("~/.ssh/id_rsa"))
    port  = "22"
    agent = false
  }

  # provisioner will start tinykube,  rpm pushed directly to ISO.
  provisioner "remote-exec" {
    inline = [
      "export PATH=$PATH:/usr/local/bin",
      "yum install -y ebtables ethtool socat conntrack apparmor-profiles rpm-build",
      "tinykube start --skip-phases=default-cni",
      "mkdir -p $HOME/.kube",
      "sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config",
      "sudo chown $(id -u):$(id -g) $HOME/.kube/config",
      "kubectl get deploy tigera-operator -n tigera-operator",
      "kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.24.1/manifests/tigera-operator.yaml",
      "kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.24.1/manifests/custom-resources.yaml"
    ]
  }
}

# Note make sure your DHCP env is stable. 
# Second null resource, we building all DPKD / kernel modules.
resource "null_resource" "dpdk" {
  depends_on = [vsphere_virtual_machine.vm]
  connection {
    type = "ssh"
    host = vsphere_virtual_machine.vm.default_ip_address
    user = "root"
    private_key = file(pathexpand("~/.ssh/id_rsa"))
    port  = "22"
    agent = false
  }

  # provisioner will start tinykube,  rpm pushed directly to ISO.
  provisioner "remote-exec" {
    inline = [
      "export PATH=$PATH:/usr/local/bin",
      "cd /root; mkdir -p build",
      "cd /root/build; git clone https://github.com/intel/intel-ipsec-mb.git",
      "cd intel-ipsec-mb; make -j 8",
      "make install; ldconfig",
      "yum -y install python3-libcap-ng python3-devel rdma-core-devel util-linux-devel zip zlib zlib-devel libxml2-devel libudev-devel",
      "pip3 install pyelftools sphinx",
      "cd /root/build; wget https://www.infradead.org/~tgr/libnl/files/libnl-3.2.25.tar.gz",
      "mkdir libnl",
      "tar -zxvf libnl-*.tar.gz -C libnl --strip-components=1",
      "cd /root/build/libnl; /configure --prefix=/usr",
      "make -j 8 && make install",
      "cd /root/build; git clone https://github.com/intel/isa-l",
      "cd /root/build/isa-l; chmod 700 autogen.sh && ./autogen.sh",
      "./configure",
      "make -j 8 && make install",
      "pip3 install pyelftools",
      "yum -y install stalld dkms linux-devel linux-rt-devel openssl-devel libmlx5",
      "ln -s /usr/src/linux-headers-$(uname -r)/ /usr/src/linux",
      "cd /root/build; wget http://fast.dpdk.org/rel/dpdk-21.11.tar.xz",
      "tar xf dpdk*",
      "cd /root/build/dpdk-21.11",
      "meson -Dplatform=native -Dexamples=all -Denable_kmods=true -Dkernel_dir=/lib/modules/$(uname -r) -Dibverbs_link=shared -Dwerror=true build",
      "ninja -C build -j 8",
      "cd /root/build/dpdk-21.11/build; ninja install; ldconfig"
    ]
  }
}

# Outputting the IP address of the new VM
output "photon_os_ip_address" {
  value = vsphere_virtual_machine.vm.default_ip_address
}