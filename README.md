# This is VMware VM and Bare-metal, Real time Photon build system.

The automated system is designed to work with a bare-metal host. (Dell) or with 
VMware VC environment. Note to have a consistent build. A builder build system 
generates ISO is used in both VM and Bare metal.    

In the case of a VM, the ISO is used to boot the VM and install OS from kick-start. 
i.e., it is an unattended installation.  Thus, In both cases, the automated build system, f
irst build a reference iso file.  

For example local directory contains ph4-rt-refresh.iso or system 
fetch the reference ISO from the web. 

## What it builds  ?

An automated system for VMware Real time Photon OS version 4 and 5 and 
consists build three phases. Make sure you familiar with Photon OS itself.
[Photon OS](https://github.com/vmware/photon)

It leverages build in Photon OS capability to install OS from 
kickstart installation.

Phase one system generates reference kick-start ISO. During this phase
the first step is to decide whether to build an online or offline version.

### Online version

Online version is the flavor when post kick-start phase. i.e., after the first 
reboot post-installation.  All post-install components polled from the internet. 
It first poll all toolchains required to compile dependencies, polls all drivers,  
git repos, DPDK, IPSEC lib, lib-nl, lib-isa, and many other libs from the internet. 
During this phase all RPMs, pip packages installed from internet.

### Offline version

In the offline version, all components are serialized to ISO and, after first boot, 
moved to / partition.

What serialized to offline dictated by configuration JSON files.
In offline directory.

[Specs]](https://github.com/spyroot/photon_rt/tree/main/offline)

All specs JSON files. For example for DPDK we need meson, nasm and ninja build system

additional_direct_rpms.json

'''json
[
  "ninja-build-1.10.2-2.ph4.x86_64",
  "meson-0.64.1-1.ph4.noarch",
  "nasm-2.15.05-1.ph4.x86_64"
]
'''
additional_git_clone.json
'''additional_git_clone.json
[
  "https://github.com/intel/isa-l",
  "https://github.com/spyroot/tuned.git",
  "https://github.com/intel/intel-ipsec-mb.git"
]
'''

'''additional_packages.json
[
  "docker"
]
'''

'''additional_rpms.json
[
  "docker"
]
'''

Additional files pushed during install
'''additional_files.json
{
  "additional_files": [
    {
      "/mnt/media/vcu1.tar.gz": "/vcu1.tar.gz"
    },
    {
      "/mnt/media/post.sh": "/post.sh"
    }
  ]
}
'''

'''additional_load_docker.json

Additional RPMS we install in online version.

'''additional_remote_rpms.json
  "wget -nc http://MY_HTTP_SERVER/MY.rpm -P /tmp/  >> /etc/postinstall"
''' 


## What customization option does it have?

Currently, system perform following.

* First it unattended install.
  * Bare metal leverage **idrac_ctl** first perform all BIOS customization.
  * Bare metal clear all pending BIOS state and boot generate ISO.
* Install latest mellanox driver upon first boot.
* Install latest intel IAVF driver.
* Pool kernel-rt source and link iavf and mellanox against latest rt.
* kernel-header and src update during install.
* The toolchain list is extensive. For example:, 
  * DPDK complied with support Mellanox, crypto (Intel IPSEC lib), and iFPGA and is ready for Intel Flexran.

* DPDK build with kernel module support.  
* VFIO and VFIO-PCI both enabled by default with SRIOV support.
* Build system detect numa topology and adjust system for HUGE PAGE support.
* All hugepages mounted and fstab adjusted.
* The build system automatically builds SRIOV VFs on multiply adapters from the list of PCI devices provided.
* Check **post.sh** variable $SRIOV_PCI_LIST
* Build system push ssh key from $HOME/.ssh/ thus after on the first boot can hook ansible.
* Build system adjust optimize kernel for real time.
  * In first boot system install tuned.
  * Install mus_rt profile optimized for real time. 
  * Initial setting  4 kernel thread allocated for general scheduler.
  * All other isolated for real time.
    * Default profile generated **mus_rt**
    * Profile setting intel_pstate=disable intel_iommu=on iommu=pt (Note idrac_ctl by default disable C state)
    * nosoftlockup tsc=reliable
    * Huge pages by default set to 16 pages and default size 1G
      * transparent_hugepage=never hugepages=16 default_hugepagesz=1G hugepagesz=1G 
    * **NOHZ** In full mode and set for all isolated cores
      * nohz_full=${isolated_cores} rcu_nocbs=${isolated_cores}
    * RCU_NOCB** set for isolated_cores
      * Logic behind this.  RCU callbacks are invoked in **softirq** context. 
        This imposes allocator deallocate memory.  (take cycles we don't want that)
        Check kernel.org docs for the rest

* Build system build default PTP configuration and enabled PTP on dedicate adapter.
  * CHeck **post.sh** variable PTP_ADAPTER,  note it PCI address.

  
* There are three main build scripts that exposed.
* **build_and_exec.sh**  Build a kick-start and all customization and docker container.
* **build_iso.sh** Build the final ISO file.
* **build_praller_boot.sh** (Optional bare-metal only) leverages idract_ctl and boots N hosts from final customized ISO via remote HTTP media and installs the real-time OS.

**build_and_exec.sh** first builds a workspace container and lands to a bash session insider a container.  That removes any requirement for a tools chains pre-install and you can run it on Mac/Linux/Win.. So the first step it builds, or pull from dockerhub the image,  generate kick start files, and builds a new ISO used for the unattended install.

Note **build_and_exec.sh** uses following json files to produce final kickstart.
* additional_direct_rpms.json  any rpms that we want to pull to the image. 
* additional_files.json a files that we need inject into the ISO.
* additional_load_docker.json a files that we injected can be loaded on first boot.
* additional_packages.json  additional packages we need istall.

All mentioned files contain a JSON list.

In the case of the VMware VC environment, **main.tf** is the main terraform file that uses generated ISO to install VM or VMs. Note in the case of terraform, there are a number of post-installation pipelines that customize a VM.

In both cases, customization for post-install, the first boot includes polling the latest Intel drivers, fixing kernel boot parameters, and optimizing VM/Host for the real-time workload.


## Requirements.

Requirements.

- Make sure you have a network segment in VC that provide DHCP services.
- Make sure the same segment has an internet connection.
- Make sure that DHCP allocates the DNS server.
- The port-group name must match whatever you see in VC.

## Step One: Build ISO.

```bash
# intall vault and store credentials.
./install_vault_linux.sh

# builds container or pull container from dockerhub and land to bash
./build_and_exec.sh

# builds iso 
./build_iso.sh
```

## Example

```bash
./build_and_exec.sh
Step 1/10 : FROM ubuntu:22.04
 ---> 2dc39ba059dc
Step 2/10 : RUN apt-get update
 ---> Using cache
 ---> a1e56dcfcac5
Step 3/10 : RUN apt-get install gnupg software-properties-common -y
 ---> Using cache
 ---> 290957a447d2
Step 4/10 : RUN apt-get install vim curl wget unzip genisoimage jq golang-go git -y
 ---> Using cache
 ---> bd890683c895
Step 5/10 : RUN wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
 ---> Using cache
 ---> 070f69167dd9
Step 6/10 : RUN gpg --no-default-keyring --keyring /usr/share/keyrings/hashicorp-archive-keyring.gpg --fingerprint
 ---> Using cache
 ---> 59fcc13ee06f
Step 7/10 : RUN echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list
 ---> Using cache
 ---> 20cc49442bcc
Step 8/10 : RUN apt-get update && apt-get install terraform
 ---> Using cache
 ---> b2a6e4e92a7b
Step 9/10 : RUN apt-get update && apt-get install -y locales && rm -rf /var/lib/apt/lists/* 	&& localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
 ---> Using cache
 ---> 06023bd2658f
Step 10/10 : ENV LANG en_US.utf8
 ---> Using cache
 ---> 9b627a4f7038
Successfully built 9b627a4f7038
Successfully tagged spyroot/photon_iso_builder:1.0
The push refers to repository [docker.io/spyroot/photon_iso_builder]
3344b9d15cf2: Layer already exists
75396949e5f2: Layer already exists
322bfa61a941: Layer already exists
3ae5fc7c640f: Layer already exists
99527508cbd5: Layer already exists
a5fe6c384a27: Layer already exists
049783616462: Layer already exists
9e9301f32f8a: Layer already exists
7f5cbd8cc787: Layer already exists
1.0: digest: sha256:8dd4c28314574e68c0ad3ca0dbd0aa8badf8d4381f1a2615cab76cbb0b7b5c35 size: 2211
1.0: Pulling from spyroot/photon_iso_builder
Digest: sha256:8dd4c28314574e68c0ad3ca0dbd0aa8badf8d4381f1a2615cab76cbb0b7b5c35
Status: Image is up to date for spyroot/photon_iso_builder:1.0
```

## Step two: Generate ISO

Now we can generate iso.  Run inside a container.

'''bash
./build_iso.sh
'''

### Example

```bash
root@08c5d91599b9:/home/vmware/photon_gen/photongen/build_iso# ./build_iso.sh
umount: /tmp/photon-iso: no mount point specified.
mount: /tmp/photon-iso: WARNING: source write-protected, mounted read-only.
/tmp/photon-ks-iso /home/vmware/photon_gen/photongen/build_iso
Warning: creating filesystem that does not conform to ISO-9660.
Size of boot image is 4 sectors -> No emulation
Size of boot image is 6144 sectors -> No emulation
  1.00% done, estimate finish Thu Sep  8 09:03:02 2022
  1.99% done, estimate finish Thu Sep  8 09:03:02 2022
  2.98% done, estimate finish Thu Sep  8 09:03:02 2022
  3.98% done, estimate finish Thu Sep  8 09:03:02 2022
  4.97% done, estimate finish Thu Sep  8 09:03:02 2022
  5.97% done, estimate finish Thu Sep  8 09:03:02 2022
 99.47% done, estimate finish Thu Sep  8 09:03:03 2022
Total translation table size: 2048
Total rockridge attributes bytes: 34230
Total directory bytes: 66730
Path table size(bytes): 162
Max brk space used 58000
502657 extents written (981 MB)
/home/vmware/photon_gen/photongen/build_iso
```

Notice script used ks.ref.cfg to generate new ks.cfg, and it pushed to ISO.cfg The script, by default, uses **$HOME/.ssh/ssh-rsa** and injects it to the target iso.

```json
{
  "hostname": "photon-machine",
  "password": {
    "crypted": false,
    "text": "VMware1!"
  },
  "disk": "/dev/sda",
  "partitions": [
    {
      "mountpoint": "/",
      "size": 0,
      "filesystem": "ext4",
      "lvm": {
        "vg_name": "vg1",
        "lv_name": "rootfs"
      }
    },
    {
      "mountpoint": "/root",
      "size": 8192,
      "filesystem": "ext4",
      "lvm": {
        "vg_name": "vg1",
        "lv_name": "root"
      }
    },
    {
      "mountpoint": "/boot",
      "size": 8192,
      "filesystem": "ext4"
    }
  ],
  "packagelist_file": "packages_rt.json",
  "additional_packages": [
    "vim",
    "gcc",
    "git",
    "wget",
    "numactl",
    "make",
    "curl"
  ],
  "postinstall": [
    "#!/bin/sh",
    "sed -i 's/PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config",
    "systemctl disable --now systemd-timesyncd",
    "sed -i 's/tx_timestamp_timeout.*/tx_timestamp_timeout    100/g' /etc/ptp4l.conf",
    "sed -i 's/eth0/eth4/g' /etc/sysconfig/ptp4l",
    "systemctl enable ptp4l.service phc2sys.service",
    "tdnf install dmidecode lshw -y",
    "tdnf update -y",
    "tdnf upgrade -y",
    "yum -y update >> /etc/postinstall",
    "yum -y install gcc meson git wget numactl make curl nasm >> /etc/postinstall",
    "yum -y install python3-pip unzip zip gzip build-essential zlib-devel >> /etc/postinstall",
    "yum -y install lshw findutils vim-extra elfutils-devel cmake cython3 python3-docutils >> /etc/postinstall",
    "yum -y install libbpf-devel libbpf libpcap-devel libpcap libmlx5 libhugetlbfs  >> /etc/postinstall",
    "wget -nc http://10.241.11.28/iso/photon/ztp/tinykube-0.0.1-1.x86_64.rpm -P /tmp/  >> /etc/postinstall",
    "tdnf install -y /tmp/tinykube-0.0.1-1.x86_64.rpm  >> /etc/postinstall"
  ],
  "linux_flavor": "linux-rt",
  "photon_docker_image": "photon:3.0",
  "photon_release_version": "4.0",
  "network": {
    "type": "dhcp"
  },
  "public_key": "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDKmJwH9DabcPvir/W3kE9VneKNH197fKFa01otfkioMh6+GFRRQm09py8NzPwdRz2a/Sp03JjJhrQ4SuPub5Dr2WJStQhEIYxF8b908+Groi6dVbaxqpFf5rWC3
pF3mT6v9eRjVHRboYb+o76bXkNo5iokvxfrpD1HL8I6AeZoxZke8oWV94IsHjsHLM78j5UHUm4ffmbNPG8joGpCEhNeT9+MSjqA+8kJz5v/ULUbuSS3f5ITYtf1fmimiFa1MCKoQ43/LuZE/VDuO1drLfov2e3YLwzNAWzLfm8CftSPG8m
z0OCFEVHs5jjdBNwpCXH8qEMAQ2yXgB3fXp6THo6slSGqQNMSqOBBwx8syTvnF7tUDXHQr9bDBvkFp8LXB+9dg+kuYuFcKaY8AhfrCvNsDHCa3fz8nQK7ovFYOHEWhH7cof1q4Uccrv/jB3uUR8ycoYUjbTfR+T63AWxM0WJa74WNHD4e8
lJyILrE59NRTWJARmDuqu3NPxfGSKYpRPU= root@epsilon01.cnfdemo.io"
}
```

A container creates volume that map to a workspace.  i.e., the same execution where Dockerfile is.  Exit from the container bash session back.  Notice build_iso.sh generated a new iso file.  Note don't run build_iso.sh directly.

## Creating VM.

A build system uses terraform to create a VM and boot VM from unattended generated ISO image.
Note that main.tf reference a vault hence you need create respected kv value.

```bash
./install_vault_linux.sh
```

script will instal vault. Note a defaut token in **token.txt** file. Also notice that default password set to DEFAULT,  
if you need adjust adjust respected kv

```bash
vault secrets enable -path=vcenter kv
vault kv put vcenter/vcenterpass password="DEFAULT"

```

## Step 3: Terrafor build instruction.

First create tfvars file. 

Make sure you have tfvars
```terraform
vsphere_server = "vc00.x.io"
vsphere_user = "administrator@vsphere.local"
vsphere_datacenter = "Datacenter"
vsphere_network = "tkg-dhcp-pod03-vlan1007-10.241.7.0"
vsphere_cluster = "core"
vsphere_datastore = "vsanDatastore"
iso_library = "iso"

photon_iso_image_name="ph4-rt-refresh_adj.iso"
photon_iso_catalog_name="ph4-rt-refresh_adj"

# vm boot attributes
vm_firmware                = "efi"
vm_efi_secure_boot_enabled = true
default_vm_disk_size=60
default_vm_mem_size=8129
default_vm_cpu_size=4
default_vm_num_cores_per_socket=4
default_vm_latency_sensitivity="normal"
default_vm_disk_thin = true

# guest vm param
root_pass = "vmware"
```

- Note by default VM set to thin
- Also note by default main.tf contains following.

```terraform
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

```

The motivation here is that we can post-install at run time and adjust CPU or memory if needed.

Initilize terraform and pull all plugins. 

```bash
terraform init -upgrade
```

Ensure you have updated the latest terraform tool and all plugins.

```bash
terraform apply
```

Notice build system upload the iso file to a content library and default datastore vsan.
if you need overwrite default datastore adjust

```
vsphere_datastore = "vsanDatastore"
```

By default, script will create dir inside a datastore ISO and put generated iso 
file in that datastore.

If everthing is right, we can deploy.  

```
terraform apply
```

Monitor progress in VC; notice that VMware tool will be installed by default, and VM will 
be rebooted automatically. The first boot script will adjust kernel and many other parts
and prepare VM to move to a next stage.


## Step 4:  TinyTKG

As part of the build process, when VM is created build system will wait for VM to obtain an IP address. Note that the network segment that indicates must have valid DHCP.

In the first phase, terraform will create a VM and boot from CDROM. Then, you can inspect VSAN Datastore and expand the ISO folder. During terraform, apply build system will upload iso in that spot.


Run 
```bash
terraform apply
```


## DPKD libs

* The build proccess builds and installs all shared libs in /usr/local/lib
* The docker image build poccess builds all example apps test-pmd etc.
* PktGen installed globally and linked to LTS DPKD build.
* The DPKD compiled with github.com/intel/intel-ipsec-mb.git support.
* The DPKD include MLX4/5 PMD and iverbs.  All kernel model in usual place.
* All Melanox libs included.  (Don't foget install all dependancies in OS itself)

# Build Instruction

build_and_exec.sh build container locally and land to local bash session.

```bash
sudo docker build -t photon_dpdk20.11:v1 .
sudo docker run --privileged --name photon_bash --rm -i -t photon_dpdk20.11:v1 bash
```
# Post Build re-compilation

All source inside /root/build

```
root [ /usr/local ]# cd /root/build/
root [ ~/build ]# ls
dpdk-20.11.3.tar.xz  dpdk-stable-20.11.3  pktgen-dpdk  rt-tests
```

# Running Cyclictest

```
sudo docker run --privileged --name photon_bash --rm -i -t photon_dpdk20.11:v1 cyclictest
```

# Running PktGen

```
sudo docker run --privileged --name photon_bash --rm -i -t photon_dpdk20.11:v1 pktgen
```

# Running testpmd

Regular setup requires hugepage 

```
sudo docker run --privileged --name photon_bash --rm -i -t photon_dpdk20.11:v1 dpdk-testpmd
```

Test run

```
sudo docker run --privileged --name photon_bash --rm -i -t photon_dpdk20.11:v1 dpdk-testpmd --no-huge
```


# Tenorflow

```
sudo docker run --privileged --name photon_bash --rm -i -t photon_dpdk20.11:v1 python3
Python 3.9.1 (default, Aug 19 2021, 02:58:42)
[GCC 10.2.0] on linux
Type "help", "copyright", "credits" or "license" for more information.
>>> import tensorflow as tf
>>> model = tf.keras.models.Sequential([
...   tf.keras.layers.Flatten(input_shape=(28, 28)),
...   tf.keras.layers.Dense(128, activation='relu'),
...   tf.keras.layers.Dropout(0.2),
...   tf.keras.layers.Dense(10)
... ])
>>>
```

* Make sure GPU attached to worker node or baremetal where you run a container.

In order to check GPU,   open python3 repl import tf and check list_physical_devices 

```
sudo docker run --privileged --name photon_bash --rm -i -t photon_dpdk20.11:v1 python3
print("Num GPUs Available: ", len(tf.config.experimental.list_physical_devices('GPU')))
Num GPUs Available:  0
```

## Libs
```
null_resource.dpdk (remote-exec): './librte_baseband_acc100.so' -> 'dpdk/pmds-22.0/librte_baseband_acc100.so'
null_resource.dpdk (remote-exec): './librte_baseband_acc100.so.22' -> 'dpdk/pmds-22.0/librte_baseband_acc100.so.22'
null_resource.dpdk (remote-exec): './librte_baseband_acc100.so.22.0' -> 'dpdk/pmds-22.0/librte_baseband_acc100.so.22.0'
null_resource.dpdk (remote-exec): './librte_baseband_fpga_5gnr_fec.so' -> 'dpdk/pmds-22.0/librte_baseband_fpga_5gnr_fec.so'
null_resource.dpdk (remote-exec): './librte_baseband_fpga_5gnr_fec.so.22' -> 'dpdk/pmds-22.0/librte_baseband_fpga_5gnr_fec.so.22'
null_resource.dpdk (remote-exec): './librte_baseband_fpga_5gnr_fec.so.22.0' -> 'dpdk/pmds-22.0/librte_baseband_fpga_5gnr_fec.so.22.0'
null_resource.dpdk (remote-exec): './librte_baseband_fpga_lte_fec.so' -> 'dpdk/pmds-22.0/librte_baseband_fpga_lte_fec.so'
null_resource.dpdk (remote-exec): './librte_baseband_fpga_lte_fec.so.22' -> 'dpdk/pmds-22.0/librte_baseband_fpga_lte_fec.so.22'
null_resource.dpdk (remote-exec): './librte_baseband_fpga_lte_fec.so.22.0' -> 'dpdk/pmds-22.0/librte_baseband_fpga_lte_fec.so.22.0'
null_resource.dpdk (remote-exec): './librte_baseband_la12xx.so' -> 'dpdk/pmds-22.0/librte_baseband_la12xx.so'
null_resource.dpdk (remote-exec): './librte_baseband_la12xx.so.22' -> 'dpdk/pmds-22.0/librte_baseband_la12xx.so.22'
null_resource.dpdk (remote-exec): './librte_baseband_la12xx.so.22.0' -> 'dpdk/pmds-22.0/librte_baseband_la12xx.so.22.0'
null_resource.dpdk (remote-exec): './librte_baseband_null.so' -> 'dpdk/pmds-22.0/librte_baseband_null.so'
null_resource.dpdk (remote-exec): './librte_baseband_null.so.22' -> 'dpdk/pmds-22.0/librte_baseband_null.so.22'
null_resource.dpdk (remote-exec): './librte_baseband_null.so.22.0' -> 'dpdk/pmds-22.0/librte_baseband_null.so.22.0'
null_resource.dpdk (remote-exec): './librte_baseband_turbo_sw.so' -> 'dpdk/pmds-22.0/librte_baseband_turbo_sw.so'
null_resource.dpdk (remote-exec): './librte_baseband_turbo_sw.so.22' -> 'dpdk/pmds-22.0/librte_baseband_turbo_sw.so.22'
null_resource.dpdk (remote-exec): './librte_baseband_turbo_sw.so.22.0' -> 'dpdk/pmds-22.0/librte_baseband_turbo_sw.so.22.0'
null_resource.dpdk (remote-exec): './librte_bus_auxiliary.so' -> 'dpdk/pmds-22.0/librte_bus_auxiliary.so'
null_resource.dpdk (remote-exec): './librte_bus_auxiliary.so.22' -> 'dpdk/pmds-22.0/librte_bus_auxiliary.so.22'
null_resource.dpdk (remote-exec): './librte_bus_auxiliary.so.22.0' -> 'dpdk/pmds-22.0/librte_bus_auxiliary.so.22.0'
null_resource.dpdk (remote-exec): './librte_bus_dpaa.so' -> 'dpdk/pmds-22.0/librte_bus_dpaa.so'
null_resource.dpdk (remote-exec): './librte_bus_dpaa.so.22' -> 'dpdk/pmds-22.0/librte_bus_dpaa.so.22'
null_resource.dpdk (remote-exec): './librte_bus_dpaa.so.22.0' -> 'dpdk/pmds-22.0/librte_bus_dpaa.so.22.0'
null_resource.dpdk (remote-exec): './librte_bus_fslmc.so' -> 'dpdk/pmds-22.0/librte_bus_fslmc.so'
null_resource.dpdk (remote-exec): './librte_bus_fslmc.so.22' -> 'dpdk/pmds-22.0/librte_bus_fslmc.so.22'
null_resource.dpdk (remote-exec): './librte_bus_fslmc.so.22.0' -> 'dpdk/pmds-22.0/librte_bus_fslmc.so.22.0'
null_resource.dpdk (remote-exec): './librte_bus_ifpga.so' -> 'dpdk/pmds-22.0/librte_bus_ifpga.so'
null_resource.dpdk (remote-exec): './librte_bus_ifpga.so.22' -> 'dpdk/pmds-22.0/librte_bus_ifpga.so.22'
null_resource.dpdk (remote-exec): './librte_bus_ifpga.so.22.0' -> 'dpdk/pmds-22.0/librte_bus_ifpga.so.22.0'
null_resource.dpdk (remote-exec): './librte_bus_pci.so' -> 'dpdk/pmds-22.0/librte_bus_pci.so'
null_resource.dpdk (remote-exec): './librte_bus_pci.so.22' -> 'dpdk/pmds-22.0/librte_bus_pci.so.22'
null_resource.dpdk (remote-exec): './librte_bus_pci.so.22.0' -> 'dpdk/pmds-22.0/librte_bus_pci.so.22.0'
null_resource.dpdk (remote-exec): './librte_bus_vdev.so' -> 'dpdk/pmds-22.0/librte_bus_vdev.so'
null_resource.dpdk (remote-exec): './librte_bus_vdev.so.22' -> 'dpdk/pmds-22.0/librte_bus_vdev.so.22'
null_resource.dpdk (remote-exec): './librte_bus_vdev.so.22.0' -> 'dpdk/pmds-22.0/librte_bus_vdev.so.22.0'
null_resource.dpdk (remote-exec): './librte_bus_vmbus.so' -> 'dpdk/pmds-22.0/librte_bus_vmbus.so'
null_resource.dpdk (remote-exec): './librte_bus_vmbus.so.22' -> 'dpdk/pmds-22.0/librte_bus_vmbus.so.22'
null_resource.dpdk (remote-exec): './librte_bus_vmbus.so.22.0' -> 'dpdk/pmds-22.0/librte_bus_vmbus.so.22.0'
null_resource.dpdk (remote-exec): './librte_common_cnxk.so' -> 'dpdk/pmds-22.0/librte_common_cnxk.so'
null_resource.dpdk (remote-exec): './librte_common_cnxk.so.22' -> 'dpdk/pmds-22.0/librte_common_cnxk.so.22'
null_resource.dpdk (remote-exec): './librte_common_cnxk.so.22.0' -> 'dpdk/pmds-22.0/librte_common_cnxk.so.22.0'
null_resource.dpdk (remote-exec): './librte_common_cpt.so' -> 'dpdk/pmds-22.0/librte_common_cpt.so'
null_resource.dpdk (remote-exec): './librte_common_cpt.so.22' -> 'dpdk/pmds-22.0/librte_common_cpt.so.22'
null_resource.dpdk (remote-exec): './librte_common_cpt.so.22.0' -> 'dpdk/pmds-22.0/librte_common_cpt.so.22.0'
null_resource.dpdk (remote-exec): './librte_common_dpaax.so' -> 'dpdk/pmds-22.0/librte_common_dpaax.so'
null_resource.dpdk (remote-exec): './librte_common_dpaax.so.22' -> 'dpdk/pmds-22.0/librte_common_dpaax.so.22'
null_resource.dpdk (remote-exec): './librte_common_dpaax.so.22.0' -> 'dpdk/pmds-22.0/librte_common_dpaax.so.22.0'
null_resource.dpdk (remote-exec): './librte_common_iavf.so' -> 'dpdk/pmds-22.0/librte_common_iavf.so'
null_resource.dpdk (remote-exec): './librte_common_iavf.so.22' -> 'dpdk/pmds-22.0/librte_common_iavf.so.22'
null_resource.dpdk (remote-exec): './librte_common_iavf.so.22.0' -> 'dpdk/pmds-22.0/librte_common_iavf.so.22.0'
null_resource.dpdk (remote-exec): './librte_common_mlx5.so' -> 'dpdk/pmds-22.0/librte_common_mlx5.so'
null_resource.dpdk (remote-exec): './librte_common_mlx5.so.22' -> 'dpdk/pmds-22.0/librte_common_mlx5.so.22'
null_resource.dpdk (remote-exec): './librte_common_mlx5.so.22.0' -> 'dpdk/pmds-22.0/librte_common_mlx5.so.22.0'
null_resource.dpdk (remote-exec): './librte_common_octeontx2.so' -> 'dpdk/pmds-22.0/librte_common_octeontx2.so'
null_resource.dpdk (remote-exec): './librte_common_octeontx2.so.22' -> 'dpdk/pmds-22.0/librte_common_octeontx2.so.22'
null_resource.dpdk (remote-exec): './librte_common_octeontx2.so.22.0' -> 'dpdk/pmds-22.0/librte_common_octeontx2.so.22.0'
null_resource.dpdk (remote-exec): './librte_common_octeontx.so' -> 'dpdk/pmds-22.0/librte_common_octeontx.so'
null_resource.dpdk (remote-exec): './librte_common_octeontx.so.22' -> 'dpdk/pmds-22.0/librte_common_octeontx.so.22'
null_resource.dpdk (remote-exec): './librte_common_octeontx.so.22.0' -> 'dpdk/pmds-22.0/librte_common_octeontx.so.22.0'
null_resource.dpdk (remote-exec): './librte_common_qat.so' -> 'dpdk/pmds-22.0/librte_common_qat.so'
null_resource.dpdk (remote-exec): './librte_common_qat.so.22' -> 'dpdk/pmds-22.0/librte_common_qat.so.22'
null_resource.dpdk (remote-exec): './librte_common_qat.so.22.0' -> 'dpdk/pmds-22.0/librte_common_qat.so.22.0'
null_resource.dpdk (remote-exec): './librte_common_sfc_efx.so' -> 'dpdk/pmds-22.0/librte_common_sfc_efx.so'
null_resource.dpdk (remote-exec): './librte_common_sfc_efx.so.22' -> 'dpdk/pmds-22.0/librte_common_sfc_efx.so.22'
null_resource.dpdk (remote-exec): './librte_common_sfc_efx.so.22.0' -> 'dpdk/pmds-22.0/librte_common_sfc_efx.so.22.0'
null_resource.dpdk (remote-exec): './librte_compress_isal.so' -> 'dpdk/pmds-22.0/librte_compress_isal.so'
null_resource.dpdk (remote-exec): './librte_compress_isal.so.22' -> 'dpdk/pmds-22.0/librte_compress_isal.so.22'
null_resource.dpdk (remote-exec): './librte_compress_isal.so.22.0' -> 'dpdk/pmds-22.0/librte_compress_isal.so.22.0'
null_resource.dpdk (remote-exec): './librte_compress_mlx5.so' -> 'dpdk/pmds-22.0/librte_compress_mlx5.so'
null_resource.dpdk (remote-exec): './librte_compress_mlx5.so.22' -> 'dpdk/pmds-22.0/librte_compress_mlx5.so.22'
null_resource.dpdk (remote-exec): './librte_compress_mlx5.so.22.0' -> 'dpdk/pmds-22.0/librte_compress_mlx5.so.22.0'
null_resource.dpdk (remote-exec): './librte_compress_octeontx.so' -> 'dpdk/pmds-22.0/librte_compress_octeontx.so'
null_resource.dpdk (remote-exec): './librte_compress_octeontx.so.22' -> 'dpdk/pmds-22.0/librte_compress_octeontx.so.22'
null_resource.dpdk (remote-exec): './librte_compress_octeontx.so.22.0' -> 'dpdk/pmds-22.0/librte_compress_octeontx.so.22.0'
null_resource.dpdk (remote-exec): './librte_compress_zlib.so' -> 'dpdk/pmds-22.0/librte_compress_zlib.so'
null_resource.dpdk (remote-exec): './librte_compress_zlib.so.22' -> 'dpdk/pmds-22.0/librte_compress_zlib.so.22'
null_resource.dpdk (remote-exec): './librte_compress_zlib.so.22.0' -> 'dpdk/pmds-22.0/librte_compress_zlib.so.22.0'
null_resource.dpdk (remote-exec): './librte_crypto_bcmfs.so' -> 'dpdk/pmds-22.0/librte_crypto_bcmfs.so'
null_resource.dpdk (remote-exec): './librte_crypto_bcmfs.so.22' -> 'dpdk/pmds-22.0/librte_crypto_bcmfs.so.22'
null_resource.dpdk (remote-exec): './librte_crypto_bcmfs.so.22.0' -> 'dpdk/pmds-22.0/librte_crypto_bcmfs.so.22.0'
null_resource.dpdk (remote-exec): './librte_crypto_caam_jr.so' -> 'dpdk/pmds-22.0/librte_crypto_caam_jr.so'
null_resource.dpdk (remote-exec): './librte_crypto_caam_jr.so.22' -> 'dpdk/pmds-22.0/librte_crypto_caam_jr.so.22'
null_resource.dpdk (remote-exec): './librte_crypto_caam_jr.so.22.0' -> 'dpdk/pmds-22.0/librte_crypto_caam_jr.so.22.0'
null_resource.dpdk (remote-exec): './librte_crypto_ccp.so' -> 'dpdk/pmds-22.0/librte_crypto_ccp.so'
null_resource.dpdk (remote-exec): './librte_crypto_ccp.so.22' -> 'dpdk/pmds-22.0/librte_crypto_ccp.so.22'
null_resource.dpdk (remote-exec): './librte_crypto_ccp.so.22.0' -> 'dpdk/pmds-22.0/librte_crypto_ccp.so.22.0'
null_resource.dpdk (remote-exec): './librte_crypto_cnxk.so' -> 'dpdk/pmds-22.0/librte_crypto_cnxk.so'
null_resource.dpdk (remote-exec): './librte_crypto_cnxk.so.22' -> 'dpdk/pmds-22.0/librte_crypto_cnxk.so.22'
null_resource.dpdk (remote-exec): './librte_crypto_cnxk.so.22.0' -> 'dpdk/pmds-22.0/librte_crypto_cnxk.so.22.0'
null_resource.dpdk (remote-exec): './librte_crypto_dpaa2_sec.so' -> 'dpdk/pmds-22.0/librte_crypto_dpaa2_sec.so'
null_resource.dpdk (remote-exec): './librte_crypto_dpaa2_sec.so.22' -> 'dpdk/pmds-22.0/librte_crypto_dpaa2_sec.so.22'
null_resource.dpdk (remote-exec): './librte_crypto_dpaa2_sec.so.22.0' -> 'dpdk/pmds-22.0/librte_crypto_dpaa2_sec.so.22.0'
null_resource.dpdk (remote-exec): './librte_crypto_dpaa_sec.so' -> 'dpdk/pmds-22.0/librte_crypto_dpaa_sec.so'
null_resource.dpdk (remote-exec): './librte_crypto_dpaa_sec.so.22' -> 'dpdk/pmds-22.0/librte_crypto_dpaa_sec.so.22'
null_resource.dpdk (remote-exec): './librte_crypto_dpaa_sec.so.22.0' -> 'dpdk/pmds-22.0/librte_crypto_dpaa_sec.so.22.0'
null_resource.dpdk (remote-exec): './librte_crypto_ipsec_mb.so' -> 'dpdk/pmds-22.0/librte_crypto_ipsec_mb.so'
null_resource.dpdk (remote-exec): './librte_crypto_ipsec_mb.so.22' -> 'dpdk/pmds-22.0/librte_crypto_ipsec_mb.so.22'
null_resource.dpdk (remote-exec): './librte_crypto_ipsec_mb.so.22.0' -> 'dpdk/pmds-22.0/librte_crypto_ipsec_mb.so.22.0'
null_resource.dpdk (remote-exec): './librte_crypto_mlx5.so' -> 'dpdk/pmds-22.0/librte_crypto_mlx5.so'
null_resource.dpdk (remote-exec): './librte_crypto_mlx5.so.22' -> 'dpdk/pmds-22.0/librte_crypto_mlx5.so.22'
null_resource.dpdk (remote-exec): './librte_crypto_mlx5.so.22.0' -> 'dpdk/pmds-22.0/librte_crypto_mlx5.so.22.0'
null_resource.dpdk (remote-exec): './librte_crypto_nitrox.so' -> 'dpdk/pmds-22.0/librte_crypto_nitrox.so'
null_resource.dpdk (remote-exec): './librte_crypto_nitrox.so.22' -> 'dpdk/pmds-22.0/librte_crypto_nitrox.so.22'
null_resource.dpdk (remote-exec): './librte_crypto_nitrox.so.22.0' -> 'dpdk/pmds-22.0/librte_crypto_nitrox.so.22.0'
null_resource.dpdk (remote-exec): './librte_crypto_null.so' -> 'dpdk/pmds-22.0/librte_crypto_null.so'
null_resource.dpdk (remote-exec): './librte_crypto_null.so.22' -> 'dpdk/pmds-22.0/librte_crypto_null.so.22'
null_resource.dpdk (remote-exec): './librte_crypto_null.so.22.0' -> 'dpdk/pmds-22.0/librte_crypto_null.so.22.0'
null_resource.dpdk (remote-exec): './librte_crypto_octeontx2.so' -> 'dpdk/pmds-22.0/librte_crypto_octeontx2.so'
null_resource.dpdk (remote-exec): './librte_crypto_octeontx2.so.22' -> 'dpdk/pmds-22.0/librte_crypto_octeontx2.so.22'
null_resource.dpdk (remote-exec): './librte_crypto_octeontx2.so.22.0' -> 'dpdk/pmds-22.0/librte_crypto_octeontx2.so.22.0'
null_resource.dpdk (remote-exec): './librte_crypto_octeontx.so' -> 'dpdk/pmds-22.0/librte_crypto_octeontx.so'
null_resource.dpdk (remote-exec): './librte_crypto_octeontx.so.22' -> 'dpdk/pmds-22.0/librte_crypto_octeontx.so.22'
null_resource.dpdk (remote-exec): './librte_crypto_octeontx.so.22.0' -> 'dpdk/pmds-22.0/librte_crypto_octeontx.so.22.0'
null_resource.dpdk (remote-exec): './librte_crypto_openssl.so' -> 'dpdk/pmds-22.0/librte_crypto_openssl.so'
null_resource.dpdk (remote-exec): './librte_crypto_openssl.so.22' -> 'dpdk/pmds-22.0/librte_crypto_openssl.so.22'
null_resource.dpdk (remote-exec): './librte_crypto_openssl.so.22.0' -> 'dpdk/pmds-22.0/librte_crypto_openssl.so.22.0'
null_resource.dpdk (remote-exec): './librte_crypto_scheduler.so' -> 'dpdk/pmds-22.0/librte_crypto_scheduler.so'
null_resource.dpdk (remote-exec): './librte_crypto_scheduler.so.22' -> 'dpdk/pmds-22.0/librte_crypto_scheduler.so.22'
null_resource.dpdk (remote-exec): './librte_crypto_scheduler.so.22.0' -> 'dpdk/pmds-22.0/librte_crypto_scheduler.so.22.0'
null_resource.dpdk (remote-exec): './librte_crypto_virtio.so' -> 'dpdk/pmds-22.0/librte_crypto_virtio.so'
null_resource.dpdk (remote-exec): './librte_crypto_virtio.so.22' -> 'dpdk/pmds-22.0/librte_crypto_virtio.so.22'
null_resource.dpdk (remote-exec): './librte_crypto_virtio.so.22.0' -> 'dpdk/pmds-22.0/librte_crypto_virtio.so.22.0'
null_resource.dpdk (remote-exec): './librte_dma_cnxk.so' -> 'dpdk/pmds-22.0/librte_dma_cnxk.so'
null_resource.dpdk (remote-exec): './librte_dma_cnxk.so.22' -> 'dpdk/pmds-22.0/librte_dma_cnxk.so.22'
null_resource.dpdk (remote-exec): './librte_dma_cnxk.so.22.0' -> 'dpdk/pmds-22.0/librte_dma_cnxk.so.22.0'
null_resource.dpdk (remote-exec): './librte_dma_dpaa.so' -> 'dpdk/pmds-22.0/librte_dma_dpaa.so'
null_resource.dpdk (remote-exec): './librte_dma_dpaa.so.22' -> 'dpdk/pmds-22.0/librte_dma_dpaa.so.22'
null_resource.dpdk (remote-exec): './librte_dma_dpaa.so.22.0' -> 'dpdk/pmds-22.0/librte_dma_dpaa.so.22.0'
null_resource.dpdk (remote-exec): './librte_dma_hisilicon.so' -> 'dpdk/pmds-22.0/librte_dma_hisilicon.so'
null_resource.dpdk (remote-exec): './librte_dma_hisilicon.so.22' -> 'dpdk/pmds-22.0/librte_dma_hisilicon.so.22'
null_resource.dpdk (remote-exec): './librte_dma_hisilicon.so.22.0' -> 'dpdk/pmds-22.0/librte_dma_hisilicon.so.22.0'
null_resource.dpdk (remote-exec): './librte_dma_idxd.so' -> 'dpdk/pmds-22.0/librte_dma_idxd.so'
null_resource.dpdk (remote-exec): './librte_dma_idxd.so.22' -> 'dpdk/pmds-22.0/librte_dma_idxd.so.22'
null_resource.dpdk (remote-exec): './librte_dma_idxd.so.22.0' -> 'dpdk/pmds-22.0/librte_dma_idxd.so.22.0'
null_resource.dpdk (remote-exec): './librte_dma_ioat.so' -> 'dpdk/pmds-22.0/librte_dma_ioat.so'
null_resource.dpdk (remote-exec): './librte_dma_ioat.so.22' -> 'dpdk/pmds-22.0/librte_dma_ioat.so.22'
null_resource.dpdk (remote-exec): './librte_dma_ioat.so.22.0' -> 'dpdk/pmds-22.0/librte_dma_ioat.so.22.0'
null_resource.dpdk (remote-exec): './librte_dma_skeleton.so' -> 'dpdk/pmds-22.0/librte_dma_skeleton.so'
null_resource.dpdk (remote-exec): './librte_dma_skeleton.so.22' -> 'dpdk/pmds-22.0/librte_dma_skeleton.so.22'
null_resource.dpdk (remote-exec): './librte_dma_skeleton.so.22.0' -> 'dpdk/pmds-22.0/librte_dma_skeleton.so.22.0'
null_resource.dpdk (remote-exec): './librte_event_cnxk.so' -> 'dpdk/pmds-22.0/librte_event_cnxk.so'
null_resource.dpdk (remote-exec): './librte_event_cnxk.so.22' -> 'dpdk/pmds-22.0/librte_event_cnxk.so.22'
null_resource.dpdk (remote-exec): './librte_event_cnxk.so.22.0' -> 'dpdk/pmds-22.0/librte_event_cnxk.so.22.0'
null_resource.dpdk (remote-exec): './librte_event_dlb2.so' -> 'dpdk/pmds-22.0/librte_event_dlb2.so'
null_resource.dpdk (remote-exec): './librte_event_dlb2.so.22' -> 'dpdk/pmds-22.0/librte_event_dlb2.so.22'
null_resource.dpdk (remote-exec): './librte_event_dlb2.so.22.0' -> 'dpdk/pmds-22.0/librte_event_dlb2.so.22.0'
null_resource.dpdk (remote-exec): './librte_event_dpaa2.so' -> 'dpdk/pmds-22.0/librte_event_dpaa2.so'
null_resource.dpdk (remote-exec): './librte_event_dpaa2.so.22' -> 'dpdk/pmds-22.0/librte_event_dpaa2.so.22'
null_resource.dpdk (remote-exec): './librte_event_dpaa2.so.22.0' -> 'dpdk/pmds-22.0/librte_event_dpaa2.so.22.0'
null_resource.dpdk (remote-exec): './librte_event_dpaa.so' -> 'dpdk/pmds-22.0/librte_event_dpaa.so'
null_resource.dpdk (remote-exec): './librte_event_dpaa.so.22' -> 'dpdk/pmds-22.0/librte_event_dpaa.so.22'
null_resource.dpdk (remote-exec): './librte_event_dpaa.so.22.0' -> 'dpdk/pmds-22.0/librte_event_dpaa.so.22.0'
null_resource.dpdk (remote-exec): './librte_event_dsw.so' -> 'dpdk/pmds-22.0/librte_event_dsw.so'
null_resource.dpdk (remote-exec): './librte_event_dsw.so.22' -> 'dpdk/pmds-22.0/librte_event_dsw.so.22'
null_resource.dpdk (remote-exec): './librte_event_dsw.so.22.0' -> 'dpdk/pmds-22.0/librte_event_dsw.so.22.0'
null_resource.dpdk (remote-exec): './librte_event_octeontx2.so' -> 'dpdk/pmds-22.0/librte_event_octeontx2.so'
null_resource.dpdk (remote-exec): './librte_event_octeontx2.so.22' -> 'dpdk/pmds-22.0/librte_event_octeontx2.so.22'
null_resource.dpdk (remote-exec): './librte_event_octeontx2.so.22.0' -> 'dpdk/pmds-22.0/librte_event_octeontx2.so.22.0'
null_resource.dpdk (remote-exec): './librte_event_octeontx.so' -> 'dpdk/pmds-22.0/librte_event_octeontx.so'
null_resource.dpdk (remote-exec): './librte_event_octeontx.so.22' -> 'dpdk/pmds-22.0/librte_event_octeontx.so.22'
null_resource.dpdk (remote-exec): './librte_event_octeontx.so.22.0' -> 'dpdk/pmds-22.0/librte_event_octeontx.so.22.0'
null_resource.dpdk (remote-exec): './librte_event_opdl.so' -> 'dpdk/pmds-22.0/librte_event_opdl.so'
null_resource.dpdk (remote-exec): './librte_event_opdl.so.22' -> 'dpdk/pmds-22.0/librte_event_opdl.so.22'
null_resource.dpdk (remote-exec): './librte_event_opdl.so.22.0' -> 'dpdk/pmds-22.0/librte_event_opdl.so.22.0'
null_resource.dpdk (remote-exec): './librte_event_skeleton.so' -> 'dpdk/pmds-22.0/librte_event_skeleton.so'
null_resource.dpdk (remote-exec): './librte_event_skeleton.so.22' -> 'dpdk/pmds-22.0/librte_event_skeleton.so.22'
null_resource.dpdk (remote-exec): './librte_event_skeleton.so.22.0' -> 'dpdk/pmds-22.0/librte_event_skeleton.so.22.0'
null_resource.dpdk (remote-exec): './librte_event_sw.so' -> 'dpdk/pmds-22.0/librte_event_sw.so'
null_resource.dpdk (remote-exec): './librte_event_sw.so.22' -> 'dpdk/pmds-22.0/librte_event_sw.so.22'
null_resource.dpdk (remote-exec): './librte_event_sw.so.22.0' -> 'dpdk/pmds-22.0/librte_event_sw.so.22.0'
null_resource.dpdk (remote-exec): './librte_mempool_bucket.so' -> 'dpdk/pmds-22.0/librte_mempool_bucket.so'
null_resource.dpdk (remote-exec): './librte_mempool_bucket.so.22' -> 'dpdk/pmds-22.0/librte_mempool_bucket.so.22'
null_resource.dpdk (remote-exec): './librte_mempool_bucket.so.22.0' -> 'dpdk/pmds-22.0/librte_mempool_bucket.so.22.0'
null_resource.dpdk (remote-exec): './librte_mempool_cnxk.so' -> 'dpdk/pmds-22.0/librte_mempool_cnxk.so'
null_resource.dpdk (remote-exec): './librte_mempool_cnxk.so.22' -> 'dpdk/pmds-22.0/librte_mempool_cnxk.so.22'
null_resource.dpdk (remote-exec): './librte_mempool_cnxk.so.22.0' -> 'dpdk/pmds-22.0/librte_mempool_cnxk.so.22.0'
null_resource.dpdk (remote-exec): './librte_mempool_dpaa2.so' -> 'dpdk/pmds-22.0/librte_mempool_dpaa2.so'
null_resource.dpdk (remote-exec): './librte_mempool_dpaa2.so.22' -> 'dpdk/pmds-22.0/librte_mempool_dpaa2.so.22'
null_resource.dpdk (remote-exec): './librte_mempool_dpaa2.so.22.0' -> 'dpdk/pmds-22.0/librte_mempool_dpaa2.so.22.0'
null_resource.dpdk (remote-exec): './librte_mempool_dpaa.so' -> 'dpdk/pmds-22.0/librte_mempool_dpaa.so'
null_resource.dpdk (remote-exec): './librte_mempool_dpaa.so.22' -> 'dpdk/pmds-22.0/librte_mempool_dpaa.so.22'
null_resource.dpdk (remote-exec): './librte_mempool_dpaa.so.22.0' -> 'dpdk/pmds-22.0/librte_mempool_dpaa.so.22.0'
null_resource.dpdk (remote-exec): './librte_mempool_octeontx2.so' -> 'dpdk/pmds-22.0/librte_mempool_octeontx2.so'
null_resource.dpdk (remote-exec): './librte_mempool_octeontx2.so.22' -> 'dpdk/pmds-22.0/librte_mempool_octeontx2.so.22'
null_resource.dpdk (remote-exec): './librte_mempool_octeontx2.so.22.0' -> 'dpdk/pmds-22.0/librte_mempool_octeontx2.so.22.0'
null_resource.dpdk (remote-exec): './librte_mempool_octeontx.so' -> 'dpdk/pmds-22.0/librte_mempool_octeontx.so'
null_resource.dpdk (remote-exec): './librte_mempool_octeontx.so.22' -> 'dpdk/pmds-22.0/librte_mempool_octeontx.so.22'
null_resource.dpdk (remote-exec): './librte_mempool_octeontx.so.22.0' -> 'dpdk/pmds-22.0/librte_mempool_octeontx.so.22.0'
null_resource.dpdk (remote-exec): './librte_mempool_ring.so' -> 'dpdk/pmds-22.0/librte_mempool_ring.so'
null_resource.dpdk (remote-exec): './librte_mempool_ring.so.22' -> 'dpdk/pmds-22.0/librte_mempool_ring.so.22'
null_resource.dpdk (remote-exec): './librte_mempool_ring.so.22.0' -> 'dpdk/pmds-22.0/librte_mempool_ring.so.22.0'
null_resource.dpdk (remote-exec): './librte_mempool_stack.so' -> 'dpdk/pmds-22.0/librte_mempool_stack.so'
null_resource.dpdk (remote-exec): './librte_mempool_stack.so.22' -> 'dpdk/pmds-22.0/librte_mempool_stack.so.22'
null_resource.dpdk (remote-exec): './librte_mempool_stack.so.22.0' -> 'dpdk/pmds-22.0/librte_mempool_stack.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_af_packet.so' -> 'dpdk/pmds-22.0/librte_net_af_packet.so'
null_resource.dpdk (remote-exec): './librte_net_af_packet.so.22' -> 'dpdk/pmds-22.0/librte_net_af_packet.so.22'
null_resource.dpdk (remote-exec): './librte_net_af_packet.so.22.0' -> 'dpdk/pmds-22.0/librte_net_af_packet.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_af_xdp.so' -> 'dpdk/pmds-22.0/librte_net_af_xdp.so'
null_resource.dpdk (remote-exec): './librte_net_af_xdp.so.22' -> 'dpdk/pmds-22.0/librte_net_af_xdp.so.22'
null_resource.dpdk (remote-exec): './librte_net_af_xdp.so.22.0' -> 'dpdk/pmds-22.0/librte_net_af_xdp.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_ark.so' -> 'dpdk/pmds-22.0/librte_net_ark.so'
null_resource.dpdk (remote-exec): './librte_net_ark.so.22' -> 'dpdk/pmds-22.0/librte_net_ark.so.22'
null_resource.dpdk (remote-exec): './librte_net_ark.so.22.0' -> 'dpdk/pmds-22.0/librte_net_ark.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_atlantic.so' -> 'dpdk/pmds-22.0/librte_net_atlantic.so'
null_resource.dpdk (remote-exec): './librte_net_atlantic.so.22' -> 'dpdk/pmds-22.0/librte_net_atlantic.so.22'
null_resource.dpdk (remote-exec): './librte_net_atlantic.so.22.0' -> 'dpdk/pmds-22.0/librte_net_atlantic.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_avp.so' -> 'dpdk/pmds-22.0/librte_net_avp.so'
null_resource.dpdk (remote-exec): './librte_net_avp.so.22' -> 'dpdk/pmds-22.0/librte_net_avp.so.22'
null_resource.dpdk (remote-exec): './librte_net_avp.so.22.0' -> 'dpdk/pmds-22.0/librte_net_avp.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_axgbe.so' -> 'dpdk/pmds-22.0/librte_net_axgbe.so'
null_resource.dpdk (remote-exec): './librte_net_axgbe.so.22' -> 'dpdk/pmds-22.0/librte_net_axgbe.so.22'
null_resource.dpdk (remote-exec): './librte_net_axgbe.so.22.0' -> 'dpdk/pmds-22.0/librte_net_axgbe.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_bnx2x.so' -> 'dpdk/pmds-22.0/librte_net_bnx2x.so'
null_resource.dpdk (remote-exec): './librte_net_bnx2x.so.22' -> 'dpdk/pmds-22.0/librte_net_bnx2x.so.22'
null_resource.dpdk (remote-exec): './librte_net_bnx2x.so.22.0' -> 'dpdk/pmds-22.0/librte_net_bnx2x.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_bnxt.so' -> 'dpdk/pmds-22.0/librte_net_bnxt.so'
null_resource.dpdk (remote-exec): './librte_net_bnxt.so.22' -> 'dpdk/pmds-22.0/librte_net_bnxt.so.22'
null_resource.dpdk (remote-exec): './librte_net_bnxt.so.22.0' -> 'dpdk/pmds-22.0/librte_net_bnxt.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_bond.so' -> 'dpdk/pmds-22.0/librte_net_bond.so'
null_resource.dpdk (remote-exec): './librte_net_bond.so.22' -> 'dpdk/pmds-22.0/librte_net_bond.so.22'
null_resource.dpdk (remote-exec): './librte_net_bond.so.22.0' -> 'dpdk/pmds-22.0/librte_net_bond.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_cnxk.so' -> 'dpdk/pmds-22.0/librte_net_cnxk.so'
null_resource.dpdk (remote-exec): './librte_net_cnxk.so.22' -> 'dpdk/pmds-22.0/librte_net_cnxk.so.22'
null_resource.dpdk (remote-exec): './librte_net_cnxk.so.22.0' -> 'dpdk/pmds-22.0/librte_net_cnxk.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_cxgbe.so' -> 'dpdk/pmds-22.0/librte_net_cxgbe.so'
null_resource.dpdk (remote-exec): './librte_net_cxgbe.so.22' -> 'dpdk/pmds-22.0/librte_net_cxgbe.so.22'
null_resource.dpdk (remote-exec): './librte_net_cxgbe.so.22.0' -> 'dpdk/pmds-22.0/librte_net_cxgbe.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_dpaa2.so' -> 'dpdk/pmds-22.0/librte_net_dpaa2.so'
null_resource.dpdk (remote-exec): './librte_net_dpaa2.so.22' -> 'dpdk/pmds-22.0/librte_net_dpaa2.so.22'
null_resource.dpdk (remote-exec): './librte_net_dpaa2.so.22.0' -> 'dpdk/pmds-22.0/librte_net_dpaa2.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_dpaa.so' -> 'dpdk/pmds-22.0/librte_net_dpaa.so'
null_resource.dpdk (remote-exec): './librte_net_dpaa.so.22' -> 'dpdk/pmds-22.0/librte_net_dpaa.so.22'
null_resource.dpdk (remote-exec): './librte_net_dpaa.so.22.0' -> 'dpdk/pmds-22.0/librte_net_dpaa.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_e1000.so' -> 'dpdk/pmds-22.0/librte_net_e1000.so'
null_resource.dpdk (remote-exec): './librte_net_e1000.so.22' -> 'dpdk/pmds-22.0/librte_net_e1000.so.22'
null_resource.dpdk (remote-exec): './librte_net_e1000.so.22.0' -> 'dpdk/pmds-22.0/librte_net_e1000.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_ena.so' -> 'dpdk/pmds-22.0/librte_net_ena.so'
null_resource.dpdk (remote-exec): './librte_net_ena.so.22' -> 'dpdk/pmds-22.0/librte_net_ena.so.22'
null_resource.dpdk (remote-exec): './librte_net_ena.so.22.0' -> 'dpdk/pmds-22.0/librte_net_ena.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_enetc.so' -> 'dpdk/pmds-22.0/librte_net_enetc.so'
null_resource.dpdk (remote-exec): './librte_net_enetc.so.22' -> 'dpdk/pmds-22.0/librte_net_enetc.so.22'
null_resource.dpdk (remote-exec): './librte_net_enetc.so.22.0' -> 'dpdk/pmds-22.0/librte_net_enetc.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_enetfec.so' -> 'dpdk/pmds-22.0/librte_net_enetfec.so'
null_resource.dpdk (remote-exec): './librte_net_enetfec.so.22' -> 'dpdk/pmds-22.0/librte_net_enetfec.so.22'
null_resource.dpdk (remote-exec): './librte_net_enetfec.so.22.0' -> 'dpdk/pmds-22.0/librte_net_enetfec.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_enic.so' -> 'dpdk/pmds-22.0/librte_net_enic.so'
null_resource.dpdk (remote-exec): './librte_net_enic.so.22' -> 'dpdk/pmds-22.0/librte_net_enic.so.22'
null_resource.dpdk (remote-exec): './librte_net_enic.so.22.0' -> 'dpdk/pmds-22.0/librte_net_enic.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_failsafe.so' -> 'dpdk/pmds-22.0/librte_net_failsafe.so'
null_resource.dpdk (remote-exec): './librte_net_failsafe.so.22' -> 'dpdk/pmds-22.0/librte_net_failsafe.so.22'
null_resource.dpdk (remote-exec): './librte_net_failsafe.so.22.0' -> 'dpdk/pmds-22.0/librte_net_failsafe.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_fm10k.so' -> 'dpdk/pmds-22.0/librte_net_fm10k.so'
null_resource.dpdk (remote-exec): './librte_net_fm10k.so.22' -> 'dpdk/pmds-22.0/librte_net_fm10k.so.22'
null_resource.dpdk (remote-exec): './librte_net_fm10k.so.22.0' -> 'dpdk/pmds-22.0/librte_net_fm10k.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_hinic.so' -> 'dpdk/pmds-22.0/librte_net_hinic.so'
null_resource.dpdk (remote-exec): './librte_net_hinic.so.22' -> 'dpdk/pmds-22.0/librte_net_hinic.so.22'
null_resource.dpdk (remote-exec): './librte_net_hinic.so.22.0' -> 'dpdk/pmds-22.0/librte_net_hinic.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_hns3.so' -> 'dpdk/pmds-22.0/librte_net_hns3.so'
null_resource.dpdk (remote-exec): './librte_net_hns3.so.22' -> 'dpdk/pmds-22.0/librte_net_hns3.so.22'
null_resource.dpdk (remote-exec): './librte_net_hns3.so.22.0' -> 'dpdk/pmds-22.0/librte_net_hns3.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_i40e.so' -> 'dpdk/pmds-22.0/librte_net_i40e.so'
null_resource.dpdk (remote-exec): './librte_net_i40e.so.22' -> 'dpdk/pmds-22.0/librte_net_i40e.so.22'
null_resource.dpdk (remote-exec): './librte_net_i40e.so.22.0' -> 'dpdk/pmds-22.0/librte_net_i40e.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_iavf.so' -> 'dpdk/pmds-22.0/librte_net_iavf.so'
null_resource.dpdk (remote-exec): './librte_net_iavf.so.22' -> 'dpdk/pmds-22.0/librte_net_iavf.so.22'
null_resource.dpdk (remote-exec): './librte_net_iavf.so.22.0' -> 'dpdk/pmds-22.0/librte_net_iavf.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_ice.so' -> 'dpdk/pmds-22.0/librte_net_ice.so'
null_resource.dpdk (remote-exec): './librte_net_ice.so.22' -> 'dpdk/pmds-22.0/librte_net_ice.so.22'
null_resource.dpdk (remote-exec): './librte_net_ice.so.22.0' -> 'dpdk/pmds-22.0/librte_net_ice.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_igc.so' -> 'dpdk/pmds-22.0/librte_net_igc.so'
null_resource.dpdk (remote-exec): './librte_net_igc.so.22' -> 'dpdk/pmds-22.0/librte_net_igc.so.22'
null_resource.dpdk (remote-exec): './librte_net_igc.so.22.0' -> 'dpdk/pmds-22.0/librte_net_igc.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_ionic.so' -> 'dpdk/pmds-22.0/librte_net_ionic.so'
null_resource.dpdk (remote-exec): './librte_net_ionic.so.22' -> 'dpdk/pmds-22.0/librte_net_ionic.so.22'
null_resource.dpdk (remote-exec): './librte_net_ionic.so.22.0' -> 'dpdk/pmds-22.0/librte_net_ionic.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_ixgbe.so' -> 'dpdk/pmds-22.0/librte_net_ixgbe.so'
null_resource.dpdk (remote-exec): './librte_net_ixgbe.so.22' -> 'dpdk/pmds-22.0/librte_net_ixgbe.so.22'
null_resource.dpdk (remote-exec): './librte_net_ixgbe.so.22.0' -> 'dpdk/pmds-22.0/librte_net_ixgbe.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_kni.so' -> 'dpdk/pmds-22.0/librte_net_kni.so'
null_resource.dpdk (remote-exec): './librte_net_kni.so.22' -> 'dpdk/pmds-22.0/librte_net_kni.so.22'
null_resource.dpdk (remote-exec): './librte_net_kni.so.22.0' -> 'dpdk/pmds-22.0/librte_net_kni.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_liquidio.so' -> 'dpdk/pmds-22.0/librte_net_liquidio.so'
null_resource.dpdk (remote-exec): './librte_net_liquidio.so.22' -> 'dpdk/pmds-22.0/librte_net_liquidio.so.22'
null_resource.dpdk (remote-exec): './librte_net_liquidio.so.22.0' -> 'dpdk/pmds-22.0/librte_net_liquidio.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_memif.so' -> 'dpdk/pmds-22.0/librte_net_memif.so'
null_resource.dpdk (remote-exec): './librte_net_memif.so.22' -> 'dpdk/pmds-22.0/librte_net_memif.so.22'
null_resource.dpdk (remote-exec): './librte_net_memif.so.22.0' -> 'dpdk/pmds-22.0/librte_net_memif.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_mlx4.so' -> 'dpdk/pmds-22.0/librte_net_mlx4.so'
null_resource.dpdk (remote-exec): './librte_net_mlx4.so.22' -> 'dpdk/pmds-22.0/librte_net_mlx4.so.22'
null_resource.dpdk (remote-exec): './librte_net_mlx4.so.22.0' -> 'dpdk/pmds-22.0/librte_net_mlx4.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_mlx5.so' -> 'dpdk/pmds-22.0/librte_net_mlx5.so'
null_resource.dpdk (remote-exec): './librte_net_mlx5.so.22' -> 'dpdk/pmds-22.0/librte_net_mlx5.so.22'
null_resource.dpdk (remote-exec): './librte_net_mlx5.so.22.0' -> 'dpdk/pmds-22.0/librte_net_mlx5.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_netvsc.so' -> 'dpdk/pmds-22.0/librte_net_netvsc.so'
null_resource.dpdk (remote-exec): './librte_net_netvsc.so.22' -> 'dpdk/pmds-22.0/librte_net_netvsc.so.22'
null_resource.dpdk (remote-exec): './librte_net_netvsc.so.22.0' -> 'dpdk/pmds-22.0/librte_net_netvsc.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_nfp.so' -> 'dpdk/pmds-22.0/librte_net_nfp.so'
null_resource.dpdk (remote-exec): './librte_net_nfp.so.22' -> 'dpdk/pmds-22.0/librte_net_nfp.so.22'
null_resource.dpdk (remote-exec): './librte_net_nfp.so.22.0' -> 'dpdk/pmds-22.0/librte_net_nfp.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_ngbe.so' -> 'dpdk/pmds-22.0/librte_net_ngbe.so'
null_resource.dpdk (remote-exec): './librte_net_ngbe.so.22' -> 'dpdk/pmds-22.0/librte_net_ngbe.so.22'
null_resource.dpdk (remote-exec): './librte_net_ngbe.so.22.0' -> 'dpdk/pmds-22.0/librte_net_ngbe.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_null.so' -> 'dpdk/pmds-22.0/librte_net_null.so'
null_resource.dpdk (remote-exec): './librte_net_null.so.22' -> 'dpdk/pmds-22.0/librte_net_null.so.22'
null_resource.dpdk (remote-exec): './librte_net_null.so.22.0' -> 'dpdk/pmds-22.0/librte_net_null.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_octeontx2.so' -> 'dpdk/pmds-22.0/librte_net_octeontx2.so'
null_resource.dpdk (remote-exec): './librte_net_octeontx2.so.22' -> 'dpdk/pmds-22.0/librte_net_octeontx2.so.22'
null_resource.dpdk (remote-exec): './librte_net_octeontx2.so.22.0' -> 'dpdk/pmds-22.0/librte_net_octeontx2.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_octeontx_ep.so' -> 'dpdk/pmds-22.0/librte_net_octeontx_ep.so'
null_resource.dpdk (remote-exec): './librte_net_octeontx_ep.so.22' -> 'dpdk/pmds-22.0/librte_net_octeontx_ep.so.22'
null_resource.dpdk (remote-exec): './librte_net_octeontx_ep.so.22.0' -> 'dpdk/pmds-22.0/librte_net_octeontx_ep.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_octeontx.so' -> 'dpdk/pmds-22.0/librte_net_octeontx.so'
null_resource.dpdk (remote-exec): './librte_net_octeontx.so.22' -> 'dpdk/pmds-22.0/librte_net_octeontx.so.22'
null_resource.dpdk (remote-exec): './librte_net_octeontx.so.22.0' -> 'dpdk/pmds-22.0/librte_net_octeontx.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_pcap.so' -> 'dpdk/pmds-22.0/librte_net_pcap.so'
null_resource.dpdk (remote-exec): './librte_net_pcap.so.22' -> 'dpdk/pmds-22.0/librte_net_pcap.so.22'
null_resource.dpdk (remote-exec): './librte_net_pcap.so.22.0' -> 'dpdk/pmds-22.0/librte_net_pcap.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_pfe.so' -> 'dpdk/pmds-22.0/librte_net_pfe.so'
null_resource.dpdk (remote-exec): './librte_net_pfe.so.22' -> 'dpdk/pmds-22.0/librte_net_pfe.so.22'
null_resource.dpdk (remote-exec): './librte_net_pfe.so.22.0' -> 'dpdk/pmds-22.0/librte_net_pfe.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_qede.so' -> 'dpdk/pmds-22.0/librte_net_qede.so'
null_resource.dpdk (remote-exec): './librte_net_qede.so.22' -> 'dpdk/pmds-22.0/librte_net_qede.so.22'
null_resource.dpdk (remote-exec): './librte_net_qede.so.22.0' -> 'dpdk/pmds-22.0/librte_net_qede.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_ring.so' -> 'dpdk/pmds-22.0/librte_net_ring.so'
null_resource.dpdk (remote-exec): './librte_net_ring.so.22' -> 'dpdk/pmds-22.0/librte_net_ring.so.22'
null_resource.dpdk (remote-exec): './librte_net_ring.so.22.0' -> 'dpdk/pmds-22.0/librte_net_ring.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_sfc.so' -> 'dpdk/pmds-22.0/librte_net_sfc.so'
null_resource.dpdk (remote-exec): './librte_net_sfc.so.22' -> 'dpdk/pmds-22.0/librte_net_sfc.so.22'
null_resource.dpdk (remote-exec): './librte_net_sfc.so.22.0' -> 'dpdk/pmds-22.0/librte_net_sfc.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_softnic.so' -> 'dpdk/pmds-22.0/librte_net_softnic.so'
null_resource.dpdk (remote-exec): './librte_net_softnic.so.22' -> 'dpdk/pmds-22.0/librte_net_softnic.so.22'
null_resource.dpdk (remote-exec): './librte_net_softnic.so.22.0' -> 'dpdk/pmds-22.0/librte_net_softnic.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_tap.so' -> 'dpdk/pmds-22.0/librte_net_tap.so'
null_resource.dpdk (remote-exec): './librte_net_tap.so.22' -> 'dpdk/pmds-22.0/librte_net_tap.so.22'
null_resource.dpdk (remote-exec): './librte_net_tap.so.22.0' -> 'dpdk/pmds-22.0/librte_net_tap.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_thunderx.so' -> 'dpdk/pmds-22.0/librte_net_thunderx.so'
null_resource.dpdk (remote-exec): './librte_net_thunderx.so.22' -> 'dpdk/pmds-22.0/librte_net_thunderx.so.22'
null_resource.dpdk (remote-exec): './librte_net_thunderx.so.22.0' -> 'dpdk/pmds-22.0/librte_net_thunderx.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_txgbe.so' -> 'dpdk/pmds-22.0/librte_net_txgbe.so'
null_resource.dpdk (remote-exec): './librte_net_txgbe.so.22' -> 'dpdk/pmds-22.0/librte_net_txgbe.so.22'
null_resource.dpdk (remote-exec): './librte_net_txgbe.so.22.0' -> 'dpdk/pmds-22.0/librte_net_txgbe.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_vdev_netvsc.so' -> 'dpdk/pmds-22.0/librte_net_vdev_netvsc.so'
null_resource.dpdk (remote-exec): './librte_net_vdev_netvsc.so.22' -> 'dpdk/pmds-22.0/librte_net_vdev_netvsc.so.22'
null_resource.dpdk (remote-exec): './librte_net_vdev_netvsc.so.22.0' -> 'dpdk/pmds-22.0/librte_net_vdev_netvsc.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_vhost.so' -> 'dpdk/pmds-22.0/librte_net_vhost.so'
null_resource.dpdk (remote-exec): './librte_net_vhost.so.22' -> 'dpdk/pmds-22.0/librte_net_vhost.so.22'
null_resource.dpdk (remote-exec): './librte_net_vhost.so.22.0' -> 'dpdk/pmds-22.0/librte_net_vhost.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_virtio.so' -> 'dpdk/pmds-22.0/librte_net_virtio.so'
null_resource.dpdk (remote-exec): './librte_net_virtio.so.22' -> 'dpdk/pmds-22.0/librte_net_virtio.so.22'
null_resource.dpdk (remote-exec): './librte_net_virtio.so.22.0' -> 'dpdk/pmds-22.0/librte_net_virtio.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_vmxnet3.so' -> 'dpdk/pmds-22.0/librte_net_vmxnet3.so'
null_resource.dpdk (remote-exec): './librte_net_vmxnet3.so.22' -> 'dpdk/pmds-22.0/librte_net_vmxnet3.so.22'
null_resource.dpdk (remote-exec): './librte_net_vmxnet3.so.22.0' -> 'dpdk/pmds-22.0/librte_net_vmxnet3.so.22.0'
null_resource.dpdk (remote-exec): './librte_raw_cnxk_bphy.so' -> 'dpdk/pmds-22.0/librte_raw_cnxk_bphy.so'
null_resource.dpdk (remote-exec): './librte_raw_cnxk_bphy.so.22' -> 'dpdk/pmds-22.0/librte_raw_cnxk_bphy.so.22'
null_resource.dpdk (remote-exec): './librte_raw_cnxk_bphy.so.22.0' -> 'dpdk/pmds-22.0/librte_raw_cnxk_bphy.so.22.0'
null_resource.dpdk (remote-exec): './librte_raw_dpaa2_cmdif.so' -> 'dpdk/pmds-22.0/librte_raw_dpaa2_cmdif.so'
null_resource.dpdk (remote-exec): './librte_raw_dpaa2_cmdif.so.22' -> 'dpdk/pmds-22.0/librte_raw_dpaa2_cmdif.so.22'
null_resource.dpdk (remote-exec): './librte_raw_dpaa2_cmdif.so.22.0' -> 'dpdk/pmds-22.0/librte_raw_dpaa2_cmdif.so.22.0'
null_resource.dpdk (remote-exec): './librte_raw_dpaa2_qdma.so' -> 'dpdk/pmds-22.0/librte_raw_dpaa2_qdma.so'
null_resource.dpdk (remote-exec): './librte_raw_dpaa2_qdma.so.22' -> 'dpdk/pmds-22.0/librte_raw_dpaa2_qdma.so.22'
null_resource.dpdk (remote-exec): './librte_raw_dpaa2_qdma.so.22.0' -> 'dpdk/pmds-22.0/librte_raw_dpaa2_qdma.so.22.0'
null_resource.dpdk (remote-exec): './librte_raw_ntb.so' -> 'dpdk/pmds-22.0/librte_raw_ntb.so'
null_resource.dpdk (remote-exec): './librte_raw_ntb.so.22' -> 'dpdk/pmds-22.0/librte_raw_ntb.so.22'
null_resource.dpdk (remote-exec): './librte_raw_ntb.so.22.0' -> 'dpdk/pmds-22.0/librte_raw_ntb.so.22.0'
null_resource.dpdk (remote-exec): './librte_raw_skeleton.so' -> 'dpdk/pmds-22.0/librte_raw_skeleton.so'
null_resource.dpdk (remote-exec): './librte_raw_skeleton.so.22' -> 'dpdk/pmds-22.0/librte_raw_skeleton.so.22'
null_resource.dpdk (remote-exec): './librte_raw_skeleton.so.22.0' -> 'dpdk/pmds-22.0/librte_raw_skeleton.so.22.0'
null_resource.dpdk (remote-exec): './librte_regex_mlx5.so' -> 'dpdk/pmds-22.0/librte_regex_mlx5.so'
null_resource.dpdk (remote-exec): './librte_regex_mlx5.so.22' -> 'dpdk/pmds-22.0/librte_regex_mlx5.so.22'
null_resource.dpdk (remote-exec): './librte_regex_mlx5.so.22.0' -> 'dpdk/pmds-22.0/librte_regex_mlx5.so.22.0'
null_resource.dpdk (remote-exec): './librte_regex_octeontx2.so' -> 'dpdk/pmds-22.0/librte_regex_octeontx2.so'
null_resource.dpdk (remote-exec): './librte_regex_octeontx2.so.22' -> 'dpdk/pmds-22.0/librte_regex_octeontx2.so.22'
null_resource.dpdk (remote-exec): './librte_regex_octeontx2.so.22.0' -> 'dpdk/pmds-22.0/librte_regex_octeontx2.so.22.0'
null_resource.dpdk (remote-exec): './librte_vdpa_ifc.so' -> 'dpdk/pmds-22.0/librte_vdpa_ifc.so'
null_resource.dpdk (remote-exec): './librte_vdpa_ifc.so.22' -> 'dpdk/pmds-22.0/librte_vdpa_ifc.so.22'
null_resource.dpdk (remote-exec): './librte_vdpa_ifc.so.22.0' -> 'dpdk/pmds-22.0/librte_vdpa_ifc.so.22.0'
null_resource.dpdk (remote-exec): './librte_vdpa_mlx5.so' -> 'dpdk/pmds-22.0/librte_vdpa_mlx5.so'
null_resource.dpdk (remote-exec): './librte_vdpa_mlx5.so.22' -> 'dpdk/pmds-22.0/librte_vdpa_mlx5.so.22'
null_resource.dpdk (remote-exec): './librte_vdpa_mlx5.so.22.0' -> 'dpdk/pmds-22.0/librte_vdpa_mlx5.so.22.0'
null_resource.dpdk (remote-exec): './librte_vdpa_sfc.so' -> 'dpdk/pmds-22.0/librte_vdpa_sfc.so'
null_resource.dpdk (remote-exec): './librte_vdpa_sfc.so.22' -> 'dpdk/pmds-22.0/librte_vdpa_sfc.so.22'
null_resource.dpdk (remote-exec): './librte_vdpa_sfc.so.22.0' -> 'dpdk/pmds-22.0/librte_vdpa_sfc.so.22.0'
null_resource.dpdk: Creation complete after 8m28s [id=2421476301113403266]

Apply complete! Resources: 6 added, 0 changed, 0 destroyed.

Outputs: './librte_baseband_acc100.so' -> 'dpdk/pmds-22.0/librte_baseband_acc100.so'
null_resource.dpdk (remote-exec): './librte_baseband_acc100.so.22' -> 'dpdk/pmds-22.0/librte_baseband_acc100.so.22'
null_resource.dpdk (remote-exec): './librte_baseband_acc100.so.22.0' -> 'dpdk/pmds-22.0/librte_baseband_acc100.so.22.0'
null_resource.dpdk (remote-exec): './librte_baseband_fpga_5gnr_fec.so' -> 'dpdk/pmds-22.0/librte_baseband_fpga_5gnr_fec.so'
null_resource.dpdk (remote-exec): './librte_baseband_fpga_5gnr_fec.so.22' -> 'dpdk/pmds-22.0/librte_baseband_fpga_5gnr_fec.so.22'
null_resource.dpdk (remote-exec): './librte_baseband_fpga_5gnr_fec.so.22.0' -> 'dpdk/pmds-22.0/librte_baseband_fpga_5gnr_fec.so.22.0'
null_resource.dpdk (remote-exec): './librte_baseband_fpga_lte_fec.so' -> 'dpdk/pmds-22.0/librte_baseband_fpga_lte_fec.so'
null_resource.dpdk (remote-exec): './librte_baseband_fpga_lte_fec.so.22' -> 'dpdk/pmds-22.0/librte_baseband_fpga_lte_fec.so.22'
null_resource.dpdk (remote-exec): './librte_baseband_fpga_lte_fec.so.22.0' -> 'dpdk/pmds-22.0/librte_baseband_fpga_lte_fec.so.22.0'
null_resource.dpdk (remote-exec): './librte_baseband_la12xx.so' -> 'dpdk/pmds-22.0/librte_baseband_la12xx.so'
null_resource.dpdk (remote-exec): './librte_baseband_la12xx.so.22' -> 'dpdk/pmds-22.0/librte_baseband_la12xx.so.22'
null_resource.dpdk (remote-exec): './librte_baseband_la12xx.so.22.0' -> 'dpdk/pmds-22.0/librte_baseband_la12xx.so.22.0'
null_resource.dpdk (remote-exec): './librte_baseband_null.so' -> 'dpdk/pmds-22.0/librte_baseband_null.so'
null_resource.dpdk (remote-exec): './librte_baseband_null.so.22' -> 'dpdk/pmds-22.0/librte_baseband_null.so.22'
null_resource.dpdk (remote-exec): './librte_baseband_null.so.22.0' -> 'dpdk/pmds-22.0/librte_baseband_null.so.22.0'
null_resource.dpdk (remote-exec): './librte_baseband_turbo_sw.so' -> 'dpdk/pmds-22.0/librte_baseband_turbo_sw.so'
null_resource.dpdk (remote-exec): './librte_baseband_turbo_sw.so.22' -> 'dpdk/pmds-22.0/librte_baseband_turbo_sw.so.22'
null_resource.dpdk (remote-exec): './librte_baseband_turbo_sw.so.22.0' -> 'dpdk/pmds-22.0/librte_baseband_turbo_sw.so.22.0'
null_resource.dpdk (remote-exec): './librte_bus_auxiliary.so' -> 'dpdk/pmds-22.0/librte_bus_auxiliary.so'
null_resource.dpdk (remote-exec): './librte_bus_auxiliary.so.22' -> 'dpdk/pmds-22.0/librte_bus_auxiliary.so.22'
null_resource.dpdk (remote-exec): './librte_bus_auxiliary.so.22.0' -> 'dpdk/pmds-22.0/librte_bus_auxiliary.so.22.0'
null_resource.dpdk (remote-exec): './librte_bus_dpaa.so' -> 'dpdk/pmds-22.0/librte_bus_dpaa.so'
null_resource.dpdk (remote-exec): './librte_bus_dpaa.so.22' -> 'dpdk/pmds-22.0/librte_bus_dpaa.so.22'
null_resource.dpdk (remote-exec): './librte_bus_dpaa.so.22.0' -> 'dpdk/pmds-22.0/librte_bus_dpaa.so.22.0'
null_resource.dpdk (remote-exec): './librte_bus_fslmc.so' -> 'dpdk/pmds-22.0/librte_bus_fslmc.so'
null_resource.dpdk (remote-exec): './librte_bus_fslmc.so.22' -> 'dpdk/pmds-22.0/librte_bus_fslmc.so.22'
null_resource.dpdk (remote-exec): './librte_bus_fslmc.so.22.0' -> 'dpdk/pmds-22.0/librte_bus_fslmc.so.22.0'
null_resource.dpdk (remote-exec): './librte_bus_ifpga.so' -> 'dpdk/pmds-22.0/librte_bus_ifpga.so'
null_resource.dpdk (remote-exec): './librte_bus_ifpga.so.22' -> 'dpdk/pmds-22.0/librte_bus_ifpga.so.22'
null_resource.dpdk (remote-exec): './librte_bus_ifpga.so.22.0' -> 'dpdk/pmds-22.0/librte_bus_ifpga.so.22.0'
null_resource.dpdk (remote-exec): './librte_bus_pci.so' -> 'dpdk/pmds-22.0/librte_bus_pci.so'
null_resource.dpdk (remote-exec): './librte_bus_pci.so.22' -> 'dpdk/pmds-22.0/librte_bus_pci.so.22'
null_resource.dpdk (remote-exec): './librte_bus_pci.so.22.0' -> 'dpdk/pmds-22.0/librte_bus_pci.so.22.0'
null_resource.dpdk (remote-exec): './librte_bus_vdev.so' -> 'dpdk/pmds-22.0/librte_bus_vdev.so'
null_resource.dpdk (remote-exec): './librte_bus_vdev.so.22' -> 'dpdk/pmds-22.0/librte_bus_vdev.so.22'
null_resource.dpdk (remote-exec): './librte_bus_vdev.so.22.0' -> 'dpdk/pmds-22.0/librte_bus_vdev.so.22.0'
null_resource.dpdk (remote-exec): './librte_bus_vmbus.so' -> 'dpdk/pmds-22.0/librte_bus_vmbus.so'
null_resource.dpdk (remote-exec): './librte_bus_vmbus.so.22' -> 'dpdk/pmds-22.0/librte_bus_vmbus.so.22'
null_resource.dpdk (remote-exec): './librte_bus_vmbus.so.22.0' -> 'dpdk/pmds-22.0/librte_bus_vmbus.so.22.0'
null_resource.dpdk (remote-exec): './librte_common_cnxk.so' -> 'dpdk/pmds-22.0/librte_common_cnxk.so'
null_resource.dpdk (remote-exec): './librte_common_cnxk.so.22' -> 'dpdk/pmds-22.0/librte_common_cnxk.so.22'
null_resource.dpdk (remote-exec): './librte_common_cnxk.so.22.0' -> 'dpdk/pmds-22.0/librte_common_cnxk.so.22.0'
null_resource.dpdk (remote-exec): './librte_common_cpt.so' -> 'dpdk/pmds-22.0/librte_common_cpt.so'
null_resource.dpdk (remote-exec): './librte_common_cpt.so.22' -> 'dpdk/pmds-22.0/librte_common_cpt.so.22'
null_resource.dpdk (remote-exec): './librte_common_cpt.so.22.0' -> 'dpdk/pmds-22.0/librte_common_cpt.so.22.0'
null_resource.dpdk (remote-exec): './librte_common_dpaax.so' -> 'dpdk/pmds-22.0/librte_common_dpaax.so'
null_resource.dpdk (remote-exec): './librte_common_dpaax.so.22' -> 'dpdk/pmds-22.0/librte_common_dpaax.so.22'
null_resource.dpdk (remote-exec): './librte_common_dpaax.so.22.0' -> 'dpdk/pmds-22.0/librte_common_dpaax.so.22.0'
null_resource.dpdk (remote-exec): './librte_common_iavf.so' -> 'dpdk/pmds-22.0/librte_common_iavf.so'
null_resource.dpdk (remote-exec): './librte_common_iavf.so.22' -> 'dpdk/pmds-22.0/librte_common_iavf.so.22'
null_resource.dpdk (remote-exec): './librte_common_iavf.so.22.0' -> 'dpdk/pmds-22.0/librte_common_iavf.so.22.0'
null_resource.dpdk (remote-exec): './librte_common_mlx5.so' -> 'dpdk/pmds-22.0/librte_common_mlx5.so'
null_resource.dpdk (remote-exec): './librte_common_mlx5.so.22' -> 'dpdk/pmds-22.0/librte_common_mlx5.so.22'
null_resource.dpdk (remote-exec): './librte_common_mlx5.so.22.0' -> 'dpdk/pmds-22.0/librte_common_mlx5.so.22.0'
null_resource.dpdk (remote-exec): './librte_common_octeontx2.so' -> 'dpdk/pmds-22.0/librte_common_octeontx2.so'
null_resource.dpdk (remote-exec): './librte_common_octeontx2.so.22' -> 'dpdk/pmds-22.0/librte_common_octeontx2.so.22'
null_resource.dpdk (remote-exec): './librte_common_octeontx2.so.22.0' -> 'dpdk/pmds-22.0/librte_common_octeontx2.so.22.0'
null_resource.dpdk (remote-exec): './librte_common_octeontx.so' -> 'dpdk/pmds-22.0/librte_common_octeontx.so'
null_resource.dpdk (remote-exec): './librte_common_octeontx.so.22' -> 'dpdk/pmds-22.0/librte_common_octeontx.so.22'
null_resource.dpdk (remote-exec): './librte_common_octeontx.so.22.0' -> 'dpdk/pmds-22.0/librte_common_octeontx.so.22.0'
null_resource.dpdk (remote-exec): './librte_common_qat.so' -> 'dpdk/pmds-22.0/librte_common_qat.so'
null_resource.dpdk (remote-exec): './librte_common_qat.so.22' -> 'dpdk/pmds-22.0/librte_common_qat.so.22'
null_resource.dpdk (remote-exec): './librte_common_qat.so.22.0' -> 'dpdk/pmds-22.0/librte_common_qat.so.22.0'
null_resource.dpdk (remote-exec): './librte_common_sfc_efx.so' -> 'dpdk/pmds-22.0/librte_common_sfc_efx.so'
null_resource.dpdk (remote-exec): './librte_common_sfc_efx.so.22' -> 'dpdk/pmds-22.0/librte_common_sfc_efx.so.22'
null_resource.dpdk (remote-exec): './librte_common_sfc_efx.so.22.0' -> 'dpdk/pmds-22.0/librte_common_sfc_efx.so.22.0'
null_resource.dpdk (remote-exec): './librte_compress_isal.so' -> 'dpdk/pmds-22.0/librte_compress_isal.so'
null_resource.dpdk (remote-exec): './librte_compress_isal.so.22' -> 'dpdk/pmds-22.0/librte_compress_isal.so.22'
null_resource.dpdk (remote-exec): './librte_compress_isal.so.22.0' -> 'dpdk/pmds-22.0/librte_compress_isal.so.22.0'
null_resource.dpdk (remote-exec): './librte_compress_mlx5.so' -> 'dpdk/pmds-22.0/librte_compress_mlx5.so'
null_resource.dpdk (remote-exec): './librte_compress_mlx5.so.22' -> 'dpdk/pmds-22.0/librte_compress_mlx5.so.22'
null_resource.dpdk (remote-exec): './librte_compress_mlx5.so.22.0' -> 'dpdk/pmds-22.0/librte_compress_mlx5.so.22.0'
null_resource.dpdk (remote-exec): './librte_compress_octeontx.so' -> 'dpdk/pmds-22.0/librte_compress_octeontx.so'
null_resource.dpdk (remote-exec): './librte_compress_octeontx.so.22' -> 'dpdk/pmds-22.0/librte_compress_octeontx.so.22'
null_resource.dpdk (remote-exec): './librte_compress_octeontx.so.22.0' -> 'dpdk/pmds-22.0/librte_compress_octeontx.so.22.0'
null_resource.dpdk (remote-exec): './librte_compress_zlib.so' -> 'dpdk/pmds-22.0/librte_compress_zlib.so'
null_resource.dpdk (remote-exec): './librte_compress_zlib.so.22' -> 'dpdk/pmds-22.0/librte_compress_zlib.so.22'
null_resource.dpdk (remote-exec): './librte_compress_zlib.so.22.0' -> 'dpdk/pmds-22.0/librte_compress_zlib.so.22.0'
null_resource.dpdk (remote-exec): './librte_crypto_bcmfs.so' -> 'dpdk/pmds-22.0/librte_crypto_bcmfs.so'
null_resource.dpdk (remote-exec): './librte_crypto_bcmfs.so.22' -> 'dpdk/pmds-22.0/librte_crypto_bcmfs.so.22'
null_resource.dpdk (remote-exec): './librte_crypto_bcmfs.so.22.0' -> 'dpdk/pmds-22.0/librte_crypto_bcmfs.so.22.0'
null_resource.dpdk (remote-exec): './librte_crypto_caam_jr.so' -> 'dpdk/pmds-22.0/librte_crypto_caam_jr.so'
null_resource.dpdk (remote-exec): './librte_crypto_caam_jr.so.22' -> 'dpdk/pmds-22.0/librte_crypto_caam_jr.so.22'
null_resource.dpdk (remote-exec): './librte_crypto_caam_jr.so.22.0' -> 'dpdk/pmds-22.0/librte_crypto_caam_jr.so.22.0'
null_resource.dpdk (remote-exec): './librte_crypto_ccp.so' -> 'dpdk/pmds-22.0/librte_crypto_ccp.so'
null_resource.dpdk (remote-exec): './librte_crypto_ccp.so.22' -> 'dpdk/pmds-22.0/librte_crypto_ccp.so.22'
null_resource.dpdk (remote-exec): './librte_crypto_ccp.so.22.0' -> 'dpdk/pmds-22.0/librte_crypto_ccp.so.22.0'
null_resource.dpdk (remote-exec): './librte_crypto_cnxk.so' -> 'dpdk/pmds-22.0/librte_crypto_cnxk.so'
null_resource.dpdk (remote-exec): './librte_crypto_cnxk.so.22' -> 'dpdk/pmds-22.0/librte_crypto_cnxk.so.22'
null_resource.dpdk (remote-exec): './librte_crypto_cnxk.so.22.0' -> 'dpdk/pmds-22.0/librte_crypto_cnxk.so.22.0'
null_resource.dpdk (remote-exec): './librte_crypto_dpaa2_sec.so' -> 'dpdk/pmds-22.0/librte_crypto_dpaa2_sec.so'
null_resource.dpdk (remote-exec): './librte_crypto_dpaa2_sec.so.22' -> 'dpdk/pmds-22.0/librte_crypto_dpaa2_sec.so.22'
null_resource.dpdk (remote-exec): './librte_crypto_dpaa2_sec.so.22.0' -> 'dpdk/pmds-22.0/librte_crypto_dpaa2_sec.so.22.0'
null_resource.dpdk (remote-exec): './librte_crypto_dpaa_sec.so' -> 'dpdk/pmds-22.0/librte_crypto_dpaa_sec.so'
null_resource.dpdk (remote-exec): './librte_crypto_dpaa_sec.so.22' -> 'dpdk/pmds-22.0/librte_crypto_dpaa_sec.so.22'
null_resource.dpdk (remote-exec): './librte_crypto_dpaa_sec.so.22.0' -> 'dpdk/pmds-22.0/librte_crypto_dpaa_sec.so.22.0'
null_resource.dpdk (remote-exec): './librte_crypto_ipsec_mb.so' -> 'dpdk/pmds-22.0/librte_crypto_ipsec_mb.so'
null_resource.dpdk (remote-exec): './librte_crypto_ipsec_mb.so.22' -> 'dpdk/pmds-22.0/librte_crypto_ipsec_mb.so.22'
null_resource.dpdk (remote-exec): './librte_crypto_ipsec_mb.so.22.0' -> 'dpdk/pmds-22.0/librte_crypto_ipsec_mb.so.22.0'
null_resource.dpdk (remote-exec): './librte_crypto_mlx5.so' -> 'dpdk/pmds-22.0/librte_crypto_mlx5.so'
null_resource.dpdk (remote-exec): './librte_crypto_mlx5.so.22' -> 'dpdk/pmds-22.0/librte_crypto_mlx5.so.22'
null_resource.dpdk (remote-exec): './librte_crypto_mlx5.so.22.0' -> 'dpdk/pmds-22.0/librte_crypto_mlx5.so.22.0'
null_resource.dpdk (remote-exec): './librte_crypto_nitrox.so' -> 'dpdk/pmds-22.0/librte_crypto_nitrox.so'
null_resource.dpdk (remote-exec): './librte_crypto_nitrox.so.22' -> 'dpdk/pmds-22.0/librte_crypto_nitrox.so.22'
null_resource.dpdk (remote-exec): './librte_crypto_nitrox.so.22.0' -> 'dpdk/pmds-22.0/librte_crypto_nitrox.so.22.0'
null_resource.dpdk (remote-exec): './librte_crypto_null.so' -> 'dpdk/pmds-22.0/librte_crypto_null.so'
null_resource.dpdk (remote-exec): './librte_crypto_null.so.22' -> 'dpdk/pmds-22.0/librte_crypto_null.so.22'
null_resource.dpdk (remote-exec): './librte_crypto_null.so.22.0' -> 'dpdk/pmds-22.0/librte_crypto_null.so.22.0'
null_resource.dpdk (remote-exec): './librte_crypto_octeontx2.so' -> 'dpdk/pmds-22.0/librte_crypto_octeontx2.so'
null_resource.dpdk (remote-exec): './librte_crypto_octeontx2.so.22' -> 'dpdk/pmds-22.0/librte_crypto_octeontx2.so.22'
null_resource.dpdk (remote-exec): './librte_crypto_octeontx2.so.22.0' -> 'dpdk/pmds-22.0/librte_crypto_octeontx2.so.22.0'
null_resource.dpdk (remote-exec): './librte_crypto_octeontx.so' -> 'dpdk/pmds-22.0/librte_crypto_octeontx.so'
null_resource.dpdk (remote-exec): './librte_crypto_octeontx.so.22' -> 'dpdk/pmds-22.0/librte_crypto_octeontx.so.22'
null_resource.dpdk (remote-exec): './librte_crypto_octeontx.so.22.0' -> 'dpdk/pmds-22.0/librte_crypto_octeontx.so.22.0'
null_resource.dpdk (remote-exec): './librte_crypto_openssl.so' -> 'dpdk/pmds-22.0/librte_crypto_openssl.so'
null_resource.dpdk (remote-exec): './librte_crypto_openssl.so.22' -> 'dpdk/pmds-22.0/librte_crypto_openssl.so.22'
null_resource.dpdk (remote-exec): './librte_crypto_openssl.so.22.0' -> 'dpdk/pmds-22.0/librte_crypto_openssl.so.22.0'
null_resource.dpdk (remote-exec): './librte_crypto_scheduler.so' -> 'dpdk/pmds-22.0/librte_crypto_scheduler.so'
null_resource.dpdk (remote-exec): './librte_crypto_scheduler.so.22' -> 'dpdk/pmds-22.0/librte_crypto_scheduler.so.22'
null_resource.dpdk (remote-exec): './librte_crypto_scheduler.so.22.0' -> 'dpdk/pmds-22.0/librte_crypto_scheduler.so.22.0'
null_resource.dpdk (remote-exec): './librte_crypto_virtio.so' -> 'dpdk/pmds-22.0/librte_crypto_virtio.so'
null_resource.dpdk (remote-exec): './librte_crypto_virtio.so.22' -> 'dpdk/pmds-22.0/librte_crypto_virtio.so.22'
null_resource.dpdk (remote-exec): './librte_crypto_virtio.so.22.0' -> 'dpdk/pmds-22.0/librte_crypto_virtio.so.22.0'
null_resource.dpdk (remote-exec): './librte_dma_cnxk.so' -> 'dpdk/pmds-22.0/librte_dma_cnxk.so'
null_resource.dpdk (remote-exec): './librte_dma_cnxk.so.22' -> 'dpdk/pmds-22.0/librte_dma_cnxk.so.22'
null_resource.dpdk (remote-exec): './librte_dma_cnxk.so.22.0' -> 'dpdk/pmds-22.0/librte_dma_cnxk.so.22.0'
null_resource.dpdk (remote-exec): './librte_dma_dpaa.so' -> 'dpdk/pmds-22.0/librte_dma_dpaa.so'
null_resource.dpdk (remote-exec): './librte_dma_dpaa.so.22' -> 'dpdk/pmds-22.0/librte_dma_dpaa.so.22'
null_resource.dpdk (remote-exec): './librte_dma_dpaa.so.22.0' -> 'dpdk/pmds-22.0/librte_dma_dpaa.so.22.0'
null_resource.dpdk (remote-exec): './librte_dma_hisilicon.so' -> 'dpdk/pmds-22.0/librte_dma_hisilicon.so'
null_resource.dpdk (remote-exec): './librte_dma_hisilicon.so.22' -> 'dpdk/pmds-22.0/librte_dma_hisilicon.so.22'
null_resource.dpdk (remote-exec): './librte_dma_hisilicon.so.22.0' -> 'dpdk/pmds-22.0/librte_dma_hisilicon.so.22.0'
null_resource.dpdk (remote-exec): './librte_dma_idxd.so' -> 'dpdk/pmds-22.0/librte_dma_idxd.so'
null_resource.dpdk (remote-exec): './librte_dma_idxd.so.22' -> 'dpdk/pmds-22.0/librte_dma_idxd.so.22'
null_resource.dpdk (remote-exec): './librte_dma_idxd.so.22.0' -> 'dpdk/pmds-22.0/librte_dma_idxd.so.22.0'
null_resource.dpdk (remote-exec): './librte_dma_ioat.so' -> 'dpdk/pmds-22.0/librte_dma_ioat.so'
null_resource.dpdk (remote-exec): './librte_dma_ioat.so.22' -> 'dpdk/pmds-22.0/librte_dma_ioat.so.22'
null_resource.dpdk (remote-exec): './librte_dma_ioat.so.22.0' -> 'dpdk/pmds-22.0/librte_dma_ioat.so.22.0'
null_resource.dpdk (remote-exec): './librte_dma_skeleton.so' -> 'dpdk/pmds-22.0/librte_dma_skeleton.so'
null_resource.dpdk (remote-exec): './librte_dma_skeleton.so.22' -> 'dpdk/pmds-22.0/librte_dma_skeleton.so.22'
null_resource.dpdk (remote-exec): './librte_dma_skeleton.so.22.0' -> 'dpdk/pmds-22.0/librte_dma_skeleton.so.22.0'
null_resource.dpdk (remote-exec): './librte_event_cnxk.so' -> 'dpdk/pmds-22.0/librte_event_cnxk.so'
null_resource.dpdk (remote-exec): './librte_event_cnxk.so.22' -> 'dpdk/pmds-22.0/librte_event_cnxk.so.22'
null_resource.dpdk (remote-exec): './librte_event_cnxk.so.22.0' -> 'dpdk/pmds-22.0/librte_event_cnxk.so.22.0'
null_resource.dpdk (remote-exec): './librte_event_dlb2.so' -> 'dpdk/pmds-22.0/librte_event_dlb2.so'
null_resource.dpdk (remote-exec): './librte_event_dlb2.so.22' -> 'dpdk/pmds-22.0/librte_event_dlb2.so.22'
null_resource.dpdk (remote-exec): './librte_event_dlb2.so.22.0' -> 'dpdk/pmds-22.0/librte_event_dlb2.so.22.0'
null_resource.dpdk (remote-exec): './librte_event_dpaa2.so' -> 'dpdk/pmds-22.0/librte_event_dpaa2.so'
null_resource.dpdk (remote-exec): './librte_event_dpaa2.so.22' -> 'dpdk/pmds-22.0/librte_event_dpaa2.so.22'
null_resource.dpdk (remote-exec): './librte_event_dpaa2.so.22.0' -> 'dpdk/pmds-22.0/librte_event_dpaa2.so.22.0'
null_resource.dpdk (remote-exec): './librte_event_dpaa.so' -> 'dpdk/pmds-22.0/librte_event_dpaa.so'
null_resource.dpdk (remote-exec): './librte_event_dpaa.so.22' -> 'dpdk/pmds-22.0/librte_event_dpaa.so.22'
null_resource.dpdk (remote-exec): './librte_event_dpaa.so.22.0' -> 'dpdk/pmds-22.0/librte_event_dpaa.so.22.0'
null_resource.dpdk (remote-exec): './librte_event_dsw.so' -> 'dpdk/pmds-22.0/librte_event_dsw.so'
null_resource.dpdk (remote-exec): './librte_event_dsw.so.22' -> 'dpdk/pmds-22.0/librte_event_dsw.so.22'
null_resource.dpdk (remote-exec): './librte_event_dsw.so.22.0' -> 'dpdk/pmds-22.0/librte_event_dsw.so.22.0'
null_resource.dpdk (remote-exec): './librte_event_octeontx2.so' -> 'dpdk/pmds-22.0/librte_event_octeontx2.so'
null_resource.dpdk (remote-exec): './librte_event_octeontx2.so.22' -> 'dpdk/pmds-22.0/librte_event_octeontx2.so.22'
null_resource.dpdk (remote-exec): './librte_event_octeontx2.so.22.0' -> 'dpdk/pmds-22.0/librte_event_octeontx2.so.22.0'
null_resource.dpdk (remote-exec): './librte_event_octeontx.so' -> 'dpdk/pmds-22.0/librte_event_octeontx.so'
null_resource.dpdk (remote-exec): './librte_event_octeontx.so.22' -> 'dpdk/pmds-22.0/librte_event_octeontx.so.22'
null_resource.dpdk (remote-exec): './librte_event_octeontx.so.22.0' -> 'dpdk/pmds-22.0/librte_event_octeontx.so.22.0'
null_resource.dpdk (remote-exec): './librte_event_opdl.so' -> 'dpdk/pmds-22.0/librte_event_opdl.so'
null_resource.dpdk (remote-exec): './librte_event_opdl.so.22' -> 'dpdk/pmds-22.0/librte_event_opdl.so.22'
null_resource.dpdk (remote-exec): './librte_event_opdl.so.22.0' -> 'dpdk/pmds-22.0/librte_event_opdl.so.22.0'
null_resource.dpdk (remote-exec): './librte_event_skeleton.so' -> 'dpdk/pmds-22.0/librte_event_skeleton.so'
null_resource.dpdk (remote-exec): './librte_event_skeleton.so.22' -> 'dpdk/pmds-22.0/librte_event_skeleton.so.22'
null_resource.dpdk (remote-exec): './librte_event_skeleton.so.22.0' -> 'dpdk/pmds-22.0/librte_event_skeleton.so.22.0'
null_resource.dpdk (remote-exec): './librte_event_sw.so' -> 'dpdk/pmds-22.0/librte_event_sw.so'
null_resource.dpdk (remote-exec): './librte_event_sw.so.22' -> 'dpdk/pmds-22.0/librte_event_sw.so.22'
null_resource.dpdk (remote-exec): './librte_event_sw.so.22.0' -> 'dpdk/pmds-22.0/librte_event_sw.so.22.0'
null_resource.dpdk (remote-exec): './librte_mempool_bucket.so' -> 'dpdk/pmds-22.0/librte_mempool_bucket.so'
null_resource.dpdk (remote-exec): './librte_mempool_bucket.so.22' -> 'dpdk/pmds-22.0/librte_mempool_bucket.so.22'
null_resource.dpdk (remote-exec): './librte_mempool_bucket.so.22.0' -> 'dpdk/pmds-22.0/librte_mempool_bucket.so.22.0'
null_resource.dpdk (remote-exec): './librte_mempool_cnxk.so' -> 'dpdk/pmds-22.0/librte_mempool_cnxk.so'
null_resource.dpdk (remote-exec): './librte_mempool_cnxk.so.22' -> 'dpdk/pmds-22.0/librte_mempool_cnxk.so.22'
null_resource.dpdk (remote-exec): './librte_mempool_cnxk.so.22.0' -> 'dpdk/pmds-22.0/librte_mempool_cnxk.so.22.0'
null_resource.dpdk (remote-exec): './librte_mempool_dpaa2.so' -> 'dpdk/pmds-22.0/librte_mempool_dpaa2.so'
null_resource.dpdk (remote-exec): './librte_mempool_dpaa2.so.22' -> 'dpdk/pmds-22.0/librte_mempool_dpaa2.so.22'
null_resource.dpdk (remote-exec): './librte_mempool_dpaa2.so.22.0' -> 'dpdk/pmds-22.0/librte_mempool_dpaa2.so.22.0'
null_resource.dpdk (remote-exec): './librte_mempool_dpaa.so' -> 'dpdk/pmds-22.0/librte_mempool_dpaa.so'
null_resource.dpdk (remote-exec): './librte_mempool_dpaa.so.22' -> 'dpdk/pmds-22.0/librte_mempool_dpaa.so.22'
null_resource.dpdk (remote-exec): './librte_mempool_dpaa.so.22.0' -> 'dpdk/pmds-22.0/librte_mempool_dpaa.so.22.0'
null_resource.dpdk (remote-exec): './librte_mempool_octeontx2.so' -> 'dpdk/pmds-22.0/librte_mempool_octeontx2.so'
null_resource.dpdk (remote-exec): './librte_mempool_octeontx2.so.22' -> 'dpdk/pmds-22.0/librte_mempool_octeontx2.so.22'
null_resource.dpdk (remote-exec): './librte_mempool_octeontx2.so.22.0' -> 'dpdk/pmds-22.0/librte_mempool_octeontx2.so.22.0'
null_resource.dpdk (remote-exec): './librte_mempool_octeontx.so' -> 'dpdk/pmds-22.0/librte_mempool_octeontx.so'
null_resource.dpdk (remote-exec): './librte_mempool_octeontx.so.22' -> 'dpdk/pmds-22.0/librte_mempool_octeontx.so.22'
null_resource.dpdk (remote-exec): './librte_mempool_octeontx.so.22.0' -> 'dpdk/pmds-22.0/librte_mempool_octeontx.so.22.0'
null_resource.dpdk (remote-exec): './librte_mempool_ring.so' -> 'dpdk/pmds-22.0/librte_mempool_ring.so'
null_resource.dpdk (remote-exec): './librte_mempool_ring.so.22' -> 'dpdk/pmds-22.0/librte_mempool_ring.so.22'
null_resource.dpdk (remote-exec): './librte_mempool_ring.so.22.0' -> 'dpdk/pmds-22.0/librte_mempool_ring.so.22.0'
null_resource.dpdk (remote-exec): './librte_mempool_stack.so' -> 'dpdk/pmds-22.0/librte_mempool_stack.so'
null_resource.dpdk (remote-exec): './librte_mempool_stack.so.22' -> 'dpdk/pmds-22.0/librte_mempool_stack.so.22'
null_resource.dpdk (remote-exec): './librte_mempool_stack.so.22.0' -> 'dpdk/pmds-22.0/librte_mempool_stack.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_af_packet.so' -> 'dpdk/pmds-22.0/librte_net_af_packet.so'
null_resource.dpdk (remote-exec): './librte_net_af_packet.so.22' -> 'dpdk/pmds-22.0/librte_net_af_packet.so.22'
null_resource.dpdk (remote-exec): './librte_net_af_packet.so.22.0' -> 'dpdk/pmds-22.0/librte_net_af_packet.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_af_xdp.so' -> 'dpdk/pmds-22.0/librte_net_af_xdp.so'
null_resource.dpdk (remote-exec): './librte_net_af_xdp.so.22' -> 'dpdk/pmds-22.0/librte_net_af_xdp.so.22'
null_resource.dpdk (remote-exec): './librte_net_af_xdp.so.22.0' -> 'dpdk/pmds-22.0/librte_net_af_xdp.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_ark.so' -> 'dpdk/pmds-22.0/librte_net_ark.so'
null_resource.dpdk (remote-exec): './librte_net_ark.so.22' -> 'dpdk/pmds-22.0/librte_net_ark.so.22'
null_resource.dpdk (remote-exec): './librte_net_ark.so.22.0' -> 'dpdk/pmds-22.0/librte_net_ark.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_atlantic.so' -> 'dpdk/pmds-22.0/librte_net_atlantic.so'
null_resource.dpdk (remote-exec): './librte_net_atlantic.so.22' -> 'dpdk/pmds-22.0/librte_net_atlantic.so.22'
null_resource.dpdk (remote-exec): './librte_net_atlantic.so.22.0' -> 'dpdk/pmds-22.0/librte_net_atlantic.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_avp.so' -> 'dpdk/pmds-22.0/librte_net_avp.so'
null_resource.dpdk (remote-exec): './librte_net_avp.so.22' -> 'dpdk/pmds-22.0/librte_net_avp.so.22'
null_resource.dpdk (remote-exec): './librte_net_avp.so.22.0' -> 'dpdk/pmds-22.0/librte_net_avp.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_axgbe.so' -> 'dpdk/pmds-22.0/librte_net_axgbe.so'
null_resource.dpdk (remote-exec): './librte_net_axgbe.so.22' -> 'dpdk/pmds-22.0/librte_net_axgbe.so.22'
null_resource.dpdk (remote-exec): './librte_net_axgbe.so.22.0' -> 'dpdk/pmds-22.0/librte_net_axgbe.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_bnx2x.so' -> 'dpdk/pmds-22.0/librte_net_bnx2x.so'
null_resource.dpdk (remote-exec): './librte_net_bnx2x.so.22' -> 'dpdk/pmds-22.0/librte_net_bnx2x.so.22'
null_resource.dpdk (remote-exec): './librte_net_bnx2x.so.22.0' -> 'dpdk/pmds-22.0/librte_net_bnx2x.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_bnxt.so' -> 'dpdk/pmds-22.0/librte_net_bnxt.so'
null_resource.dpdk (remote-exec): './librte_net_bnxt.so.22' -> 'dpdk/pmds-22.0/librte_net_bnxt.so.22'
null_resource.dpdk (remote-exec): './librte_net_bnxt.so.22.0' -> 'dpdk/pmds-22.0/librte_net_bnxt.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_bond.so' -> 'dpdk/pmds-22.0/librte_net_bond.so'
null_resource.dpdk (remote-exec): './librte_net_bond.so.22' -> 'dpdk/pmds-22.0/librte_net_bond.so.22'
null_resource.dpdk (remote-exec): './librte_net_bond.so.22.0' -> 'dpdk/pmds-22.0/librte_net_bond.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_cnxk.so' -> 'dpdk/pmds-22.0/librte_net_cnxk.so'
null_resource.dpdk (remote-exec): './librte_net_cnxk.so.22' -> 'dpdk/pmds-22.0/librte_net_cnxk.so.22'
null_resource.dpdk (remote-exec): './librte_net_cnxk.so.22.0' -> 'dpdk/pmds-22.0/librte_net_cnxk.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_cxgbe.so' -> 'dpdk/pmds-22.0/librte_net_cxgbe.so'
null_resource.dpdk (remote-exec): './librte_net_cxgbe.so.22' -> 'dpdk/pmds-22.0/librte_net_cxgbe.so.22'
null_resource.dpdk (remote-exec): './librte_net_cxgbe.so.22.0' -> 'dpdk/pmds-22.0/librte_net_cxgbe.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_dpaa2.so' -> 'dpdk/pmds-22.0/librte_net_dpaa2.so'
null_resource.dpdk (remote-exec): './librte_net_dpaa2.so.22' -> 'dpdk/pmds-22.0/librte_net_dpaa2.so.22'
null_resource.dpdk (remote-exec): './librte_net_dpaa2.so.22.0' -> 'dpdk/pmds-22.0/librte_net_dpaa2.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_dpaa.so' -> 'dpdk/pmds-22.0/librte_net_dpaa.so'
null_resource.dpdk (remote-exec): './librte_net_dpaa.so.22' -> 'dpdk/pmds-22.0/librte_net_dpaa.so.22'
null_resource.dpdk (remote-exec): './librte_net_dpaa.so.22.0' -> 'dpdk/pmds-22.0/librte_net_dpaa.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_e1000.so' -> 'dpdk/pmds-22.0/librte_net_e1000.so'
null_resource.dpdk (remote-exec): './librte_net_e1000.so.22' -> 'dpdk/pmds-22.0/librte_net_e1000.so.22'
null_resource.dpdk (remote-exec): './librte_net_e1000.so.22.0' -> 'dpdk/pmds-22.0/librte_net_e1000.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_ena.so' -> 'dpdk/pmds-22.0/librte_net_ena.so'
null_resource.dpdk (remote-exec): './librte_net_ena.so.22' -> 'dpdk/pmds-22.0/librte_net_ena.so.22'
null_resource.dpdk (remote-exec): './librte_net_ena.so.22.0' -> 'dpdk/pmds-22.0/librte_net_ena.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_enetc.so' -> 'dpdk/pmds-22.0/librte_net_enetc.so'
null_resource.dpdk (remote-exec): './librte_net_enetc.so.22' -> 'dpdk/pmds-22.0/librte_net_enetc.so.22'
null_resource.dpdk (remote-exec): './librte_net_enetc.so.22.0' -> 'dpdk/pmds-22.0/librte_net_enetc.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_enetfec.so' -> 'dpdk/pmds-22.0/librte_net_enetfec.so'
null_resource.dpdk (remote-exec): './librte_net_enetfec.so.22' -> 'dpdk/pmds-22.0/librte_net_enetfec.so.22'
null_resource.dpdk (remote-exec): './librte_net_enetfec.so.22.0' -> 'dpdk/pmds-22.0/librte_net_enetfec.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_enic.so' -> 'dpdk/pmds-22.0/librte_net_enic.so'
null_resource.dpdk (remote-exec): './librte_net_enic.so.22' -> 'dpdk/pmds-22.0/librte_net_enic.so.22'
null_resource.dpdk (remote-exec): './librte_net_enic.so.22.0' -> 'dpdk/pmds-22.0/librte_net_enic.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_failsafe.so' -> 'dpdk/pmds-22.0/librte_net_failsafe.so'
null_resource.dpdk (remote-exec): './librte_net_failsafe.so.22' -> 'dpdk/pmds-22.0/librte_net_failsafe.so.22'
null_resource.dpdk (remote-exec): './librte_net_failsafe.so.22.0' -> 'dpdk/pmds-22.0/librte_net_failsafe.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_fm10k.so' -> 'dpdk/pmds-22.0/librte_net_fm10k.so'
null_resource.dpdk (remote-exec): './librte_net_fm10k.so.22' -> 'dpdk/pmds-22.0/librte_net_fm10k.so.22'
null_resource.dpdk (remote-exec): './librte_net_fm10k.so.22.0' -> 'dpdk/pmds-22.0/librte_net_fm10k.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_hinic.so' -> 'dpdk/pmds-22.0/librte_net_hinic.so'
null_resource.dpdk (remote-exec): './librte_net_hinic.so.22' -> 'dpdk/pmds-22.0/librte_net_hinic.so.22'
null_resource.dpdk (remote-exec): './librte_net_hinic.so.22.0' -> 'dpdk/pmds-22.0/librte_net_hinic.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_hns3.so' -> 'dpdk/pmds-22.0/librte_net_hns3.so'
null_resource.dpdk (remote-exec): './librte_net_hns3.so.22' -> 'dpdk/pmds-22.0/librte_net_hns3.so.22'
null_resource.dpdk (remote-exec): './librte_net_hns3.so.22.0' -> 'dpdk/pmds-22.0/librte_net_hns3.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_i40e.so' -> 'dpdk/pmds-22.0/librte_net_i40e.so'
null_resource.dpdk (remote-exec): './librte_net_i40e.so.22' -> 'dpdk/pmds-22.0/librte_net_i40e.so.22'
null_resource.dpdk (remote-exec): './librte_net_i40e.so.22.0' -> 'dpdk/pmds-22.0/librte_net_i40e.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_iavf.so' -> 'dpdk/pmds-22.0/librte_net_iavf.so'
null_resource.dpdk (remote-exec): './librte_net_iavf.so.22' -> 'dpdk/pmds-22.0/librte_net_iavf.so.22'
null_resource.dpdk (remote-exec): './librte_net_iavf.so.22.0' -> 'dpdk/pmds-22.0/librte_net_iavf.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_ice.so' -> 'dpdk/pmds-22.0/librte_net_ice.so'
null_resource.dpdk (remote-exec): './librte_net_ice.so.22' -> 'dpdk/pmds-22.0/librte_net_ice.so.22'
null_resource.dpdk (remote-exec): './librte_net_ice.so.22.0' -> 'dpdk/pmds-22.0/librte_net_ice.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_igc.so' -> 'dpdk/pmds-22.0/librte_net_igc.so'
null_resource.dpdk (remote-exec): './librte_net_igc.so.22' -> 'dpdk/pmds-22.0/librte_net_igc.so.22'
null_resource.dpdk (remote-exec): './librte_net_igc.so.22.0' -> 'dpdk/pmds-22.0/librte_net_igc.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_ionic.so' -> 'dpdk/pmds-22.0/librte_net_ionic.so'
null_resource.dpdk (remote-exec): './librte_net_ionic.so.22' -> 'dpdk/pmds-22.0/librte_net_ionic.so.22'
null_resource.dpdk (remote-exec): './librte_net_ionic.so.22.0' -> 'dpdk/pmds-22.0/librte_net_ionic.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_ixgbe.so' -> 'dpdk/pmds-22.0/librte_net_ixgbe.so'
null_resource.dpdk (remote-exec): './librte_net_ixgbe.so.22' -> 'dpdk/pmds-22.0/librte_net_ixgbe.so.22'
null_resource.dpdk (remote-exec): './librte_net_ixgbe.so.22.0' -> 'dpdk/pmds-22.0/librte_net_ixgbe.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_kni.so' -> 'dpdk/pmds-22.0/librte_net_kni.so'
null_resource.dpdk (remote-exec): './librte_net_kni.so.22' -> 'dpdk/pmds-22.0/librte_net_kni.so.22'
null_resource.dpdk (remote-exec): './librte_net_kni.so.22.0' -> 'dpdk/pmds-22.0/librte_net_kni.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_liquidio.so' -> 'dpdk/pmds-22.0/librte_net_liquidio.so'
null_resource.dpdk (remote-exec): './librte_net_liquidio.so.22' -> 'dpdk/pmds-22.0/librte_net_liquidio.so.22'
null_resource.dpdk (remote-exec): './librte_net_liquidio.so.22.0' -> 'dpdk/pmds-22.0/librte_net_liquidio.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_memif.so' -> 'dpdk/pmds-22.0/librte_net_memif.so'
null_resource.dpdk (remote-exec): './librte_net_memif.so.22' -> 'dpdk/pmds-22.0/librte_net_memif.so.22'
null_resource.dpdk (remote-exec): './librte_net_memif.so.22.0' -> 'dpdk/pmds-22.0/librte_net_memif.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_mlx4.so' -> 'dpdk/pmds-22.0/librte_net_mlx4.so'
null_resource.dpdk (remote-exec): './librte_net_mlx4.so.22' -> 'dpdk/pmds-22.0/librte_net_mlx4.so.22'
null_resource.dpdk (remote-exec): './librte_net_mlx4.so.22.0' -> 'dpdk/pmds-22.0/librte_net_mlx4.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_mlx5.so' -> 'dpdk/pmds-22.0/librte_net_mlx5.so'
null_resource.dpdk (remote-exec): './librte_net_mlx5.so.22' -> 'dpdk/pmds-22.0/librte_net_mlx5.so.22'
null_resource.dpdk (remote-exec): './librte_net_mlx5.so.22.0' -> 'dpdk/pmds-22.0/librte_net_mlx5.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_netvsc.so' -> 'dpdk/pmds-22.0/librte_net_netvsc.so'
null_resource.dpdk (remote-exec): './librte_net_netvsc.so.22' -> 'dpdk/pmds-22.0/librte_net_netvsc.so.22'
null_resource.dpdk (remote-exec): './librte_net_netvsc.so.22.0' -> 'dpdk/pmds-22.0/librte_net_netvsc.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_nfp.so' -> 'dpdk/pmds-22.0/librte_net_nfp.so'
null_resource.dpdk (remote-exec): './librte_net_nfp.so.22' -> 'dpdk/pmds-22.0/librte_net_nfp.so.22'
null_resource.dpdk (remote-exec): './librte_net_nfp.so.22.0' -> 'dpdk/pmds-22.0/librte_net_nfp.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_ngbe.so' -> 'dpdk/pmds-22.0/librte_net_ngbe.so'
null_resource.dpdk (remote-exec): './librte_net_ngbe.so.22' -> 'dpdk/pmds-22.0/librte_net_ngbe.so.22'
null_resource.dpdk (remote-exec): './librte_net_ngbe.so.22.0' -> 'dpdk/pmds-22.0/librte_net_ngbe.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_null.so' -> 'dpdk/pmds-22.0/librte_net_null.so'
null_resource.dpdk (remote-exec): './librte_net_null.so.22' -> 'dpdk/pmds-22.0/librte_net_null.so.22'
null_resource.dpdk (remote-exec): './librte_net_null.so.22.0' -> 'dpdk/pmds-22.0/librte_net_null.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_octeontx2.so' -> 'dpdk/pmds-22.0/librte_net_octeontx2.so'
null_resource.dpdk (remote-exec): './librte_net_octeontx2.so.22' -> 'dpdk/pmds-22.0/librte_net_octeontx2.so.22'
null_resource.dpdk (remote-exec): './librte_net_octeontx2.so.22.0' -> 'dpdk/pmds-22.0/librte_net_octeontx2.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_octeontx_ep.so' -> 'dpdk/pmds-22.0/librte_net_octeontx_ep.so'
null_resource.dpdk (remote-exec): './librte_net_octeontx_ep.so.22' -> 'dpdk/pmds-22.0/librte_net_octeontx_ep.so.22'
null_resource.dpdk (remote-exec): './librte_net_octeontx_ep.so.22.0' -> 'dpdk/pmds-22.0/librte_net_octeontx_ep.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_octeontx.so' -> 'dpdk/pmds-22.0/librte_net_octeontx.so'
null_resource.dpdk (remote-exec): './librte_net_octeontx.so.22' -> 'dpdk/pmds-22.0/librte_net_octeontx.so.22'
null_resource.dpdk (remote-exec): './librte_net_octeontx.so.22.0' -> 'dpdk/pmds-22.0/librte_net_octeontx.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_pcap.so' -> 'dpdk/pmds-22.0/librte_net_pcap.so'
null_resource.dpdk (remote-exec): './librte_net_pcap.so.22' -> 'dpdk/pmds-22.0/librte_net_pcap.so.22'
null_resource.dpdk (remote-exec): './librte_net_pcap.so.22.0' -> 'dpdk/pmds-22.0/librte_net_pcap.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_pfe.so' -> 'dpdk/pmds-22.0/librte_net_pfe.so'
null_resource.dpdk (remote-exec): './librte_net_pfe.so.22' -> 'dpdk/pmds-22.0/librte_net_pfe.so.22'
null_resource.dpdk (remote-exec): './librte_net_pfe.so.22.0' -> 'dpdk/pmds-22.0/librte_net_pfe.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_qede.so' -> 'dpdk/pmds-22.0/librte_net_qede.so'
null_resource.dpdk (remote-exec): './librte_net_qede.so.22' -> 'dpdk/pmds-22.0/librte_net_qede.so.22'
null_resource.dpdk (remote-exec): './librte_net_qede.so.22.0' -> 'dpdk/pmds-22.0/librte_net_qede.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_ring.so' -> 'dpdk/pmds-22.0/librte_net_ring.so'
null_resource.dpdk (remote-exec): './librte_net_ring.so.22' -> 'dpdk/pmds-22.0/librte_net_ring.so.22'
null_resource.dpdk (remote-exec): './librte_net_ring.so.22.0' -> 'dpdk/pmds-22.0/librte_net_ring.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_sfc.so' -> 'dpdk/pmds-22.0/librte_net_sfc.so'
null_resource.dpdk (remote-exec): './librte_net_sfc.so.22' -> 'dpdk/pmds-22.0/librte_net_sfc.so.22'
null_resource.dpdk (remote-exec): './librte_net_sfc.so.22.0' -> 'dpdk/pmds-22.0/librte_net_sfc.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_softnic.so' -> 'dpdk/pmds-22.0/librte_net_softnic.so'
null_resource.dpdk (remote-exec): './librte_net_softnic.so.22' -> 'dpdk/pmds-22.0/librte_net_softnic.so.22'
null_resource.dpdk (remote-exec): './librte_net_softnic.so.22.0' -> 'dpdk/pmds-22.0/librte_net_softnic.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_tap.so' -> 'dpdk/pmds-22.0/librte_net_tap.so'
null_resource.dpdk (remote-exec): './librte_net_tap.so.22' -> 'dpdk/pmds-22.0/librte_net_tap.so.22'
null_resource.dpdk (remote-exec): './librte_net_tap.so.22.0' -> 'dpdk/pmds-22.0/librte_net_tap.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_thunderx.so' -> 'dpdk/pmds-22.0/librte_net_thunderx.so'
null_resource.dpdk (remote-exec): './librte_net_thunderx.so.22' -> 'dpdk/pmds-22.0/librte_net_thunderx.so.22'
null_resource.dpdk (remote-exec): './librte_net_thunderx.so.22.0' -> 'dpdk/pmds-22.0/librte_net_thunderx.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_txgbe.so' -> 'dpdk/pmds-22.0/librte_net_txgbe.so'
null_resource.dpdk (remote-exec): './librte_net_txgbe.so.22' -> 'dpdk/pmds-22.0/librte_net_txgbe.so.22'
null_resource.dpdk (remote-exec): './librte_net_txgbe.so.22.0' -> 'dpdk/pmds-22.0/librte_net_txgbe.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_vdev_netvsc.so' -> 'dpdk/pmds-22.0/librte_net_vdev_netvsc.so'
null_resource.dpdk (remote-exec): './librte_net_vdev_netvsc.so.22' -> 'dpdk/pmds-22.0/librte_net_vdev_netvsc.so.22'
null_resource.dpdk (remote-exec): './librte_net_vdev_netvsc.so.22.0' -> 'dpdk/pmds-22.0/librte_net_vdev_netvsc.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_vhost.so' -> 'dpdk/pmds-22.0/librte_net_vhost.so'
null_resource.dpdk (remote-exec): './librte_net_vhost.so.22' -> 'dpdk/pmds-22.0/librte_net_vhost.so.22'
null_resource.dpdk (remote-exec): './librte_net_vhost.so.22.0' -> 'dpdk/pmds-22.0/librte_net_vhost.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_virtio.so' -> 'dpdk/pmds-22.0/librte_net_virtio.so'
null_resource.dpdk (remote-exec): './librte_net_virtio.so.22' -> 'dpdk/pmds-22.0/librte_net_virtio.so.22'
null_resource.dpdk (remote-exec): './librte_net_virtio.so.22.0' -> 'dpdk/pmds-22.0/librte_net_virtio.so.22.0'
null_resource.dpdk (remote-exec): './librte_net_vmxnet3.so' -> 'dpdk/pmds-22.0/librte_net_vmxnet3.so'
null_resource.dpdk (remote-exec): './librte_net_vmxnet3.so.22' -> 'dpdk/pmds-22.0/librte_net_vmxnet3.so.22'
null_resource.dpdk (remote-exec): './librte_net_vmxnet3.so.22.0' -> 'dpdk/pmds-22.0/librte_net_vmxnet3.so.22.0'
null_resource.dpdk (remote-exec): './librte_raw_cnxk_bphy.so' -> 'dpdk/pmds-22.0/librte_raw_cnxk_bphy.so'
null_resource.dpdk (remote-exec): './librte_raw_cnxk_bphy.so.22' -> 'dpdk/pmds-22.0/librte_raw_cnxk_bphy.so.22'
null_resource.dpdk (remote-exec): './librte_raw_cnxk_bphy.so.22.0' -> 'dpdk/pmds-22.0/librte_raw_cnxk_bphy.so.22.0'
null_resource.dpdk (remote-exec): './librte_raw_dpaa2_cmdif.so' -> 'dpdk/pmds-22.0/librte_raw_dpaa2_cmdif.so'
null_resource.dpdk (remote-exec): './librte_raw_dpaa2_cmdif.so.22' -> 'dpdk/pmds-22.0/librte_raw_dpaa2_cmdif.so.22'
null_resource.dpdk (remote-exec): './librte_raw_dpaa2_cmdif.so.22.0' -> 'dpdk/pmds-22.0/librte_raw_dpaa2_cmdif.so.22.0'
null_resource.dpdk (remote-exec): './librte_raw_dpaa2_qdma.so' -> 'dpdk/pmds-22.0/librte_raw_dpaa2_qdma.so'
null_resource.dpdk (remote-exec): './librte_raw_dpaa2_qdma.so.22' -> 'dpdk/pmds-22.0/librte_raw_dpaa2_qdma.so.22'
null_resource.dpdk (remote-exec): './librte_raw_dpaa2_qdma.so.22.0' -> 'dpdk/pmds-22.0/librte_raw_dpaa2_qdma.so.22.0'
null_resource.dpdk (remote-exec): './librte_raw_ntb.so' -> 'dpdk/pmds-22.0/librte_raw_ntb.so'
null_resource.dpdk (remote-exec): './librte_raw_ntb.so.22' -> 'dpdk/pmds-22.0/librte_raw_ntb.so.22'
null_resource.dpdk (remote-exec): './librte_raw_ntb.so.22.0' -> 'dpdk/pmds-22.0/librte_raw_ntb.so.22.0'
null_resource.dpdk (remote-exec): './librte_raw_skeleton.so' -> 'dpdk/pmds-22.0/librte_raw_skeleton.so'
null_resource.dpdk (remote-exec): './librte_raw_skeleton.so.22' -> 'dpdk/pmds-22.0/librte_raw_skeleton.so.22'
null_resource.dpdk (remote-exec): './librte_raw_skeleton.so.22.0' -> 'dpdk/pmds-22.0/librte_raw_skeleton.so.22.0'
null_resource.dpdk (remote-exec): './librte_regex_mlx5.so' -> 'dpdk/pmds-22.0/librte_regex_mlx5.so'
null_resource.dpdk (remote-exec): './librte_regex_mlx5.so.22' -> 'dpdk/pmds-22.0/librte_regex_mlx5.so.22'
null_resource.dpdk (remote-exec): './librte_regex_mlx5.so.22.0' -> 'dpdk/pmds-22.0/librte_regex_mlx5.so.22.0'
null_resource.dpdk (remote-exec): './librte_regex_octeontx2.so' -> 'dpdk/pmds-22.0/librte_regex_octeontx2.so'
null_resource.dpdk (remote-exec): './librte_regex_octeontx2.so.22' -> 'dpdk/pmds-22.0/librte_regex_octeontx2.so.22'
null_resource.dpdk (remote-exec): './librte_regex_octeontx2.so.22.0' -> 'dpdk/pmds-22.0/librte_regex_octeontx2.so.22.0'
null_resource.dpdk (remote-exec): './librte_vdpa_ifc.so' -> 'dpdk/pmds-22.0/librte_vdpa_ifc.so'
null_resource.dpdk (remote-exec): './librte_vdpa_ifc.so.22' -> 'dpdk/pmds-22.0/librte_vdpa_ifc.so.22'
null_resource.dpdk (remote-exec): './librte_vdpa_ifc.so.22.0' -> 'dpdk/pmds-22.0/librte_vdpa_ifc.so.22.0'
null_resource.dpdk (remote-exec): './librte_vdpa_mlx5.so' -> 'dpdk/pmds-22.0/librte_vdpa_mlx5.so'
null_resource.dpdk (remote-exec): './librte_vdpa_mlx5.so.22' -> 'dpdk/pmds-22.0/librte_vdpa_mlx5.so.22'
null_resource.dpdk (remote-exec): './librte_vdpa_mlx5.so.22.0' -> 'dpdk/pmds-22.0/librte_vdpa_mlx5.so.22.0'
null_resource.dpdk (remote-exec): './librte_vdpa_sfc.so' -> 'dpdk/pmds-22.0/librte_vdpa_sfc.so'
null_resource.dpdk (remote-exec): './librte_vdpa_sfc.so.22' -> 'dpdk/pmds-22.0/librte_vdpa_sfc.so.22'
null_resource.dpdk (remote-exec): './librte_vdpa_sfc.so.22.0' -> 'dpdk/pmds-22.0/librte_vdpa_sfc.so.22.0'
null_resource.dpdk: Creation complete after 8m28s [id=2421476301113403266]

Apply complete! Resources: 6 added, 0 changed, 0 destroyed.

Outputs:
```
