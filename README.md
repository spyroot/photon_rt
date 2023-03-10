# This is VMware VM and Bare-metal, Real time Photon build system.

The automated system is designed to work with a bare-metal host. (Dell) or with 
VMware VC environment.

Note to have a consistent build. A builder build system generates ISO 
is used in both VM and Bare metal.    

In the case of a VM, the ISO is used to boot the VM and install OS from kick-start. i.e., it 
is an unattended installation.  Thus, In both cases, the automated build system, 
first build a reference iso file.  

For example local directory contains ph4-rt-refresh.iso or system fetch the reference ISO from the web. 

## What it builds  ?

An automated system for VMware Real time Photon OS version 4 and 5 and 
consists build multiply phases. Make sure you familiar with Photon OS itself.
[Photon OS](https://github.com/vmware/photon)

It leverages build in Photon OS capability to install OS from 
kickstart spec and its unattended installation. i.e. it implies you correctly 
re-adjusted boot source in BIOS before you install OS.

In phase one system generates a reference kick-start ISO. During this phase
the first step is to decide whether to build an online or offline version.
The reference ISO copy to dedicate directory that exposed via HTTP. By default, 
it **DEFAULT_WEB_DIR** in **shared.bash**.   in cluster.env you need to define  
**IDRAC_REMOTE_HTTP**. By default, I use the same host as the bootstrap host. i.e., 
I assume that the host that generates ISO also exposes HTTP port 80.   
You can use docker env. The entry point in the source tree 
is a script that starts Nginx.

Note that the third step **build_in_parallel_boot.sh**, is optional. 
After you run build_iso.sh execute ISO generate in the current directory

### Online version

The online version is the flavor of when post-kick-start phase. i.e., 
after the first reboot post-installation. All post-install components polled from the internet. 
It first polls all toolchains required to compile dependencies, polls all drivers,  
git repos, DPDK, IPSEC lib, lib-nl, lib-isa, and many other libs from the internet. 
During this phase, all RPMs, and pip packages are installed from the internet.

### Offline version

In the offline version, all components are serialized to ISO and, after first boot,  
moved to root / partition.

What serialized to offline dictated by configuration JSON files.
In the offline settings, it consists of three directories by default.  
All are defined in shared.bash

```bash
DEFAULT_RPM_DIR="direct_rpms"
# all cloned and tar. gzed repositories in git_repos
DEFAULT_GIT_DIR="git_images"
# all downloaded tar.gz ( drivers and other arcs) will be in direct.
DEFAULT_ARC_DIR="direct"
```

[Specs]](https://github.com/spyroot/photon_rt/tree/main/offline)

All specs JSON files. For example for DPDK we need meson, nasm and ninja build system

additional_direct_rpms.json
```json
[
  "ninja-build-1.10.2-2.ph4.x86_64",
  "meson-0.64.1-1.ph4.noarch",
  "nasm-2.15.05-1.ph4.x86_64"
]
```

'''
additional_git_clone.json

```json
[
  "https://github.com/intel/isa-l",
  "https://github.com/spyroot/tuned.git",
  "https://github.com/intel/intel-ipsec-mb.git"
]
```

```json
[
  "docker"
]
```


Additional files pushed during install.
```json
{
  "additional_files": [
    {
      "/mnt/media/my_docker.tar.gz": "/my_docker.tar.gz"
    },
    {
      "/mnt/media/post.sh": "/post.sh"
    }
  ]
}
```
additional_load_docker.json

```json
[
  "wget -nc http://MY_HTTP_SERVER/MY.rpm -P /tmp/  >> /etc/postinstall"
]
```

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
  * **build_praller_boot.sh** (Optional bare-metal only) leverages **idract_ctl** and boots 
  N hosts from final customized ISO via remote HTTP media and installs the real-time OS.

**build_and_exec.sh** first builds a workspace container and lands to a bash 
session inside a container.   That removes any requirement for a tools 
chain pre-install, and you can run it on Mac/Linux/Win.  So the first step is to build 
or pull the image from the docker hub,  generate kick-start files, 
and build a new ISO used for the unattended installation.


Note **build_and_exec.sh** uses following json files to produce final kickstart.
* additional_direct_rpms.json  any rpms that we want to pull to the image. 
* additional_files.json a files that we need inject into the ISO.
* additional_load_docker.json a files that we injected can be loaded on first boot.
* additional_packages.json  additional packages we need install.

All mentioned files contain a JSON list.

In the case of the VMware VC environment, **main.tf** is the main terraform file that uses 
generated ISO to install VM or VMs. Note in the case of terraform, there are a number of
post-installation pipelines that customize a VM.

In both cases, customization for post-install, the first boot includes polling the 
latest Intel drivers, fixing kernel boot parameters, and optimizing VM/Host for the real-time workload.

## Requirements.

Requirements.

- Make sure you have a network segment in VC that provide DHCP services.
- If you are using Linux and don't want to use the docker image I provide. 
- Make sure you run on a system with python 3.10.   idrac_ctl requires python 3.10
- If you do bare-metal online you also need make sure post kick-start host will get IP address.
- Make sure the same segment has an internet connection.
- Make sure that DHCP allocates the DNS server.
- The port-group name must match whatever you see in VC.

## Step One: Build ISO.

```bash
# instal vault and store credentials.
./install_vault_linux.sh

# builds container or pull container from dockerhub and land to bash
./build_and_exec.sh

# builds iso 
./build_iso.sh
```

For example 

Spec to build Photon 4 Real-Time kernel with VMware Test NF.

```bash
#!/bin/bash
BUILD_TYPE="offline_testnf_os4_flex21" ./build_and_exec.sh
BUILD_TYPE="offline_testnf_os4_flex21" ./build_iso.sh
BUILD_TYPE="offline_testnf_os4_flex21" ./build_paraller_boot.sh
```

## Overwrite post boot.

During first boot post.sh perform  number of optimization and customization.  **overwrite.env** 
provides option to turn on or off specific customization.

Example **overwrite.env** that will overwrite PCI list for SRIOV.
If you want switch everything off please check **overwrite.example_disable_post**

```bash
#!/bin/bash

# overwrite do we need build DPDK or not.  note if we build DPDK
# we probably want to build  
# libnl  https://www.infradead.org/~tgr/libnl/
# intel ipsec lib https://github.com/intel/intel-ipsec-mb
#OVERWRITE_DPDK_BUILD="yes"
# overwrites setting do we want build i.e. enable SRIOV 
# or not.   OVERWRITE_SRIOV_PCI is list of PCI 
# address that builder will use as target set 
#OVERWRITE_BUILD_SRIOV="yes"
# overwrite do we build ipsec or not
#OVERWRITE_IPSEC_BUILD="yes"
# overwrite do we build intel driver or not
#OVERWRITE_INTEL_BUILD="yes"
# overwrite do we build hugepages or not
#OVERWRITE_BUILD_HUGEPAGES="yes"
# overwrite do we build tuned with profile or not
#OVERWRITE_BUILD_TUNED="yes"
# overwrite ptp do we build or not
#OVERWRITE_BUILD_PTP="yes"
# overwrite do we build trunk or not
#OVERWRITE_BUILD_TRUNK="yes"
# overwrite default pci
#OVERWRITE_SRIOV_PCI="pci@0000:51:00.0,pci@0000:51:00.1"
# overwrite default max vf
#OVERWRITE_MAX_VFS_PER_PCI=16
# overwrite default max vf
#OVERWRITE_DOT1Q_VLAN_ID_LIST="2000,2001"
# overwrite default max vf
#OVERWRITE_DOT1Q_VLAN_TRUNK_PCI="pci@0000:18:00.1"

# overwrites adapter allocate for static IP
# OVERWRITE_STATIC_ETHn_NAME="eth0"
# OVERWRITE_STATIC_ETHn_ADDRESS="192.168.1.1/24"
# OVERWRITE_STATIC_ETHn_GATEWAY="192.168.254.254"
# OVERWRITE_STATIC_ETHn_STATIC_DNS="8.8.8.8"
```

## Main configuration file.

The main configuration file is **shared.bash**.  It is the only file you should edit. 
Its main configuration indicates what we need to build. Specs folder **MUST** 
container a structure I posted as an example.

DEFAULT_BUILD_TYPE tells the builder what directory it must use.  
The same directory must container all JSON spec folders.

```bash
DEFAULT_BUILD_TYPE="offline_testnf_os4_flex21"
```

## Usage



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

Build ISO generate target ISO.

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

Notice script used ks.ref.cfg to generate new ks.cfg, and it pushed to ISO.cfg The script, 
by default, uses **$HOME/.ssh/ssh-rsa** and injects it to the target iso.

```json

```

A container creates a volume that map to a workspace.  i.e., the same execution where Dockerfile is.   
Exit from the container bash session back.  Notice build_iso.sh generated a new iso file.  
Note don't run build_iso.sh directly.

## Creating VM.

A build system uses terraform to create a VM and boot VM from unattended generated ISO image.
Note that main.tf reference a vault hence you need create respected kv value.

```bash
./install_vault_linux.sh
```

The script will install the vault. Note a default token in **token.txt** file. 
Also, notice that the default password is set to DEFAULT,  if you need to adjust  respected kv

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

If everything is right, we can deploy.  

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


## DPDK libs

* The build process builds and installs all shared libs in /usr/local/lib
* The docker image build process builds all example apps test-pmd etc.
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

Regular setup requires huge page 

```
sudo docker run --privileged --name photon_bash --rm -i -t photon_dpdk20.11:v1 dpdk-testpmd
```

Test run

```
sudo docker run --privileged --name photon_bash --rm -i -t photon_dpdk20.11:v1 dpdk-testpmd --no-huge
```

# Tensorflow

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
