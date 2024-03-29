#!/bin/bash
# This is post install script.  This script executed
# after first post install.
# Post install builder support two mode interactive and none interactive mode (default)
# IS_INTERACTIVE design for case if we run manually by hand.
#
#
# The goal here
# - build mellanox driver and Intel driver.
# - link to current kernel src.
# - build all DPDK kmod and install. (including UIO)
# - build all libs required for DPDK Crypto.
# - build IPSec libs required for vdev DPDK.
# - build CUDA (optional)
# - install all as shared libs.
# - make sure vfio latest.
# - enable vfio and vfio-pci.
# - enable SRIOV on target network adapter.(must be UP)
# - enable huge pages for single socket or dual socket.
# - enable PTP
# - set VF to trusted mode and disable spoof check.
# - automatically generate tuned profile , load.
#
# Each build value can be overwritten from overwrite.env file.
# The main point we need overwrite:
#   - Docker image we need load.
#   - Set correct PCI address for SRIOV.
#   - Set correct VLAN ranges and PCI address for trunk adapter.
#
# Example disable all
#
# OVERWRITE_DPDK_BUILD="no"
# OVERWRITE_BUILD_SRIOV="no"
# OVERWRITE_IPSEC_BUILD="no"
# OVERWRITE_INTEL_BUILD="no"
# OVERWRITE_BUILD_TUNED="no"
# OVERWRITE_BUILD_PTP="no"
# OVERWRITE_BUILD_TRUNK="no"
# OVERWRITE_BUILD_LIBNL="no"
# OVERWRITE_BUILD_ISA="no"
# OVERWRITE_BUILD_DEFAULT_NETWORK="no"
# OVERWRITE_BUILD_INSTALL_PACKAGES="no"
# OVERWRITE_BUILD_RE_LINK_KERNEL="no"

# OVERWRITE_LOAD_VFIO="no"
# OVERWRITE_LOAD_DOCKER_IMAGE="no"
# OVERWRITE_BUILD_HUGEPAGES="no"
#
# spyroot@gmail.com
# Author Mustafa Bayramov

# all overwrite loaded from overwrite
source /overwrite.env
export LANG=en_US.UTF-8
export LC_ALL=$LANG
export PATH="$PATH":/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin
GREEN_CUSTOM='\033[0;32m'
NC_CUSTOM='\033[0m'

# version we are using for IAVF and Mellanox
AVX_VERSION=4.5.3
if [ -z "$OVERWRITE_AVX_VERSION" ]; then
  echo "Using default AVX_VERSION value:$AVX_VERSION."
else
  AVX_VERSION=$OVERWRITE_AVX_VERSION
fi

MLNX_VER=5.4-1.0.3.0
if [ -z "$OVERWRITE_MLNX_VER" ]; then
  echo "Using default MLNX_VER value:$MLNX_VER."
else
  MLNX_VER=$OVERWRITE_MLNX_VER
fi

DPDK_VERSION="dpdk-21.11"
# overwrite default value,  /overwrite always take precedence.
if [ -z "$OVERWRITE_DPDK_VERSION" ]; then
  echo "Using default DPDK_VERSION value:$DPDK_VERSION."
else
  DPDK_VERSION=$OVERWRITE_DPDK_VERSION
fi

# if defined we will not install.
if [ -z "$OVERWRITE_INSTALL_RPMS" ]; then
  rpm -i /mnt/cdrom/direct_rpms/*
else
  echo "Skipping installing rpms"
fi

DEFAULT_DOCKER_IMAGE_NAME=""
if [ -z "$DOCKER_IMAGE" ]; then
  echo "DOCKER_IMAGE is empty using $DEFAULT_DOCKER_IMAGE_NAME."
  DOCKER_IMAGE=$DEFAULT_DOCKER_IMAGE_NAME
fi

# default image loaded.
DEFAULT_DOKCER_IMAGE_DIR=""
DOCKER_IMAGE_PATH="$DEFAULT_DOKCER_IMAGE_DIR/$DOCKER_IMAGE.tar.gz"
DOCKER_IMAGE_NAME="vcu1"

# by default all build in /root/build.
ROOT_BUILD="/root/build"
# logs are in /build
BUILD_LOG="/build"

# all require tools
REQUIRED_TOOLS=("wget" "tar" "lshw" "awk")
# dirs that we expect to hold tar.gz
EXPECTED_DIRS=("/direct" "/mnt/cdrom/direct" "/")
# list of required pip packages.
PIP_PKG_REQUIRED=("pyelftools" "sphinx" "procfs")

# What we are building, all flags on by default.
# i.e. by default we build all.
DO_REBOOT="no"
IS_INTERACTIVE="no"
MLX_BUILD="yes"
INTEL_BUILD="yes"
DPDK_BUILD="yes"
IPSEC_BUILD="yes"
BUILD_YASM="yes"
LIBNL_BUILD="yes"
LIBNL_ISA="yes"
BUILD_TUNED="yes"
BUILD_SRIOV="yes"
BUILD_HUGEPAGES="yes"
BUILD_PTP="yes"
BUILD_TRUNK="yes"
BUILD_DEFAULT_NETWORK="yes"
BUILD_STATIC_ADDRESS="no"
BUILD_TRUNK="yes"
WITH_QAT="yes"
LOAD_VFIO="yes"
DO_FULL_CLEANUP="yes"
BUILD_LOAD_DOCKER_IMAGE="yes"
BUILD_RE_LINK_KERNEL="yes"
BUILD_INSTALL_PACKAGES="yes"

# this file script expect in offline mode
DEFAULT_IPSEC_TAR_NAME="intel-ipsec-mb.tar.gz"
DEFAULT_PYELF_TAR_NAME="pyelftools.tar.gz"
DEFAULT_ISA_TAR_NAME="isa-l.tar.gz"
DEFAULT_TUNED_TAR="tuned.tar.gz"
DEFAULT_YASM_TAR="yasm.tar.gz"

# caller can pass INTERACTIVE
if [ -z "$INTERACTIVE" ]; then
  IS_INTERACTIVE="no"
else
  IS_INTERACTIVE="yes"
fi

# overwrite default value,  /overwrite always take precedence.
if [ -z "$OVERWRITE_BUILD_INSTALL_PACKAGES" ]; then
  echo "Using default BUILD_INSTALL_PACKAGES value:$BUILD_INSTALL_PACKAGES."
else
  BUILD_INSTALL_PACKAGES=$OVERWRITE_BUILD_INSTALL_PACKAGES
fi

# overwrite default value,  /overwrite always take precedence.
if [ -z "$OVERWRITE_BUILD_RE_LINK_KERNEL" ]; then
  echo "Using default BUILD_RE_LINK_KERNEL value:$BUILD_RE_LINK_KERNEL."
else
  BUILD_RE_LINK_KERNEL=$OVERWRITE_BUILD_RE_LINK_KERNEL
fi

# overwrite default value,  /overwrite always take precedence.
if [ -z "$OVERWRITE_BUILD_DEFAULT_NETWORK" ]; then
  echo "Using default OVERWRITE_BUILD_DEFAULT_NETWORK value:$BUILD_DEFAULT_NETWORK."
else
  BUILD_DEFAULT_NETWORK=$OVERWRITE_BUILD_DEFAULT_NETWORK
fi

# overwrite for DPDK
if [ -z "$OVERWRITE_DPDK_BUILD" ]; then
  echo "Using default DPDK_BUILD value:$DPDK_BUILD."
else
  DPDK_BUILD=$OVERWRITE_DPDK_BUILD
fi

# overwrite for tuned
if [ -z "$OVERWRITE_BUILD_TUNED" ]; then
  echo "Using default BUILD_TUNED value:$BUILD_TUNED."
else
  BUILD_TUNED=$OVERWRITE_BUILD_TUNED
fi

# overwrite for sriov
if [ -z "$OVERWRITE_BUILD_SRIOV" ]; then
  echo "Using default BUILD_SRIOV:$BUILD_SRIOV."
else
  BUILD_SRIOV=$OVERWRITE_BUILD_SRIOV
fi

# overwrite for intel driver
if [ -z "$OVERWRITE_INTEL_BUILD" ]; then
  echo "Using default BUILD_SRIOV value:$INTEL_BUILD."
else
  INTEL_BUILD=$OVERWRITE_INTEL_BUILD
fi

# overwrite for intel mellanox
if [ -z "$OVERWRITE_MLX_BUILD" ]; then
  echo "Using default MLX_BUILD value:$MLX_BUILD."
else
  MLX_BUILD=$OVERWRITE_MLX_BUILD
fi

# overwrite for libnl
if [ -z "$OVERWRITE_BUILD_LIBNL" ]; then
  echo "Using default LIBNL_BUILD value:$LIBNL_BUILD."
else
  LIBNL_BUILD=$OVERWRITE_BUILD_LIBNL
fi

# overwrite for libnl
if [ -z "$OVERWRITE_BUILD_ISA" ]; then
  echo "Using default OVERWRITE_BUILD_ISA value: $LIBNL_ISA."
else
  LIBNL_ISA=$OVERWRITE_BUILD_ISA
fi

# overwrite for libnl
if [ -z "$OVERWRITE_LOAD_VFIO" ]; then
  echo "Using default LOAD_VFIO value $LOAD_VFIO."
else
  LOAD_VFIO=$OVERWRITE_LOAD_VFIO
fi

# overwrite for libnl
if [ -z "$OVERWRITE_LOAD_DOCKER_IMAGE" ]; then
  echo "Using default BUILD_LOAD_DOCKER_IMAGE value $BUILD_LOAD_DOCKER_IMAGE."
else
  BUILD_LOAD_DOCKER_IMAGE=$OVERWRITE_LOAD_DOCKER_IMAGE
fi

# overwrite for ipsec lib
if [ -z "$OVERWRITE_IPSEC_BUILD" ]; then
  echo "Using default OVERWRITE_IPSEC_BUILD value $IPSEC_BUILD."
else
  IPSEC_BUILD=$OVERWRITE_IPSEC_BUILD
fi
# overwrite for hugepages
if [ -z "$OVERWRITE_BUILD_HUGEPAGES" ]; then
  echo "Using default BUILD_HUGEPAGES value $BUILD_HUGEPAGES."
else
  BUILD_HUGEPAGES=$OVERWRITE_BUILD_HUGEPAGES
fi

# overwrite for ptp
if [ -z "$OVERWRITE_BUILD_PTP" ]; then
  echo "Using default BUILD_SRIOV value $BUILD_PTP."
else
  BUILD_PTP=$OVERWRITE_BUILD_PTP
fi

# build trunk overwrite
if [ -z "$OVERWRITE_BUILD_TRUNK" ]; then
  echo "Using default BUILD_SRIOV value $OVERWRITE_BUILD_TRUNK."
else
  BUILD_TRUNK=$OVERWRITE_BUILD_TRUNK
fi
# location where we get all tar.gz from cloned repos.
DEFAULT_GIT_IMAGE_DIR="/git_images"
DEFAULT_DIRECT="/direct"
DEFAULT_DIRECT_RPMS="/direct_rpms"

# SRIOV NIC make sure it up.
# each PCI resolved to respected ethX adapter
SRIOV_PCI_LIST="pci@0000:51:00.0,pci@0000:51:00.1"
MAX_VFS_PER_PCI=8
# overwrite default pci list
if [ -z "$OVERWRITE_SRIOV_PCI" ]; then
  echo "Using default SRIOV_PCI_LIST $SRIOV_PCI_LIST."
else
  SRIOV_PCI_LIST=$OVERWRITE_SRIOV_PCI
  echo "Change sriov vfs to $SRIOV_PCI_LIST"
fi
# overwrite max vs
if [ -z "$OVERWRITE_MAX_VFS_PER_PCI" ]; then
  echo "Using default MAX_VFS_PER_PCI value $MAX_VFS_PER_PCI."
else
  MAX_VFS_PER_PCI=$OVERWRITE_MAX_VFS_PER_PCI
  echo "Change max vfs to $MAX_VFS_PER_PCI"
fi

# list of vlan interface that we need create.
# pci resolved to adapter that we want to use for a trunk
DOT1Q_VLAN_ID_LIST="2000,2001"
DOT1Q_VLAN_TRUNK_PCI="pci@0000:18:00.1"
if [ -z "$OVERWRITE_DOT1Q_VLAN_ID_LIST" ]; then
  echo "Using default DOT1Q_VLAN_ID_LIST value $DOT1Q_VLAN_ID_LIST."
else
  DOT1Q_VLAN_ID_LIST=$OVERWRITE_DOT1Q_VLAN_ID_LIST
  echo "Change default VLAN ID LIST to $DOT1Q_VLAN_ID_LIST"
fi

if [ -z "$OVERWRITE_DOT1Q_VLAN_TRUNK_PCI" ]; then
  echo "Using default DOT1Q_VLAN_TRUNK_PCI value $DOT1Q_VLAN_TRUNK_PCI."
else
  DOT1Q_VLAN_TRUNK_PCI=$OVERWRITE_DOT1Q_VLAN_TRUNK_PCI
  echo "Change default PCI address for dot1q to $DOT1Q_VLAN_TRUNK_PCI"
fi

# prefix used to generate each trunk ethernet and netdev
DOT1Q_SYSTEMD_DEFAULT_PREFIX="10-vlan"
DOT1Q_ETH_NAME="main"
# enables LLD on ethe adapter
LLDP="yes"
LLDP_EMIT="yes"

# adapter that we want use for static IP.
STATIC_ETHn_NAME="eth0"
STATIC_ETHn_ADDRESS="192.168.254.1/24"
STATIC_ETHn_GATEWAY="192.168.254.254"
STATIC_ETHn_STATIC_DNS="8.8.8.8"

# overwrite for eth name
if [ -z "$OVERWRITE_STATIC_ETHn_NAME" ]; then
  echo "Using default STATIC_ETHn_NAME. $STATIC_ETHn_NAME"
else
  STATIC_ETHn_NAME=$OVERWRITE_STATIC_ETHn_NAME
  echo "Change default static ethernet name to $STATIC_ETHn_NAME"
fi
# overwrite for IP address
if [ -z "$OVERWRITE_STATIC_ETHn_ADDRESS" ]; then
  echo "Using default static ethernet address. $STATIC_ETHn_ADDRESS"
else
  STATIC_ETHn_ADDRESS=$OVERWRITE_STATIC_ETHn_ADDRESS
  echo "Change default static address to $STATIC_ETHn_ADDRESS"
fi

# overwrite for gateway
if [ -z "$OVERWRITE_STATIC_ETHn_GATEWAY" ]; then
  echo "Using default STATIC_ETHn_GATEWAY. $STATIC_ETHn_GATEWAY"
else
  STATIC_ETHn_GATEWAY=$OVERWRITE_STATIC_ETHn_GATEWAY
  echo "Change default STATIC_ETHn_NAME address for static to $STATIC_ETHn_GATEWAY"
fi

# overwrite for dns
if [ -z "$OVERWRITE_STATIC_ETHn_STATIC_DNS" ]; then
  echo "Using default STATIC_ETHn_STATIC_DNS. $STATIC_ETHn_STATIC_DNS"
else
  STATIC_ETHn_STATIC_DNS=$OVERWRITE_STATIC_ETHn_STATIC_DNS
  echo "Change default STATIC_ETHn_NAME address for static to $STATIC_ETHn_STATIC_DNS"
fi

# by default can generate DHCP and static.
# DHCP enabled masked e* while static for particular adapter.
DEFAULT_SYSTEMD_STATIC_NET_NAME_PREFIX="99-static"
# default name used to generate DHCP
DEFAULT_DHCP_NET_NAME="99-dhcp-en.network"

# default path to system d
DEFAULT_SYSTEMD_PATH="/etc/systemd/network"

# number of huge pages for 2k and 1GB
# make sure this number is same or less than what I do for mus_rt tuned profile.
# i.e. cross-check /proc/cmdline if you need more adjust config at the bottom.
PAGES="2048"
PAGES_1GB="8"

# PTP adapter. i.e 810 or PCI_PT
PTP_ADAPTER="pci@0000:8a:00.1"

# All links and directories
IPSEC_LIB_LOCATION="https://github.com/intel/intel-ipsec-mb.git"
ISA_L_LOCATION="https://github.com/intel/isa-l"
TUNED_LOCATION="https://github.com/spyroot/tuned.git"
PYELF_LIB_LOCATION="https://github.com/eliben/pyelftools.git"
YASM_LOCATION="https://github.com/yasm/yasm.git"


# mirror for all online files.
# drivers etc.
DPDK_URL_LOCATIONS=(
  "http://fast.dpdk.org/rel/dpdk-21.11.tar.xz"
  "https://drive.google.com/u/0/uc?id=1EllCI6gkZ3O70CXAXW9F4QCFD6IrGgZx&export=download&confirm=1e-b")
# Lib NL
LIB_NL_LOCATION=(
  "https://www.infradead.org/~tgr/libnl/files/libnl-3.2.25.tar.gz"
  "https://www.infradead.org/~tgr/libnl/files/libnl-3.2.25.tar.gz"
)
# Mellanox IAVF driver
IAVF_LOCATION=(
  "https://downloadmirror.intel.com/738727/iavf-$AVX_VERSION.tar.gz"
  "https://downloadmirror.intel.com/738727/iavf-$AVX_VERSION.tar.gz"
)
# Mellanox OFED driver
MELLANOX_LOCATION=(
  "http://www.mellanox.com/downloads/ofed/MLNX_OFED-$MLNX_VER/MLNX_OFED_SRC-debian-$MLNX_VER.tgz"
  "http://www.mellanox.com/downloads/ofed/MLNX_OFED-$MLNX_VER/MLNX_OFED_SRC-debian-$MLNX_VER.tgz"
)

DPDK_TARGET_DIR_BUILD="$ROOT_BUILD/dpdk-21.11"
LIB_ISAL_TARGET_DIR_BUILD="$ROOT_BUILD/isa-l"
YASM_TARGET_DIR_BUILD="$ROOT_BUILD/yasm"

# DRIVER TMP DIR where we are building.
MLX_DIR=/tmp/mlnx_ofed_src
INTEL_DIR=/tmp/iavf

# all logs
BUILD_MELLANOX_LOG="$BUILD_LOG/build_mellanox_driver.log"
BUILD_INTEL_LOG="$BUILD_LOG/build_intel_driver.log"
BUILD_DOCKER_LOG="$BUILD_LOG/build_docker_images.log"
BUILD_IPSEC_LOG="$BUILD_LOG/build_ipsec_lib.log"
BUILD_PIP_LOG="$BUILD_LOG/build_pip_deps.log"
BUILD_NL_LOG="$BUILD_LOG/build_nl.log"
BUILD_ISA_LOG="$BUILD_LOG/build_isa.log"
BUILD_DPDK_LOG="$BUILD_LOG/build_dpdk.log"
BUILD_PYELF_LOG="$BUILD_LOG/build_pyelf.log"
BUILD_TUNED_LOG="$BUILD_LOG/build_tuned.log"
BUILD_HUGEPAGES_LOG="$BUILD_LOG/build_hugepages.log"
BUILD_PTP_BUILD_LOG="$BUILD_LOG/build_ptp.log"
BUILD_YASM_LOG="$BUILD_LOG/build_yasm.log"
DEFAULT_BUILDER_LOG="$BUILD_LOG/build_main.log"



# Variable for static network
# mainly if we want set static IP for adapter
# Note by default BUILD_STATIC_ADDRESS=no
STATIC_ETHn_NAME="eth0"
STATIC_ETHn_ADDRESS="192.168.254.1/24"
STATIC_ETHn_GATEWAY="192.168.254.254"
STATIC_ETHn_STATIC_DNS="8.8.8.8"

# Functions definition,  scroll down to main.
#
#
#

# Function checks if string contains yes or not
function is_yes() {
  local var=$1
  if [[ -z "$var" ]]; then
    return 1
  else
    if [ "$var" == "yes" ]; then
      return 0
    else
      return 1
    fi
  fi
}

# Function check if string empty or not
function is_not_empty() {
  local var=$1
  if [[ -z "$var" ]]; then
    return 1
  else
    return 0
  fi
}

log_green() {
  printf "%b %s. %b\n" "${GREEN}" "$@" "${NC}"
}

# Function removes blacks
function remove_all_spaces {
  local str=$1
  echo "${str//[[:blank:]]/}"
}
# return 0 if ubuntu os
function is_ubuntu_os {
  local -r ver="$1"
  grep -q "Ubuntu $ver" /etc/*release
}
# return 0 if centos os.
function is_centos_os {
  local -r ver="$1"
  grep -q "CentOS Linux release $ver" /etc/*release
}
# return 0 if target machine photon os.
function is_photon_os {
  local -r ver="$1"
  grep -q "VMware Photon OS $ver" /etc/*release
}
# return 0 if command installed
function is_cmd_installed {
  local -r cmd_name="$1"
  command -v "$cmd_name" > /dev/null
}

# Function trim spaces from input str, filters pci device tree
# by type network and return name of all adapter.
# pci_to_adapter pci@0000:8a:00.0 return -> eth3
function pci_to_adapter() {
  local var="$*"
  local adapter
  var="${var#"${var%%[![:space:]]*}"}"
  var="${var%"${var##*[![:space:]]}"}"
  adapter=$(lshw -class network -businfo -notime | grep "$var" | awk '{print $2}')
  echo "$adapter"
}

# neat way to split string
# call my_arr=( $(split_array "," "a,b,c") )
function split_array {
  local -r sep="$1"
  local -r str="$2"
  local -a ary=()
  IFS="$sep" read -r -a ary <<<"$str"
  echo "${ary[*]}"
}

# return true 0 if the given file exists
function file_exists {
  local -r a_file="$1"
  [[ -f "$a_file" ]]
}

# return true (0) if the first arg contains the second arg
function string_contains {
  local -r _s1="$1"
  local -r _s2="$2"
  [[ "$_s1" == *"$_s2"* ]]
}

# Strip the prefix from the string.
# Example:
#   pci@0000:8a:00.0,pci@0000:8a:00.1
#   strip_prefix "pci@0000:8a:00.0" "pci@0000:"  return "8a:00.0"
#   strip_prefix "pci@0000:8a:00.0" "*@" return "0000:8a:00.0"
function strip_prefix {
  local -r src_str="$1"
  local -r prefix="$2"
  echo "${src_str#"$prefix"}"
}

# Example:
#   pci@0000:8a:00.0, pci@0000:8a:00.1
#   strip_suffix "pci@0000:8a:00.0" ":8a:00.0"  return "pci@0000"
function strip_suffix {
  local -r src_str="$1"
  local -r suffix="$2"
  echo "${src_str%"$suffix"}"
}

function is_null_or_empty {
  local -r source_str="$1"
  [[ -z "$source_str" || "$source_str" == "null" ]]
}

# "pci@0000:8a:00.1" -> 0000
function pci_domain() {
    local -r src_str="$1"
    echo "$src_str" | awk -F'@' '{print $2}' | awk -F':' '{print $1}'
}

# Takes "pci@0000:8a:00.1" -> 8a
function pci_bus() {
    local -r src_str="$1"
    echo "$src_str" | awk -F':' '{print $2}'
}
# Takes "pci@0000:8a:00.1" -> 00
function pci_device() {
    local -r src_str="$1"
    echo "$src_str" | awk -F':' '{print $3}' | awk -F'.' '{print $1}'
}
# Takes "pci@0000:8a:00.1" -> 1
function pci_function() {
    local -r src_str="$1"
    echo "$src_str" | awk -F':' '{print $3}' | awk -F'.' '{print $2}'
}

# Takes pci@0000:8a:00.1 -> 0000:8a
function pci_domain_and_bus() {
    local -r src_str="$1"
    if is_null_or_empty "$src_str"; then
      echo ""
    else
      echo "$src_str" | awk -F'@' '{print $2}' | awk -F'.' '{print $1}' | awk -F':' '{print $1":"$2}'
    fi
}

# Extract directory
function extrac_dir() {
  local dir_path=$1
  local dir_name
  dir_name=""

  if [ -z "$dir_path" ]; then
    dir_name=""
  else
    local dir_name
    dir_path=$(trim "$dir_path")
    dir_name=$(dirname "$dir_path")
  fi

  echo "$dir_name"
}

# Function extracts filename
# arg full path to a file
function extrac_filename() {
  local file_path=$1
  local file_name
  file_name=""

  if [ -z "$file_path" ]; then
    file_name=""
  else
    local file_name
    file_path=$(trim "$file_path")
    file_name=$(basename "$file_path")
  fi

  echo "$file_name"
}

# append to array
function array_append {
  local -r _content="$1"
  local -ar ary=("$@")
  local final_aray
  final_aray=( "${ary[@]/#/$_content}" )
  echo "${final_aray[*]}"
}

# takes array X and comma seperated list of pci devices
# populate array X with resolved network adapters.
function adapters_from_pci_list() {
  # array that will store ethernet names
  local -n eth_name_array=$1
  # a command separated string of pci devices.
  local sriov_pci_devices=$2

  local separator=','
  eth_name_array=$(declare -p sriov_pci_devices)
  # read
  IFS=$separator read -ra sriov_pci_array <<<"$sriov_pci_devices"
  (( j == 0)) || true
  for sriov_device in "${sriov_pci_array[@]}"; do
    local domain_bus
    domain_bus=$(pci_domain_and_bus "$sriov_device")
    local sysfs_device_path="/sys/class/pci_bus/$domain_bus/device/enable"
    if [ -r "$sysfs_device_path" ]; then
      local adapter_name
      echo "Reading from $sysfs_device_path"
      adapter_name=$(pci_to_adapter "$sriov_device")
      echo "Resolve $sriov_device to ethernet adapter $adapter_name"
      eth_name_array[j]=$adapter_name
      (( j++ )) || true
    else
      echo "failed to read sys path $sysfs_device_path"
    fi
  done
}

# Function create create log dir.
function create_log_dir() {
  local log_dir
  local default_log=$1
  log_dir=$(dirname "$default_log")
  if ! mkdir "$log_dir"; then
    echo "The $log_dir target directory probably is read-only."
  fi
}

# log message to console and file.
# if log dir not present it will create it.
# if log file already present, log msg will be appended.
# log message to console and file.
function log_console_and_file() {
  local log_dir
  local default_log=$DEFAULT_BUILDER_LOG
  printf "%b %s %b\n" "${GREEN}" "$@" "${NC}"

  log_dir=$(extrac_dir $default_log)
  if [ ! -d log_dir ]; then
    mkdir -p "$log_dir"
  fi

  if file_exists "$default_log"; then
    echo "$@" >>"$default_log"
  else
    echo "$@" >"$default_log"
  fi
}

# log message to console and file.
# for keep, it separates
function log_green_console_and_file() {
  local log_dir
  local default_log=$DEFAULT_BUILDER_LOG
  printf "%b %s %b\n" "${GREEN_CUSTOM}" "$@" "${NC_CUSTOM}"

  log_dir=$(extrac_dir $default_log)
  if [ ! -d log_dir ]; then
    mkdir -p "$log_dir"
  fi

  if file_exists "$default_log"; then
    echo "$@" >>"$default_log"
  else
    echo "$@" >"$default_log"
  fi
}

# Function take list of PCI devices, and number of target VFs,
# Checks each PCI address in sysfs,
# Resolves each PCI address from format the input pci@0000:BB:AA.0 to
# respected eth name.
# Enables sriov if num vfs will reset to target num VFs.
function enable_sriov() {
  local eth_array
  local list_of_pci_devices=$1
  declare -i target_num_vfs=$2
  adapters_from_pci_list eth_array "$list_of_pci_devices"
#  "${GREEN}" "$@" "${NC}"
  log_console_and_file "Enabling SRIOV ${eth_array[*]} target num vfs $target_num_vfs"

  if is_yes "$IS_INTERACTIVE"; then
        local choice
        read -r -p "Building SRIOV resolved adapter ${eth_array[*]} (y/n)?" choice
        case "$choice" in
        y | Y)  ;;
        n | N) return 1 ;;
        *) echo "invalid" ;;
        esac
  fi

  if [ -z "$BUILD_SRIOV" ]; then
    log_console_and_file "Skipping SRIOV phase."
    return 0
  fi

  log_console_and_file "Loading vfio and vfio-pci."
  modprobe vfio
  modprobe vfio-pci enable_sriov=1
  # First enable num VF on interface Check that we have correct number of vs and
  # adjust if needed then for each VF set to trusted mode and enable disable spoof check
  echo "Building sriov config for $eth_array"
  for sriov_eth_name in "${eth_array[@]}"; do
    local sysfs_path
    sysfs_path="/sys/class/net/$sriov_eth_name/device/sriov_numvfs"
    log_console_and_file "sysfs path $sysfs_path"
    if [ -r "$sysfs_path" ]
    then
        log_console_and_file "Reading from $sysfs_path"
        local if_status
        if_status=$(ip link show "$sriov_eth_name" | grep UP)
        [ -z "$if_status" ] && {
          log_console_and_file "Error: Interface $sriov_eth_name either down or invalid."
          break
        }
        if [ ! -e "$sysfs_eth_path" ]; then
          touch "$sysfs_eth_path" 2>/dev/null
        fi
        local current_num_vfs
        current_num_vfs=$(cat "$sysfs_path" | grep $target_num_vfs)
        if [ "${target_num_vfs:-0}" -ne "${current_num_vfs:-0}" ]
        then
            log_console_and_file "Error: Expected number of sriov vfs for adapter=$sriov_eth_name vfs=$target_num_vfs found $current_num_vfs"
            # note if adapter bounded we will not be able to do that.
            log_console_and_file "num vfs $target_num_vfs"
            echo "$target_num_vfs" > "$sysfs_path"
        fi
        #  set to trusted mode and enable disable spoof check
        for ((i = 1; i <= target_num_vfs; i++)); do
          log_console_and_file "Enabling trust on $sriov_eth_name vf $i"
          ip link set "$sriov_eth_name" vf "$i" trust on 2>/dev/null
          ip link set "$sriov_eth_name" vf "$i" spoof off 2>/dev/null
        done
    else
        log_console_and_file "Failed to read $sysfs_eth_path"
        log_console_and_file "Adjusting number of vf $target_num_vfs in $sysfs_eth_path"
        echo "$target_num_vfs" > "$sysfs_path"
    fi
  done
}

# Function check if image already loaded
# Usage:
# if is_tar "file.tar"; then
#     echo "Image loaded"
# fi
function is_tar() {
  local file_name=$1
  local is_tar
  is_tar=$(file "$file_name" | grep tar)
  if [[ -z "$is_tar" ]]; then
    return 1
  else
    return 0
  fi
}

# Function check if device mounted
# Usage:
# if is_mounted "cdrom"; then
#     echo "cdrom mounted"
# fi
is_cdrom_mounted() {
  local dev=$1
  local is_mounted
  is_mounted=$(mount | grep "$dev")
  if [[ -z "$is_mounted" ]]; then
    return 1
  else
    return 0
  fi
}

# Function check if image already loaded
# Usage:
# if is_docker_image_present "spyroot/photon_iso_builder"; then
#     echo "Image loaded"
# fi
function is_docker_image_present() {
  local image_name=$1
  local docker_image
  docker_image=$(docker image ls | grep "$image_name")
  if [[ -z "$docker_image" ]]; then
    return 1
  else
    return 0
  fi
}

# Function check if docker is up
# Usage:
# if is_docker_up; then
#   echo "do"
# fi
function is_docker_up() {
  local is_docker_running
  is_docker_running=$(systemctl status docker | grep running)
  if [[ -z "$is_docker_running" ]]; then
    return 1
  else
    return 0
  fi
}

# Function load docker image
# First argument is log file.
# second argument path to a file
# third name of image
#
# Usage:
#   load_docker_image /builder/build_docker.log image_path image_name,
function build_docker_images() {
  local log_file=$1
  local docker_image_path=$2
  local docker_image_name=$3

  if file_exists "$docker_image_path"; then
    log_console_and_file "  Docker image $docker_image_path exists."
    if [ -z "$BUILD_LOAD_DOCKER_IMAGE" ]; then
      log_console_and_file " -Attempting load a docker image $docker_image_path."
    else
      if is_yes "$IS_INTERACTIVE"; then
        local choice
        read -r -p "Building docker and loading $docker_image_path (y/n)?" choice
        case "$choice" in
        y | Y)  ;;
        n | N) return 1 ;;
        *) echo "invalid" ;;
        esac
      fi

      if is_not_empty "$docker_image_path"; then
        log_console_and_file " -Enabling docker services."
        systemctl enable docker
        systemctl start docker
        systemctl daemon-reload
        if is_docker_up; then
            log_console_and_file " -Docker is up"
            if is_docker_image_present "$docker_image_name"; then
                log_console_and_file " -Loading docker image from $docker_image_path"
                docker load < "$docker_image_path"
                docker image ls > "$log_file" 2>&1
            fi
        fi
      fi
    fi
    else
      echo "Docker file $docker_image_path not found."
  fi
}

# Function build pyelf lib
function build_pyelf() {
  local log_file=$1
  local suffix
  local repo_name
  touch "$log_file" 2>/dev/null
  suffix=".git"

  repo_name=${PYELF_LIB_LOCATION/%$suffix/}
  repo_name=${repo_name##*/}
  local pyelf_lib_path
  pyelf_lib_path=$ROOT_BUILD/"$repo_name"

  if [ -z "$DPDK_BUILD" ]
  then
      log_console_and_file "Skipping pyelf since DPDK build is disabled."
  else
      if is_yes "$IS_INTERACTIVE"; then
      local choice
      read -r -p "Building pyelf lib (y/n)?" choice
      case "$choice" in
      y | Y)  ;;
      n | N) return 1 ;;
      *) echo "invalid" ;;
      esac
    fi
    log_console_and_file "Building pyelf lib."
    # we load image from DEFAULT_GIT_IMAGE_DIR
    if [ -d $DEFAULT_GIT_IMAGE_DIR ]; then
        mkdir -p "$pyelf_lib_path"
        log_console_and_file " -Unpacking pyelf to $pyelf_lib_path from a local source copy."
        log_console_and_file " -Pyelf location $DEFAULT_GIT_IMAGE_DIR/pyelftolls."
        tar xfz $DEFAULT_GIT_IMAGE_DIR/pyelftools*tar.gz --warning=no-timestamp -C "$ROOT_BUILD"
    else
        log_console_and_file " -Cloning pyelf lib from a git source."
        pushd $ROOT_BUILD || exit
        git clone "$PYELF_LIB_LOCATION" > "$log_file" 2>&1
        popd || exit
    fi

    if [ -d "$pyelf_lib_path" ]; then
      log_console_and_file " -Building $pyelf_lib_path"
      pushd "$pyelf_lib_path" || exit
      /bin/python setup.py install > "$log_file" 2>&1
      popd || exit
    else
      log_console_and_file "Failed create $pyelf_lib_path"
    fi
  fi
}

# Function builds an ipsec lib.
# It required lib for DPDK and enabled crypto
#
function build_ipsec_lib() {
  local log_file=$1
  local suffix
  local repo_name
  touch "$log_file" 2>/dev/null
  suffix=".git"

  if [ -z "$IPSEC_BUILD" ]
  then
      log_console_and_file "Skipping ipsec lib build."
  else
      if is_yes "$IS_INTERACTIVE"; then
      local choice
      read -r -p "Building ipsec lib (y/n)?" choice
      case "$choice" in
      y | Y)  ;;
      n | N) return 1 ;;
      *) echo "invalid" ;;
      esac
    fi

    repo_name=${IPSEC_LIB_LOCATION/%$suffix/}
    repo_name=${repo_name##*/}
    local ipsec_lib_path
    ipsec_lib_path=$ROOT_BUILD/"$repo_name"

    # we load image from DEFAULT_GIT_IMAGE_DIR
    if [ -d $DEFAULT_GIT_IMAGE_DIR ]; then
        local tar_file
        tar_file=$DEFAULT_GIT_IMAGE_DIR/$DEFAULT_IPSEC_TAR_NAME
        if file_exists tar_file; then
          log_console_and_file " -Unpacking $tar_file ipsec lib from a local copy to $ipsec_lib_path."
          mkdir -p "$ipsec_lib_path"
          tar xfz $tar_file --warning=no-timestamp -C "$ROOT_BUILD"
        else
          log_console_and_file " -File $tar_file not found."
          log_console_and_file " -Cloning ipsec lib from a git copy."
          cd $ROOT_BUILD || exit; git clone "$IPSEC_LIB_LOCATION" > "$log_file" 2>&1
        fi
    else
      log_console_and_file " -Directory $DEFAULT_GIT_IMAGE_DIR not found."
      log_console_and_file " -Building ipsec lib from a git copy."
      cd $ROOT_BUILD || exit; git clone "$IPSEC_LIB_LOCATION" > "$log_file" 2>&1
    fi

    log_console_and_file " -Building ipsec lib in build dir $ipsec_lib_path"
    cd "$ipsec_lib_path" || exit; make clean SHARED=n
    cd "$ipsec_lib_path" || exit; make -j 16 AESNI_EMU=y > "$log_file" 2>&1
    make install &> "$log_file"; ldconfig; ldconfig /usr/lib
  fi
}

# Function builds mellanox driver
# args log file, file_name, mlx_ver
function build_mellanox_driver() {
  local log_file=$1
  local build_dir=$2
  echo "" > "$log_file"

  if [ -z "$MLX_BUILD" ]
  then
      log_console_and_file "Skipping Mellanox driver build."
  else
    if is_yes "$IS_INTERACTIVE"; then
      local choice
      read -r -p "Building mellanox driver from $build_dir (y/n)?" choice
      case "$choice" in
      y | Y)  ;;
      n | N) return 1 ;;
      *) echo "invalid" ;;
      esac
    fi
    cd "$build_dir" || exit; tar -zxvf MLNX_OFED_SRC-debian-* -C  mlnx_ofed_src --strip-components=1 > "$log_file" 2>&1
  fi
}

# Function builds intel iavf
# args log_file , download dir
function build_intel_iavf() {
  local log_file=$1
  local build_dir=$2
  echo "" >"$log_file"

  if [ -z "$INTEL_BUILD" ]
  then
      log_console_and_file "Skipping intel driver build."
  else
    if is_yes "$IS_INTERACTIVE"; then
      local choice
      read -r -p "Building intel iavf driver from $build_dir (y/n)?" choice
      case "$choice" in
      y | Y)  ;;
      n | N) return 1 ;;
      *) echo "invalid" ;;
      esac
    fi
    mkdir -p "$build_dir"
    cd "$build_dir" || exit; tar -zxvf iavf-* -C iavf --strip-components=1 > "$log_file" 2>&1
    if is_yes "$IS_INTERACTIVE"; then
      cd "$build_dir"/src || exit; make
      make install
    else
      cd "$build_dir"/src || exit; make > "$log_file" 2>&1; make install > "$log_file.iavf.install.log" 2>&1
    fi
  fi
}

# Function adjust shared libs
function adjust_shared_libs() {
  log_console_and_file "Adjusting shared libs."
  # we add shared lib to ld.so.conf
  local SHARED_LIB_LINE='/usr/local/lib'
  local SHARED_LD_FILE='/etc/ld.so.conf'
  grep -qF -- "$SHARED_LIB_LINE" "$SHARED_LD_FILE" || echo "$SHARED_LIB_LINE" >>"$SHARED_LD_FILE"
  ldconfig
}

# Function install requires pips
# first args a log file , second bash array
# or all required package names
function build_install_pips_deb() {
  local log_file=$1
  shift
  local pip_array=("$@")
  touch "$log_file" 2>/dev/null
  for pip_pkg_name in "${pip_array[@]}"; do
    log_console_and_file "Install pip $pip_pkg_name"
    pip3 install "$pip_pkg_name" > "$log_file" 2>&1
  done
}

# Function builds lib nl
#  First argument a path to log file.
function build_lib_nl() {
  local log_file=$1
  local build_dir=$2
  touch "$log_file" 2>/dev/null

  # build and install libnl
  if [ -z "$LIBNL_BUILD" ]; then
    log_console_and_file "Skipping libnl driver build"
  else

    if is_yes "$IS_INTERACTIVE"; then
      local choice
      read -r -p "Building lib nl in $build_dir parallel build 8 (y/n)?" choice
      case "$choice" in
      y | Y)  ;;
      n | N) return 1 ;;
      *) echo "invalid" ;;
      esac
    fi

    log_console_and_file " -Extracting libnl to $build_dir"
    cd "$build_dir" || exit; tar -zxvf libnl-*.tar.gz -C libnl --strip-components=1 > "$log_file" 2>&1
    cd "$build_dir" || exit
    ./configure --prefix=/usr &>/build/build_configure_nl.log
    make -j 8 > "$log_file" 2>&1; make install > "$log_file" 2>&1
    ldconfig; ldconfig /usr/local/lib
  fi
}

# Function builds yasm.
#  First argument a path to log file.
#  it downloads only.
function build_yasm() {
  local log_file=$1
  touch "$log_file" 2>/dev/null
  local suffix
  suffix=".git"

  local repo_name
  repo_name=${YASM_LOCATION/%$suffix/}
  repo_name=${repo_name##*/}
  local yasm_lib_path=$ROOT_BUILD/"$repo_name"

  # build and install isa
  if [ -z "$YASM_LOCATION" ]; then
    log_console_and_file "Skipping yasm build"
  else
     if is_yes "$IS_INTERACTIVE"; then
        local choice
        read -r -p "Building yasm in $YASM_TARGET_DIR_BUILD parallel build 8 (y/n)?" choice
        case "$choice" in
        y | Y)  ;;
        n | N) return 1 ;;
        *) echo "invalid" ;;
        esac
    fi

    # if git dir exist first we check for tar
    local lib_file=""
    if [ -d $DEFAULT_GIT_IMAGE_DIR ]; then
        lib_file=$(file /$DEFAULT_GIT_IMAGE_DIR/*yasm* | grep gzip)
        if is_not_empty "$lib_file"; then
          mkdir -p "$yasm_lib_path"
          log_console_and_file " -Unpacking yasm from local to $yasm_lib_path."
          tar xfz $DEFAULT_GIT_IMAGE_DIR/*yasm* --warning=no-timestamp -C "$ROOT_BUILD"
        fi
    fi

    # fall back to git
    if is_null_or_empty "$lib_file"; then
      log_console_and_file "Building yasm lib from a git."
      cd $ROOT_BUILD || exit; git clone "$YASM_LOCATION" > "$log_file" 2>&1
    fi

    mkdir -p $YASM_TARGET_DIR_BUILD
    cd $YASM_TARGET_DIR_BUILD || exit
    chmod 700 autogen.sh && ./autogen.sh > "$log_file" 2>&1
    ./configure > "$log_file" 2>&1
    make -j 8 > "$log_file.yasm.build.log" 2>&1; make install > "$log_file.yasm.install.log" 2>&1
    ldconfig; ldconfig /usr/local/lib; ldconfig /usr/lib
  fi
}

# Function builds lib isa
#  First argument a path to log file.
#  it downloads only.
function build_lib_isa() {
  local log_file=$1
  touch "$log_file" 2>/dev/null
  local suffix
  suffix=".git"

  local repo_name
  repo_name=${ISA_L_LOCATION/%$suffix/}
  repo_name=${repo_name##*/}
  local isa_lib_path
  isa_lib_path=$ROOT_BUILD/"$repo_name"

  # build and install isa
  if [ -z "$LIBNL_ISA" ]; then
    log_console_and_file "Skipping isa-l driver build"
  else
     if is_yes "$IS_INTERACTIVE"; then
        local choice
        read -r -p "Building lib isa in $LIB_ISAL_TARGET_DIR_BUILD parallel build 8 (y/n)?" choice
        case "$choice" in
        y | Y)  ;;
        n | N) return 1 ;;
        *) echo "invalid" ;;
        esac
    fi

    # if git dir exist first we check for tar
    local lib_file=""
    if [ -d $DEFAULT_GIT_IMAGE_DIR ]; then
        lib_file=$(file /$DEFAULT_GIT_IMAGE_DIR/*isa* | grep gzip)
        if is_not_empty "$lib_file"; then
          mkdir -p "$isa_lib_path"
          log_console_and_file " -Unpacking isa-l from local to $isa_lib_path."
          tar xfz $DEFAULT_GIT_IMAGE_DIR/*isa-l* --warning=no-timestamp -C "$ROOT_BUILD"
        fi
    fi

    # fall back to git
    if is_null_or_empty "$lib_file"; then
      log_console_and_file "Building isa-l lib from a git."
      cd $ROOT_BUILD || exit; git clone "$ISA_L_LOCATION" > "$log_file" 2>&1
    fi

    mkdir -p $LIB_ISAL_TARGET_DIR_BUILD
    cd $LIB_ISAL_TARGET_DIR_BUILD || exit
    chmod 700 autogen.sh && ./autogen.sh > "$log_file" 2>&1
    ./configure > "$log_file" 2>&1
    make -j 8 > "$log_file.build.log" 2>&1; make install > "$log_file.isa.install.log" 2>&1
    ldconfig; ldconfig /usr/local/lib; ldconfig /usr/lib
  fi
}

# Function link a new kernel header src
# to /usr/src
function link_kernel() {
  local custom_kern_prefix=$1
  local target_system
  local kernel_src_path
  local default_kernel_prefix="/usr/src/linux-headers-"

  local major
  major=$(find /boot/*rt.cfg | cut -d  '/' -f 3 | cut -d '-' -f 2)
  local minor
  minor=$(find /boot/*rt.cfg | cut -d  '/' -f 3 | cut -d '-' -f 3)

  target_system=$(find /boot/*rt.cfg | sed 's/^.boot\/linux-//' | sed 's/^//' | sed 's/.cfg$//')
  log_console_and_file " -discovered rt kernel $target_system"
  if is_not_empty "$custom_kern_prefix"; then
    log_console_and_file " -Using custom provided kernel header dir $default_kernel_prefix"
    kernel_src_path=$custom_kern_prefix
  else
    kernel_src_path=$default_kernel_prefix$target_system
    log_console_and_file " -Using kernel header src $kernel_src_path"
  fi

  if [ ! -d "$kernel_src_path" ]; then
    log_console_and_file " -Failed resolve a kernel src path $kernel_src_path taking current from /boot/photon.cfg"
    local ver
    local min
    cp /boot/*rt.cfg /boot/photon.cfg
    ver=$(cat /boot/photon.cfg|grep vmlinuz|cut -d '=' -f 2|cut -d '-' -f 2)
    min=$(cat /boot/photon.cfg|grep vmlinuz|cut -d '=' -f 2|cut -d '-' -f 3)
    kernel_src_path=/usr/src/linux-headers-$ver-$min-"rt"
    if [ ! -d "$kernel_src_path" ]; then
        log_console_and_file " -Failed resole $kernel_src_path kernel src path. please stop check system."
    else
        log_green_console_and_file " -Resolved $kernel_src_path kernel headers."
        depmod
    fi
  fi

  if is_yes "$IS_INTERACTIVE"; then
        local choice
        read -r -p "Linking /usr/src/link to $kernel_src_path (y/n)?" choice
        case "$choice" in
        y | Y)  ;;
        n | N) return 1 ;;
        *) echo "invalid" ;;
        esac
  fi

  rm -rf /usr/src/linux
  ln -s "$kernel_src_path"/ /usr/src/linux 2>/dev/null
  if [ ! -d "/usr/src/linux" ]; then
    log_green_console_and_file "Failed create link /usr/src/linux to a current kernel source."
  fi
}

# Function builds DPDK
#  First arg a path to log file.
#  Second optional arg path to a kernel headers
#  path is optional in case we use none default location
function build_dpdk() {
    local log_file=$1
    local build_dir=$2
    local custom_kern_prefix=$3
    local build_flags="-Dplatform=native -Dexamples=all -Denable_kmods=true -Dibverbs_link=shared -Dwerror=true -Dprefix=/usr"

    touch "$log_file" 2>/dev/null
    local default_kernel_prefix="/usr/src/linux-headers-"

    if [ -z "$custom_kern_prefix" ]; then
      log_console_and_file "Using default kernel header prefix $default_kernel_prefix"
    else
      log_console_and_file "Using user supplied prefix $default_kernel_prefix"
      default_kernel_prefix=$custom_kern_prefix
    fi

    # kernel source and DPDK, we're building with Intel and Mellanox driver.
    local yum_tools=("linux-rt-devel" "linux-devel" "dkms" "stalld" "openssl-devel" "libmlx5" "dtc" "dtc-devel" "meson" "doxygen" "python3-sphinx" "libpcap" "libpcap-devel" "libbpf" "libbpf-devel" "lshw")
    for yum_tool in "${yum_tools[@]}"
    do
      local is_installed
      is_installed=$(rpm -qa yum_tool)
      log_console_and_file "Check required packages"
      if is_not_empty is_installed; then
        log_console_and_file " tools $yum_tool installed."
      else
        log_console_and_file " tool $tool not installed, installing via yum"
        yum install "$tool"
      fi
    done

    # this will move out
    yum --quiet -y install stalld dkms linux-devel linux-rt-devel dtc dtc-devel meson
    doxygen libpcap libpcap-devel libbpf libbpf-developenssl-devel libmlx5 lshw > "$log_file" 2>&1
    # first we check all tools in place.
    local dpdk_tools=("meson" "python3" "ninja")
    log_console_and_file " Checking required pip packages"
    for tool in "${dpdk_tools[@]}"
    do
      if is_cmd_installed "$tool"
      then
        log_console_and_file "tools $tool installed."
      else
        log_console_and_file "tool $tool not installed."
      fi
    done

    if [ -z "$DPDK_BUILD" ]; then
      log_console_and_file "Skipping DPDK build."
    else
      local kernel_src_path
      local target_system
      local meson_build_dir
      target_system=$(find /boot/*rt.cfg | sed 's/^.boot\/linux-//' | sed 's/^//' | sed 's/.cfg$//')
      kernel_src_path=$default_kernel_prefix$target_system
      meson_build_dir=$build_dir/"build"

      if is_yes "$IS_INTERACTIVE"; then
        echo "Using kernel $kernel_src_path"
        echo "meson build location $meson_build_dir"
        echo "Using $build_flags"

        local choice
        read -r -p "Building DPDK build location $meson_build_dir number of concurrent make: 8 (y/n)?" choice
        case "$choice" in
        y | Y)  ;;
        n | N) return 1 ;;
        *) echo "invalid" ;;
        esac
      fi
      log_console_and_file "Building DPDK."
      log_console_and_file " -Using kernel source tree $kernel_src_path"
      if [ ! -d "$kernel_src_path" ]; then
        log_console_and_file "Failed locate kernel source."
      fi

      # in case pip wasn't called , we need install pyelftools
      pip3 install pyelftools sphinx > "$log_file" > "$log_file" 2>&1
      /usr/bin/python3 -c "import importlib.util; import sys; from elftools.elf.elffile import ELFFile" > "$log_file" 2>&1
      ln -s "$kernel_src_path"/ /usr/src/linux 2>/dev/null
      if [ ! -d "/usr/src/linux" ]; then
        echo log_console_and_file "Failed create link /usr/src/linux to a current kernel source."
      fi
      ldconfig; ldconfig /usr/local/lib
      log_console_and_file "DPDK meson dir $meson_build_dir as build staging. target /lib/modules/$target_system"
      cd "$build_dir" || exit
      if is_yes "$IS_INTERACTIVE"; then
        meson setup "$build_flags" -Dkernel_dir="$kernel_src_path" build
        local choice
        read -r -p "Building DPDK build location $meson_build_dir number of concurrent make: 8 (y/n)?" choice
        case "$choice" in
        y | Y)  ;;
        n | N) return 1 ;;
        *) echo "invalid" ;;
        esac
      else
        meson setup "$build_flags" -Dkernel_dir="$kernel_src_path" build > "$log_file.meson.log" 2>&1
      fi

      # meson -Dplatform=native -Dexamples=all -Denable_kmods=true -Dkernel_dir=/lib/modules/"$target_system" -Dibverbs_link=shared -Dwerror=true build > "$log_file.meson.log" 2>&1
      if is_yes "$IS_INTERACTIVE"; then
          cd "$meson_build_dir" || exit; ninja -j 8 > "$log_file.build.log" 2>&1
      else
          cd "$meson_build_dir" || exit; ninja -j 8 > "$log_file.build.log" 2>&1
      fi
      log_console_and_file "Finished building DPDK."
      ninja install > "$log_file.install.log" 2>&1
      log_console_and_file "Installing DPDK."
      ldconfig; ldconfig /usr/local/lib
    fi
}

# Functions load vfio and vfio_pci
function load_vfio_pci() {

    if is_yes "$IS_INTERACTIVE"; then
      local choice
      read -r -p "Load vfio and adjusting /etc/modules-load.d (y/n)?" choice
      case "$choice" in
      y | Y)  ;;
      n | N) return 1 ;;
      *) echo "invalid" ;;
      esac
  fi

  if [ -z "$LOAD_VFIO" ] || [ "$LOAD_VFIO" == "no" ]; then
    log_console_and_file "Skipping QAT phase."
  else
    log_console_and_file "Loading vfio and vfio_pci."

    # adjust config and load VFIO
    local MODULES_VFIO_PCI_FILE='/etc/modules-load.d/vfio-pci.conf'
    local MODULES_VFIO_FILE='/etc/modules-load.d/vfio.conf'

    mkdir -p /etc/modules-load.d 2>/dev/null
    if [[ ! -e $MODULES_VFIO_PCI_FILE ]]; then
      touch $MODULES_VFIO_PCI_FILE 2>/dev/null
    fi

    if [[ ! -e $MODULES_VFIO_FILE ]]; then
      touch $MODULES_VFIO_FILE 2>/dev/null
    fi

    local MODULES_VFIO_PCI_LINE='vfio-pci'
    local MODULES_VFIO_PCI_FILE='/etc/modules-load.d/vfio-pci.conf'
    grep -qF -- "$MODULES_VFIO_PCI_LINE" "$MODULES_VFIO_PCI_FILE" || echo "$MODULES_VFIO_PCI_LINE" >>"$MODULES_VFIO_PCI_FILE"

    local MODULES_VFIO_LINE='vfio'
    local MODULES_VFIO_FILE='/etc/modules-load.d/vfio.conf'
    grep -qF -- "$MODULES_VFIO_LINE" "$MODULES_VFIO_FILE" || echo "$MODULES_VFIO_LINE" >>"$MODULES_VFIO_FILE"
  fi
}

# Generate tuned bash script
function generate_tuned_script() {
  cat >/usr/lib/tuned/mus_rt/script.sh <<'EOF'
#!/bin/sh
. /usr/lib/tuned/functions
start() {
return 0
}
stop() {
return 0
}
verify() {
    retval=0
    if [ "$TUNED_isolated_cores" ]; then
        tuna -c "$TUNED_isolated_cores" -P > /dev/null 2>&1
        retval=$?
    fi
    return $retval
}
process $@
EOF
}


# Function fix tuned and some build in, generate a new tuned profile
# updates tuned python and make it active.
function build_tuned() {

   if is_yes "$IS_INTERACTIVE"; then
      local choice
      read -r -p "Build tuned profile (y/n)?" choice
      case "$choice" in
      y | Y) ;;
      n | N) return 1 ;;
      *) echo "invalid" ;;
      esac
  fi

  local log_file=$1
  touch "$log_file" 2>/dev/null
  #### create tuned profile.
  if [ -z "$BUILD_TUNED" ] && [ "$BUILD_TUNED" == "yes" ]; then
    log_console_and_file "Skipping tuned optimization."
  else
    rm -rf $ROOT_BUILD/tuned 2>/dev/null
    mkdir -p $ROOT_BUILD/tuned 2>/dev/null
    if [ -d "/git_images" ]; then
        local tuned_tar_file=$DEFAULT_GIT_IMAGE_DIR/tuned.tar.gz
        if file_exists $tuned_tar_file; then
          log_console_and_file "Unpacking tuned lib from a local copy."
          tar xfz $DEFAULT_GIT_IMAGE_DIR/tuned.tar.gz --warning=no-timestamp -C $ROOT_BUILD
        else
          log_console_and_file "Cloning tuned form remote repo."
          cd $ROOT_BUILD || exit; git clone "$TUNED_LOCATION" > "$log_file" 2>&1; cd tuned || exit;
        fi
    else
      log_console_and_file "Cloning tuned form remote repo."
      cd $ROOT_BUILD || exit; git clone "$TUNED_LOCATION" > "$log_file" 2>&1; cd tuned || exit;
    fi

    yum install grub2
    cp $ROOT_BUILD/tuned/92-tuned.install /usr/lib/kernel/install.d/92-tuned.install
    cp $ROOT_BUILD/tuned/00_tuned /etc/grub.d/00_tuned
    chmod 755 /etc/grub.d/00_tuned
    cp -Rf tuned /usr/lib/python3.10/site-packages
    # profile
    mkdir -p /usr/lib/tuned/mus_rt 2>/dev/null
    # create vars
    rm /etc/tuned/realtime-variables.conf 2>/dev/null
    touch /etc/tuned/realtime-variables.conf 2>/dev/null
    cat >/etc/tuned/realtime-variables.conf <<'EOF'
  isolated_cores=${f:calc_isolated_cores:2}
  isolate_managed_irq=Y
EOF
  # create profile
    rm /usr/lib/tuned/mus_rt/tuned.conf 2>/dev/null
    touch /usr/lib/tuned/mus_rt/tuned.conf 2>/dev/null
    log_console_and_file "Generating tuned.conf config."
    cat >/usr/lib/tuned/mus_rt/tuned.conf <<'EOF'
[main]
summary=Optimize for realtime workloads
include = network-latency
[variables]
include = /etc/tuned/realtime-variables.conf
isolated_cores_assert_check = \\${isolated_cores}
isolated_cores = ${isolated_cores}
not_isolated_cpumask = ${f:cpulist2hex_invert:${isolated_cores}}
isolated_cores_expanded=${f:cpulist_unpack:${isolated_cores}}
isolated_cpumask=${f:cpulist2hex:${isolated_cores_expanded}}
isolated_cores_online_expanded=${f:cpulist_online:${isolated_cores}}
isolate_managed_irq = ${isolate_managed_irq}
managed_irq=${f:regex_search_ternary:${isolate_managed_irq}:\b[y,Y,1,t,T]\b:managed_irq,domain,:}
[net]
channels=combined ${f:check_net_queue_count:${netdev_queue_count}}
[sysctl]
kernel.hung_task_timeout_secs = 600
kernel.nmi_watchdog = 0
kernel.sched_rt_runtime_us = -1
vm.stat_interval = 10
kernel.timer_migration = 0
net.ipv4.conf.all.rp_filter=2
[sysfs]
/sys/bus/workqueue/devices/writeback/cpumask = ${not_isolated_cpumask}
/sys/devices/virtual/workqueue/cpumask = ${not_isolated_cpumask}
/sys/devices/virtual/workqueue/*/cpumask = ${not_isolated_cpumask}
/sys/devices/system/machinecheck/machinecheck*/ignore_ce = 1
[bootloader]
cmdline_realtime=+isolcpus=${managed_irq}${isolated_cores} intel_pstate=disable intel_iommu=on iommu=pt nosoftlockup tsc=reliable transparent_hugepage=never hugepages=16 default_hugepagesz=1G hugepagesz=1G nohz_full=${isolated_cores} rcu_nocbs=${isolated_cores}
[irqbalance]
banned_cpus=${isolated_cores}
[script]
script = ${i:PROFILE_DIR}/script.sh
[scheduler]
isolated_cores=${isolated_cores}
[rtentsk]
EOF

    # create script used for a tuned.
    rm /usr/lib/tuned/mus_rt/script.sh 2>/dev/null
    touch /usr/lib/tuned/mus_rt/script.sh 2>/dev/null
    log_console_and_file "Generating tuned script.sh."
    generate_tuned_script
    chmod 755 /usr/lib/tuned/mus_rt/script.sh
    cd $ROOT_BUILD/tuned || exit; make PYTHON=/usr/bin/python3 install
    log_console_and_file "Enabling and restarting tuned."
    # enabled tuned and load profile we created.
    systemctl enable tuned
    systemctl daemon-reload
    systemctl start tuned
    log_console_and_file "Activating mus_rt profile."
    tuned-adm profile mus_rt
    systemctl status tuned
    systemctl restart tuned
  fi
}

# Function trims white spaces
trim() {
    local var="$*"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    echo "$var"
}

# Function enables Intel QAT.
function build_qat() {

   if is_yes "$IS_INTERACTIVE"; then
      local choice
      read -r -p "Loading QAT (y/n)?" choice
      case "$choice" in
      y | Y)  ;;
      n | N) return 1 ;;
      *) echo "invalid" ;;
      esac
  fi

  if [ -z "$WITH_QAT" ]; then
    log_console_and_file "Skipping QAT phase."
  else
    modprobe intel_qat
  fi
}

# Function builds huge pages
# First path to a log
# second num 2k pages
# third 1GB pages
function build_hugepages() {
  local log_file=$1
  local pages=${2:-0}
  local page_1gb=${3:-0}

  touch "$log_file" > /dev/null 2>&1
  if [ -z "$BUILD_HUGEPAGES" ] && [ "$BUILD_HUGEPAGES" == "yes" ]
  then
      log_console_and_file "Skipping hugepages allocation."
      return
  fi

  log_console_and_file "Installing libhugetlbfs and libhugetlbfs-devel packages"
  yum install libhugetlbfs libhugetlbfs-devel > /dev/null 2>&1

  # Check if 1GB pages are defined
  if [ -z "$pages_1gb" ]
  then
      log_console_and_file "Skipping hugepages allocation. 1GB pages not defined."
      return
  fi

  # Huge pages for each NUMA NODE
  log_console_and_file "Adjusting numa pages."
  local IS_SINGLE_NUMA
  IS_SINGLE_NUMA=$(numactl --hardware | grep available | grep 0-1)

   if is_yes "$IS_INTERACTIVE"; then
      local choice
      read -r -p "Building huge 2048 $pages 1GB $page_1gb, pages detected $IS_SINGLE_NUMA (y/n)?" choice
      case "$choice" in
      y | Y)  ;;
      n | N) return 1 ;;
      *) echo "invalid" ;;
      esac
  fi

  # Huge pages for each NUMA NODE
  log_console_and_file "Adjusting numa pages."
  local IS_SINGLE_NUMA
  IS_SINGLE_NUMA=$(numactl --hardware | grep available | grep 0-1)
  if [ -z "$IS_SINGLE_NUMA" ]
  then
          log_console_and_file "Target system with single socket num 2k $PAGES num 1GB $PAGES_1GB."
          echo "$pages" > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages
          echo "$page_1gb" > /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages
  else
          log_console_and_file "Target system with dual socket num 2k $PAGES num 1GB $PAGES_1GB."
          echo "$pages" > /sys/devices/system/node/node0/hugepages/hugepages-2048kB/nr_hugepages
          echo "$pages" > /sys/devices/system/node/node1/hugepages/hugepages-2048kB/nr_hugepages
          echo "$page_1gb"  > /sys/devices/system/node/node0/hugepages/hugepages-1048576kB/nr_hugepages
          echo "$page_1gb" > /sys/devices/system/node/node1/hugepages/hugepages-1048576kB/nr_hugepages
  fi
  log_console_and_file "Adjusting /etc/fstab mount hugetlbfs"
  local FSTAB_FILE='/etc/fstab'
  local HUGEPAGES_MOUNT_LINE='nodev /mnt/huge hugetlbfs pagesize=1GB 0 0'
  mkdir /mnt/huge > /dev/null 2>&1
  mount -t hugetlbfs nodev /mnt/huge > "$log_file" 2>&1
  grep -qF -- "$HUGEPAGES_MOUNT_LINE" "$FSTAB_FILE" || echo "$HUGEPAGES_MOUNT_LINE" >> "$FSTAB_FILE"
}

# mainly for debug to re-run during dev phase
function cleanup() {
    rm /build/*
    rm -rf $DPDK_TARGET_DIR_BUILD/build
    docker volume prune -f
}

## build configs for ptp
# and start ptp4l and phc2sys
# updater resolved from a PCI address.
function build_ptp() {
  local log_file=$1
  touch "$log_file" 2>/dev/null

  if [ "${BUILD_PTP:-no}" != "yes" ]; then
      log_console_and_file "Skipping ptp configuration."
      return 0
  fi

  if [ -z "$PTP_ADAPTER" ]; then
    log_console_and_file "Error: PTP_ADAPTER is undefined. Cannot configure PTP."
    return 1
  fi

  if is_yes "$IS_INTERACTIVE"; then
    local choice
    read -r -p "Building ptp configuration (y/n)?" choice
    case "$choice" in
    y | Y)  ;;
    n | N) return 1 ;;
    *) echo "invalid" ;;
    esac
  fi

  # enable ptp4l start and create config, restart.
  log_console_and_file "Enabling ptp4l ptp4l."
  systemctl enable ptp4l
  systemctl enable phc2sys
  systemctl daemon-reload
  systemctl start ptp4l
  systemctl start phc2sys
  systemctl ptp4l > "$log_file" 2>&1
  systemctl phc2sys > "$log_file" 2>&1

  # generate config.
  rm /etc/ptp4l.conf 2>/dev/null; touch /etc/ptp4l.conf 2>/dev/null
  echo "Adjusting ptp4l config /etc/ptp4l.conf" >> /build/build_ptp.log
  cat > /etc/ptp4l.conf  << 'EOF'
[global]
twoStepFlag		1
socket_priority		0
priority1		128
priority2		128
domainNumber		0
#utc_offset		37
clockClass		248
clockAccuracy		0xFE
offsetScaledLogVariance	0xFFFF
free_running		0
freq_est_interval	1
dscp_event		0
dscp_general		0
dataset_comparison	ieee1588
G.8275.defaultDS.localPriority	128
maxStepsRemoved		255
logAnnounceInterval	1
logSyncInterval		0
operLogSyncInterval	0
logMinDelayReqInterval	0
logMinPdelayReqInterval	0
operLogPdelayReqInterval 0
announceReceiptTimeout	3
syncReceiptTimeout	0
delayAsymmetry		0
fault_reset_interval	4
neighborPropDelayThresh	20000000
G.8275.portDS.localPriority	128
asCapable               auto
BMCA                    ptp
inhibit_announce        0
inhibit_delay_req       0
ignore_source_id        0
assume_two_step		0
logging_level		6
path_trace_enabled	0
follow_up_info		0
hybrid_e2e		0
inhibit_multicast_service	0
net_sync_monitor	0
tc_spanning_tree	0
tx_timestamp_timeout	10
unicast_listen		0
unicast_master_table	0
unicast_req_duration	3600
use_syslog		1
verbose			1
summary_interval	0
kernel_leap		1
check_fup_sync		0
pi_proportional_const	0.0
pi_integral_const	0.0
pi_proportional_scale	0.0
pi_proportional_exponent	-0.3
pi_proportional_norm_max	0.7
pi_integral_scale	0.0
pi_integral_exponent	0.4
pi_integral_norm_max	0.3
step_threshold		0.0
first_step_threshold	0.00002
max_frequency		900000000
clock_servo		pi
sanity_freq_limit	200000000
ntpshm_segment		0
msg_interval_request	0
servo_num_offset_values 10
servo_offset_threshold  0
write_phase_mode	0
# Transport options
transportSpecific	0x0
ptp_dst_mac		01:1B:19:00:00:00
p2p_dst_mac		01:80:C2:00:00:0E
udp_ttl			1
udp6_scope		0x0E
uds_address		/var/run/ptp4l
# Default interface options
clock_type		OC
network_transport	UDPv4
delay_mechanism		E2E
time_stamping		hardware
tsproc_mode		filter
delay_filter		moving_median
delay_filter_length	10
egressLatency		0
ingressLatency		0
boundary_clock_jbod	0
# Clock description
productDescription	;;
revisionData		;;
manufacturerIdentity	00:00:00
userDescription		;
timeSource		0xA0
EOF
  local ptp_adapter_name
  ptp_adapter_name=$(pci_to_adapter "$PTP_ADAPTER")
  # adjust /etc/sysconfig/ptp4l
  rm /etc/sysconfig/ptp4l 2>/dev/null; touch /etc/sysconfig/ptp4l 2>/dev/null
  log_console_and_file "Adjusting /etc/sysconfig/ptp4l and setting ptp for adapter $ptp_adapter_name"
  cat > /etc/sysconfig/ptp4l << EOF
OPTIONS="-f /etc/ptp4l.conf -i $PTP_ADAPTER"
EOF
  # restart everything.
  log_console_and_file "Restarting ptp4l "
  systemctl daemon-reload
  systemctl restart ptp4l
  systemctl restart phc2sys
  systemctl status ptp4l >> $BUILD_PIP_LOG
}

# Checks if required mandatory tools are installed on local system
#
# Arguments:
#   result_var_name: the name of the variable that will be set to the number of errors (e.g., "num_errors")
#   required_tools: an array of tool names that are required
#
# Returns:
#   Nothing. The function sets the value of the result_var_name variable to the number of errors.
function build_dirs() {
  mkdir -p $MLX_DIR > /dev/null 2>&1
  mkdir -p $INTEL_DIR > /dev/null 2>&1
  mkdir -p /build/ > /dev/null 2>&1
}

# Function checks if required mandatory
# tools installed on local system
function check_installed() {
  local  result_var_name=$1
  declare -i errors=0
  shift
  local array_tools=("$@")

  # the result_var_name argument must be a non-empty string,
  # and the required_tools array must not be empty.
  if [[ -z $result_var_name || $# -eq 0 ]]; then
      echo "Error: missing required arguments"
      return 1
  fi

  for tool in "${array_tools[@]}"
  do
    if is_cmd_installed "$tool"; then
      log_green_console_and_file "tools $tool installed."
    else
      log_console_and_file "tool $tool not installed."
      errors+=1
    fi
  done

  eval "$result_var_name"="'$errors'"
}

# Extracts the version number from a filename, URL, or full path
#
# Arguments:
#   file_path: the path to the file (e.g., "/mnt/cdrom/direct/dpdk-21.11.3.tar.xz")
#   pref: the prefix of the filename (e.g., "dpdk-")
#   suffix: the suffix of the filename (e.g., ".tar.xz")
#
# Returns:
#   the version number (e.g., "21.11.3")
function extrac_version() {
  local file_path=$1
  local pref=$2
  local suffix=$3
  local version
  version=""

  if [ -z "$file_path" ] || [ -z "$pref" ] || [ -z "$suffix" ]; then
    version=""
  else

#    # Extract the filename from the path
#    local filename=$(basename "$file_path")
#    local version=$(echo "$filename" | grep -oE "${prefix}[[:digit:].]+${suffix}" | grep -oE "[[:digit:].]+")

    file_path=$(trim "$file_path")
    local file_name
    file_name=$(basename "$file_path")
    version=${file_name/#$pref/}
    version=${version/%$suffix/}
  fi

  echo "$version"
}

# Searches for a file in an array of directories, or in the CD-ROM drive,
# or by performing a deep search of the file system
#
# Arguments:
#   search_pattern: a prefix for the file pattern (e.g., "dpdk-")
#   target_name: the target name of the file (e.g., "tar.gz")
#   suffix: a pattern to extract the version (e.g., ".*")
#   __resul_search_var: the name of a variable that the function will set if it finds the file
#   (optional) search_name: the name of the file to search for (for logging purposes)
#
# Returns:
#   0 if the file is found and the variable is set, 1 otherwise
function search_file() {
  local search_pattern=$1
  local target_name=$2
  local suffix=$3
  local  __resul_search_var=$4
  local found_file=""
  local found_in=""
  local found=false

  if [[ -z $search_pattern || -z $target_name || -z $suffix || -z $__resul_search_var ]]; then
      echo "Error: missing required arguments"
      return 1
  fi

  log_console_and_file "Searching search_pattern $search_pattern target_name $target_name suffix $suffix"
  # first check all expected dirs
  for expected_dir in "${EXPECTED_DIRS[@]}"; do
    log_console_and_file "Searching $target_name in $expected_dir"
    found_file=$(ls "$expected_dir" 2>/dev/null | grep "$search_pattern*")
    if [ -n "$found_file" ]; then
      found_in=$expected_dir/$found_file
      log_console_and_file "Found $target_name in $found_in"
      eval "$__resul_search_var"="$found_in"
      found=true
      return 0
    fi
  done

  # if not found in expect location, mount cdrom and check
  # in /direct dir
  if [ -z "$found_in" ] || [ "$found" = false ]; then
    log_console_and_file "Mounting cdrom and searching a $target_name"
    mount /dev/cdrom 2>/dev/null
    found_file=$(ls /mnt/cdrom/direct 2>/dev/null | grep "$search_pattern*")
    if [ -n "$found_file" ]; then
      log_console_and_file "File found in local cdrom $found_file"
      found_in="/mnt/cdrom/direct"/$found_file
      eval "$__resul_search_var"="$found_in"
      found=true
      return 0
    fi
  fi

  # if we didn't found do a deep search
  if [ -z "$found_in" ] || [ "$found" = false ]; then
    local search_regex
    search_regex=".*$search_pattern.*.$suffix"
    log_console_and_file "File not found, doing deep search pattern $search_regex"
    found_file="$(cd / || exit; find / -type f -regex "$search_regex" -maxdepth 10 2>/dev/null | head -n 1)"
    log_console_and_file "Result of deep search $found_file"
  fi

  if file_exists "$found_file"; then
    log_console_and_file "Deep search found a file $found_file"
  fi

  if [[ "$__resul_search_var" ]]; then
    eval "$__resul_search_var"="'$found_file'"
  else
    echo "$found_file"
  fi
}

# Function takes target dir where to store a file
# and list of location mirror for a given file.
function fetch_file() {
  local target_dir=$1
  local  __result_fetch_var=$2
  shift 2
  local urls=("$@")
  local remote_file_name
  local full_path

  if [ ! -d target_dir ]; then
    mkdir -p "$target_dir"
  fi

  log_console_and_file "File will be saved in $target_dir"

  for url in "${urls[@]}"; do
    remote_file_name=$(extrac_filename "$url")
    log_console_and_file "Fetching file $remote_file_name from $url"
    full_path=$target_dir"/"$remote_file_name
    wget --quiet -nc "$url" -O "$remote_file_name" || rm -f "$remote_file_name"
    if file_exists "$remote_file_name"; then
      log_console_and_file "Downloaded file to $remote_file_name"
      break
    else
      log_console_and_file "Failed to fetch $remote_file_name from $url"
    fi
  done

  if file_exists "$remote_file_name"; then
    log_console_and_file "Copy file to $remote_file_name to $full_path"
    cp "$remote_file_name" "$full_path"
  fi

  if [[ "$__result_fetch_var" ]]; then
    eval $__result_fetch_var="'$full_path'"
  else
    echo "$full_path"
  fi
}

# Generates a DHCP network configuration file for Ethernet adapters that match a given mask
#
# Arguments:
#   eth_mask (optional): the Ethernet adapter mask (default: "e*")
#
# Returns:
#   0 if successful, 1 if an error occurred
function generate_dhcp_network() {
  local eth_mask=$1
  local default_mask="e*"
  if [ -z "$eth_mask" ]; then
    eth_mask=$default_mask
  fi

  if ! mkdir -p "$DEFAULT_SYSTEMD_PATH"; then
      echo "Error: could not create directory $DEFAULT_SYSTEMD_PATH"
      return 1
  fi

    # Write the network configuration file
    if ! cat >"$DEFAULT_SYSTEMD_PATH/$DEFAULT_DHCP_NET_NAME" <<EOF
[Match]
Name=$eth_mask
[Network]
DHCP=yes
IPv6AcceptRA=no
EOF
    then
        echo "Error: could not write to $DEFAULT_SYSTEMD_PATH/$DEFAULT_DHCP_NET_NAME"
        return 1
    fi
    return 0
}

# Returns 0 if the specified string is a valid IPv4 address, 1 otherwise
function valid_ipv4_address() {
    local address=$1
    local octet

    # Split the address into four octets
    IFS='.' read -r -a octets <<< "$address"

    # Check that the address has four octets
    if [[ ${#octets[@]} -ne 4 ]]; then
        return 1
    fi

    # Check that each octet is a number between 0 and 255
    for octet in "${octets[@]}"; do
        if ! [[ $octet =~ ^[0-9]+$ ]]; then
            return 1
        fi
        if (( $octet < 0 || $octet > 255 )); then
            return 1
        fi
    done

    # If we made it this far, the address is valid
    return 0
}

# Generates a static network configuration file for a specified Ethernet adapter
#
# Arguments:
#   adapter_name: the name of the Ethernet adapter
#   address: the static IP address
#   gateway: the gateway IP address
#   dns: the DNS server IP address
#
# Returns:
#   0 if successful, 1 if an error occurred
function generate_static_network() {
    local adapter_name=$1
    local address=$2
    local gateway=$3
    local dns=$4

    # Validate input: all arguments must be provided
    if [[ -z $adapter_name || -z $address || -z $gateway || -z $dns ]]; then
        echo "Error: all arguments must be provided"
        return 1
    fi

    # Validate input: IP address, gateway, and DNS server must be valid IPv4 addresses
    if ! valid_ipv4_address "$address"; then
        echo "Error: $address is not a valid IPv4 address"
        return 1
    fi

    if ! valid_ipv4_address "$gateway"; then
        echo "Error: $gateway is not a valid IPv4 address"
        return 1
    fi

    if ! valid_ipv4_address "$dns"; then
        echo "Error: $dns is not a valid IPv4 address"
        return 1
    fi

    # Check if the network configuration file already exists
    if [[ -e "$DEFAULT_SYSTEMD_PATH/$DEFAULT_SYSTEMD_STATIC_NET_NAME_PREFIX-$adapter_name.network" ]]; then
        echo "Error: $DEFAULT_SYSTEMD_PATH/$DEFAULT_SYSTEMD_STATIC_NET_NAME_PREFIX-$adapter_name.network already exists"
        return 1
    fi

    # Write the network configuration file
    if ! cat >"$DEFAULT_SYSTEMD_PATH/$DEFAULT_SYSTEMD_STATIC_NET_NAME_PREFIX-$adapter_name.network" <<EOF
[Match]
Name=$adapter_name
[Network]
Address=$address
Gateway=$gateway
DNS=$dns
EOF
    then
        echo "Error: could not write to $DEFAULT_SYSTEMD_PATH/$DEFAULT_SYSTEMD_STATIC_NET_NAME_PREFIX-$adapter_name.network"
        return 1
    fi
    # Return success
    return 0
}

# Function generate default networks.
# generate_dhcp_network generate default DHCP network.
# if static required it will also generate static.
function generate_default_network() {
  # generate default dhcp network
  if is_yes "$IS_INTERACTIVE"; then
    local choice
    read -r -p "Building default DHCP and static network (y/n)?" choice
    case "$choice" in
    y | Y)  ;;
    n | N) return 1 ;;
    *) echo "invalid" ;;
    esac
  fi

  if is_yes "$BUILD_DEFAULT_NETWORK"; then
    log_console_and_file "Generating default dhcp network"
    generate_dhcp_network "e*"
  fi
  # generate all static networks
  if is_yes $BUILD_STATIC_ADDRESS; then
    if is_not_empty $STATIC_ETHn_NAME &&
      is_not_empty $STATIC_ETHn_ADDRESS &&
      is_not_empty $STATIC_ETHn_GATEWAY &&
      is_not_empty $STATIC_ETHn_STATIC_DNS; then
      log_console_and_file "Generating static network for $STATIC_ETHn_NAME"
      generate_static_network "$STATIC_ETHn_NAME" \
        "$STATIC_ETHn_ADDRESS" \
        "$STATIC_ETHn_GATEWAY" \
        "$STATIC_ETHn_STATIC_DNS"
    fi
  fi
}

# Generates a .netdev file for a VLAN with a specified ID
#
# Arguments:
#   vlan_id: the VLAN ID (an integer)
#
# Returns:
#   0 if successful, 1 if an error occurred
function generate_vlan_netdev() {
  local vlan_id=$1
  if ! [[ $vlan_id =~ ^[0-9]+$ ]]; then
    echo "Error: vlan_id must be a valid integer"
    return 1
  fi
  # Check if the .netdev file already exists
  if [[ -e "$DEFAULT_SYSTEMD_PATH/$DOT1Q_SYSTEMD_DEFAULT_PREFIX$vlan_id.netdev" ]]; then
      echo "Error: $DEFAULT_SYSTEMD_PATH/$DOT1Q_SYSTEMD_DEFAULT_PREFIX$vlan_id.netdev already exists"
      return 1
  fi

  # Write the .netdev file
  if ! cat >"$DEFAULT_SYSTEMD_PATH/$DOT1Q_SYSTEMD_DEFAULT_PREFIX$vlan_id.netdev" <<EOF
[NetDev]
Name=VLAN$vlan_id
Kind=vlan
[VLAN]
Id=$vlan_id
EOF
    then
        echo "Error: could not write to $DEFAULT_SYSTEMD_PATH/$DOT1Q_SYSTEMD_DEFAULT_PREFIX$vlan_id.netdev"
        return 1
    fi
  return 0
}

# Generates a Photon OS kernel config file with custom parameters
# The function finds the CPUs in NUMA node 0, removes a set of CPUs
# from the list, and generates a new line with the remaining CPUs
# and other parameters. It mainly for a case when tuned is broken
# and we manually pass all value.
#
# Arguments:
#   config_file (optional): filename of the config file to be generated (default: photon.cfg2)
#
# Returns:
#   0 if successful, 1 if an error occurred
function generate_manual_photon_config() {
    local config_file=${1:-photon.cfg2}

    # Check if numactl command is available
    if ! command -v numactl > /dev/null 2>&1; then
        echo "Error: numactl command not found"
        return 1
    fi

    # Find CPUs in NUMA node 0
    local node_numa0=$(numactl --hardware | grep "node 0" | grep cpus | cut -d ":" -f 2)
    # Find CPUs in NUMA node 1
    local node_numa1=$(numactl --hardware | grep "node 0" | grep cpus | cut -d ":" -f 2)
    declare -a list=( "$node_numa0" )

    # Remove specified CPUs from the list
    declare delete=(0 1 2 3)
    for del in "${delete[@]}"
    do
        list=("${list[@]/$del}")
    done

    # check if list array is not empty
    if [ -z "${list[*]}" ]; then
        echo "Error: list array is empty"
        return 1
    fi

    # Replace a specific line in the config file with a new line containing the list array and other parameters
    if ! sed -i -r \
    "s/^tuned_params=.*/tuned_params=\
    skew_tick=1 \
    isolcpus=managed_irq,domain, \
    isolcpus=managed_irq,domain,${list[*]} \
    intel_pstate=disable \
    intel_iommu=on \
    iommu=pt \
    nosoftlockup \
    tsc=reliable \
    transparent_hugepage=never \
    hugepages=16 \
    default_hugepagesz=1G \
    hugepagesz=1G \
    nohz_full=${list[*]} \
    rcu_nocbs=${list[*]}/"\
    "${config_file}"
    then
      echo "Error: sed command failed"
      return 1
    fi

    # Return success
    return 0
}


function generate_docker_config() {
  cat >"/usr/lib/systemd/system/docker.service" <<EOF
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target containerd.service
Wants=network-online.target
Requires=docker.socket containerd.service
[Service]
Type=notify
ExecStart=taskset -c 5-27 /usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock
ExecReload=/bin/kill -s HUP $MAINPID
TimeoutSec=0
RestartSec=2
Restart=always
StartLimitBurst=3
StartLimitInterval=60s
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
Delegate=yes
KillMode=process
[Install]
WantedBy=multi-user.target
EOF
}

function generate_vlan_network() {
  local vlan_id=$1
  if is_not_empty vlan_id; then
    log_console_and_file "Generating $DEFAULT_SYSTEMD_PATH/$DOT1Q_SYSTEMD_DEFAULT_PREFIX$vlan_id.network"
    cat >"$DEFAULT_SYSTEMD_PATH/$DOT1Q_SYSTEMD_DEFAULT_PREFIX$vlan_id.network" <<EOF
[Match]
Name=VLAN$vlan_id
Type=vlan
[Network]
Description=generated vlan config
[Address]
Address=DHCP
EOF
  fi
}

function generate_ether_adapter() {
  local trunk_eth_name=$1
  local lld=$2
  local emit_lld=$3
  if is_not_empty trunk_eth_name; then
    log_console_and_file "Generating $DEFAULT_SYSTEMD_PATH/00-$trunk_eth_name.network"
    cat >"$DEFAULT_SYSTEMD_PATH/00-$trunk_eth_name.network" <<EOF
[Match]
Name=$trunk_eth_name
Type=ether
[Network]
Description=physical ethernet device
LLDP=$lld
EmitLLDP=$emit_lld
EOF
  fi
}

# Function builds cycling test
# First arg a path to log file.
function build_cycling_test() {
    local log_file=$1
    local cycling_test_dir="$ROOT_BUILD/cycling_test"

    if [ -z "$BUILD_CYCLING_TEST" ] || [ "$BUILD_CYCLING_TEST" == "no" ]; then
        log_console_and_file "Skipping cycling test build."
    else
        log_console_and_file "Building cycling test."
        # Clone and build cycling test
        mkdir -p "$ROOT_BUILD" > /dev/null 2>&1
        cd "$ROOT_BUILD" || exit
        git clone git://git.kernel.org/pub/scm/linux/kernel/git/clrkwllms/rt-tests.git > "$log_file" 2>&1
        cd rt-tests/ || exit
        make > "$log_file" 2>&1
        make install > "$log_file" 2>&1

        mkdir -p "$cycling_test_dir" > /dev/null 2>&1
        ln -sf "$ROOT_BUILD"/rt-tests/cyclictest/cyclictest "$cycling_test_dir/cyclictest"
    fi
}

#
# Function create all vlan interface
#
function build_vlans_ifs() {
  local vlan_id_list="$1"
  local if_name="$2"

  if is_yes "$BUILD_TRUNK" && is_not_empty "$DOT1Q_VLAN_TRUNK_PCI"; then
    local trunk_eth_name
    trunk_eth_name=$(pci_to_adapter "$DOT1Q_VLAN_TRUNK_PCI")
    if [ -z "$trunk_eth_name" ]; then
      log_console_and_file "Failed resolve PCI $DOT1Q_VLAN_TRUNK_PCI address for vlan trunk."
      return 1
    fi

    if is_yes "$IS_INTERACTIVE"; then
      local choice
      read -r -p "Building trunk profile VLAN range $vlan_id_list adapter $trunk_eth_name (y/n)?" choice
      case "$choice" in
      y | Y)  ;;
      n | N) return 1 ;;
      *) echo "invalid" ;;
      esac
    fi

    local vlan_ids=""
    local separator=','
    IFS=$separator read -ra vlan_ids <<<"$vlan_id_list"
    # first for all VLANs we generate all netdev
    for vlan_id in "${vlan_ids[@]}"; do
      generate_vlan_netdev "$vlan_id"
    done
    # generate ether adapter with LLDP on or off etc.
    generate_ether_adapter "$trunk_eth_name" $LLDP $LLDP_EMIT
    IFS=$separator read -ra vlan_ids <<<"$vlan_id_list"
    for vlan_id in "${vlan_ids[@]}"; do
      echo "VLAN=VLAN$vlan_id" >> "$DEFAULT_SYSTEMD_PATH/00-$if_name.network"
    done
    IFS=$separator read -ra vlan_ids <<<"$vlan_id_list"
    for vlan_id in "${vlan_ids[@]}"; do
      generate_vlan_network "$vlan_id"
      echo "VLAN=VLAN$vlan_id" >> "$DEFAULT_SYSTEMD_PATH/00-$if_name.network"
    done
  fi


  if is_yes "$IS_INTERACTIVE"; then
    local choice
    read -r -p "Restarting networkd (y/n)?" choice
    case "$choice" in
    y | Y)  ;;
    n | N) return 1 ;;
    *) echo "invalid" ;;
    esac
  fi

  systemctl restart systemd-networkd
}


# The function search each required package by default;
# all offline are in /direct directory.
# It created during first boot.
# This function uses function search_file to locate each respected file required.
# i.e., it first checks /direct
# if not found mount cdrom ( after the first mount, it might un-mounted) search tar.gz , xy etc.
# in cdrom, if not, does a deep search with find --depth 6, if all failed poll from the internet.
# Unpack all files and return the build location.
# All drivers, git clone, etc., are moved by default to $BUILD_ROOT
# i.e /root/build.
function unpack_all_files() {
  local search_criterion=$1
  local file_name=$2
  local suffix=$3
  local  __result_loc_var=$4
  shift 4
  local mirrors=("$@")
  local build_location=$ROOT_BUILD/$file_name
  local search_result
  search_file "$search_criterion" "$file_name" "$suffix" search_result
  if file_exists "$search_result"; then
    log_console_and_file "* Found existing file $search_result"
    log_console_and_file ""
    mkdir -p "$build_location"
    tar -xf "$search_result" --directory "$build_location" --strip-components=1
  else
    local download_result=""
    log_console_and_file "File not found need downloading $file_name"
    fetch_file $ROOT_BUILD download_result "${mirrors[@]}"
    if file_exists "$download_result"; then
      log_console_and_file "* File successfully downloaded $file_name location $download_result"
      log_console_and_file ""
      mkdir -p "$build_location"
      tar -xf "$download_result" --directory "$build_location" --strip-components=1
    fi
  fi

  if [[ "$__result_loc_var" ]]; then
    eval "$__result_loc_var"="'$build_location'"
  else
    echo "$build_location"
  fi
}

# Function cleanup.
# it will clean build , logs and all tar.gz copied.
# This mainly useful if you run post manually.
# or during dev stage for unit testing.
function clean_up() {
  if is_yes $DO_FULL_CLEANUP; then
    log_console_and_file "Performing full clean"
    rm -rf "${ROOT_BUILD:?}/"*
    rm -rf "${BUILD_LOG:?}/"*
  fi
}


function print_build_spec() {
  echo "----------------------* build spec  *----------------------------"
  echo "AVX_VERSION $AVX_VERSION"
  echo "AVX_VERSION $MLNX_VER"
  echo "DOCKER_IMAGE $DOCKER_IMAGE_PATH"
  echo "DOCKER_IMAGE_PATH $DOCKER_IMAGE_NAME"
  echo "ROOT BUILD DIR $ROOT_BUILD"
  echo "build mellanox $MLX_BUILD"
  echo "build intel $INTEL_BUILD"
  echo "build ipsec $IPSEC_BUILD"
  echo "build DPDK $DPDK_BUILD"
  echo "build lib isa $LIBNL_ISA"
  echo "build lib nl $LIBNL_ISA"
  echo "build tuned profile $BUILD_TUNED"
  echo "build sriov adapter $BUILD_SRIOV"
  echo "build trunk adapter $BUILD_TRUNK"
  echo "build default networks $BUILD_DEFAULT_NETWORK"
  echo "build static networks $BUILD_STATIC_ADDRESS"
  echo "enable QAT $WITH_QAT"
  echo "load vfio $LOAD_VFIO"
  echo "skip clean up $DO_FULL_CLEANUP"
  echo "build docker images $BUILD_LOAD_DOCKER_IMAGE"
  echo "reboot post $DO_REBOOT"
  echo "----------------------* spec  *----------------------------"
  echo "Default location to check for docker images: $DEFAULT_GIT_IMAGE_DIR"
  echo "----------------------* network spec  *----------------------------"
  echo "SRIOV PCIs $SRIOV_PCI_LIST max vfs: $MAX_VFS_PER_PCI"
  echo "VLAN ranges $DOT1Q_VLAN_ID_LIST trunk pci address: $DOT1Q_VLAN_TRUNK_PCI"
  echo "enable LLDP on trunk $LLDP emit LLDP $LLDP_EMIT"
  echo "Default systemd network prefix for files $DOT1Q_SYSTEMD_DEFAULT_PREFIX"
  echo "Default name for trunk $DOT1Q_ETH_NAME"
  echo "Default static network adapter $STATIC_ETHn_NAME address $STATIC_ETHn_ADDRESS gw $STATIC_ETHn_GATEWAY dns $STATIC_ETHn_STATIC_DNS"
  echo "----------------------* hugepages  *----------------------------"
  echo "Small pages $PAGES"
  echo "1GB pages $PAGES_1GB"
  echo "----------------------* ptp  *----------------------------"
  echo "ptp adapter pci $PTP_ADAPTER"
}

# Function clean only logs and build dir.
function clean_build_only() {
  rm -rf "${ROOT_BUILD:?}/"*
  rm -rf "${BUILD_LOG:?}/"*
}

function check_all_vars() {
  SRIOV_PCI_LIST=$(remove_all_spaces "$SRIOV_PCI_LIST")
  DOT1Q_VLAN_ID_LIST=$(remove_all_spaces "$DOT1Q_VLAN_ID_LIST")
  MAX_VFS_PER_PCI=$(remove_all_spaces "$MAX_VFS_PER_PCI")
  AVX_VERSION=$(remove_all_spaces "$AVX_VERSION")
  MLNX_VER=$(remove_all_spaces "$MLNX_VER")
  DOCKER_IMAGE_PATH=$(remove_all_spaces "$DOCKER_IMAGE_PATH")
  PAGES=$(remove_all_spaces "$PAGES")
}

# Main entry for a script
function main() {

  check_all_vars
  mount /dev/cdrom > /mount.log > /dev/null 2>&1
  mkdir -p /build/ > /dev/null 2>&1
  ls -l /mnt/cdrom > /ls_cdrom_media.log
  ls -l /boot > /ls_boot.log

  mkdir -p $DEFAULT_DIRECT_RPMS; cp -uv /mnt/cdrom/direct_rpms/*.rpm /direct_rpms > /copy_cdrom_direct_rpm.log
  mkdir -p $DEFAULT_DIRECT; cp -uv /mnt/cdrom/direct/* $DEFAULT_DIRECT > /copy_cdrom_direct.log
  mkdir -p $DEFAULT_GIT_IMAGE_DIR; cp -uv /mnt/cdrom/git_images/* $DEFAULT_GIT_IMAGE_DIR > /copy_cdrom_git_images.log

  local log_main_dir
  log_main_dir=$(dirname "$DEFAULT_BUILDER_LOG")
  # clear all logs and build
  clean_build_only
  create_log_dir "$DEFAULT_BUILDER_LOG"
  declare -i errs=0
  check_installed errs "${REQUIRED_TOOLS[@]}"
  if [[ $errs -gt 0 ]]; then
    echo "Please check required commands."
  fi

  # re-link kernel to current
  if is_yes "$BUILD_RE_LINK_KERNEL"; then
    link_kernel ""
  fi


  # install required packages
  if is_yes "$BUILD_INSTALL_PACKAGES"; then
    yum --quiet -y install python3-libcap-ng python3-devel \
    rdma-core-devel util-linux-devel \
      zip zlib zlib-devel libxml2-devel \
    libudev-devel &> /build/build_rpms_pull.log
    # installed.before and after our diff
    yum list installed > /installed.after.log
    rpm -qa > /rpm.installed.after.log
  fi

  build_dirs

  # all location updated
  local dpdk_build_location=""
  local iavf_build_location=""
  local libnl_build_location=""
  local mellanox_build_location=""

  # optional full clean-up
  clean_up

  # either fetch from local or remote
  unpack_all_files "dpdk" "$DPDK_VERSION" "tar.xz" dpdk_build_location "${DPDK_URL_LOCATIONS[@]}"
  unpack_all_files "iavf-$AVX_VERSION" "iavf-$AVX_VERSION" "tar.gz" iavf_build_location "${IAVF_LOCATION[@]}"
  unpack_all_files "libnl-3.2.25" "libnl-3.2.25" "tar.gz" libnl_build_location "${LIB_NL_LOCATION[@]}"
  unpack_all_files "MLNX_OFED_SRC" "MLNX_OFED_SRC-debian-$MLNX_VER" "tgz" mellanox_build_location "${MELLANOX_LOCATION[@]}"

  log_console_and_file "-DPDK Build location $dpdk_build_location"
  log_console_and_file "-IAVF Build location $iavf_build_location"
  log_console_and_file "-LIBNL Build location $libnl_build_location"
  log_console_and_file "-Mellanox Build location $mellanox_build_location"

  if file_exists "$DOCKER_IMAGE_PATH"; then
      log_console_and_file "-Resolved docker image at location $DOCKER_IMAGE_PATH"
  fi

  # if we do interactive.
  #  for example, we want run manually by hand post install.
  if is_yes "$IS_INTERACTIVE"; then
    print_build_spec

    local choice
    read -r -p "Please check and confirm (y/n)?" choice
    case "$choice" in
    y | Y)  ;;
    n | N) return 1 ;;
    *) echo "invalid" ;;
    esac
  fi

  if is_yes "$MLX_BUILD"; then
    log_console_and_file "Starting Building mellanox driver."
    build_mellanox_driver "$BUILD_MELLANOX_LOG" "$mellanox_build_location"
  fi
  if is_yes "$INTEL_BUILD"; then
    log_console_and_file "Stating building intel driver."
    build_intel_iavf "$BUILD_INTEL_LOG" "$iavf_build_location"
  fi
  if is_yes "$BUILD_LOAD_DOCKER_IMAGE"; then
    log_console_and_file "Loading docker images."
    build_docker_images $BUILD_DOCKER_LOG "$DOCKER_IMAGE_PATH" "$DOCKER_IMAGE_NAME"
  fi
  if is_yes "$BUILD_YASM"; then
      log_console_and_file "Building yasm."
      build_yasm "$BUILD_YASM_LOG"
  fi
  if is_yes "$IPSEC_BUILD"; then
    log_console_and_file "Starting building ipsec lib."
    build_ipsec_lib "$BUILD_IPSEC_LOG"
  fi
  adjust_shared_libs
  build_install_pips_deb "$BUILD_PIP_LOG" "${PIP_PKG_REQUIRED[@]}"
  if is_yes "$LIBNL_BUILD"; then
    build_lib_nl "$BUILD_NL_LOG" "$libnl_build_location"
  fi
  if is_yes "$LIBNL_ISA"; then
    build_lib_isa "$BUILD_ISA_LOG"
  fi
  if is_yes "$DPDK_BUILD"; then
    build_pyelf "$BUILD_PYELF_LOG"
    build_dpdk "$BUILD_DPDK_LOG" "$dpdk_build_location"
  fi
  if is_yes "$LOAD_VFIO"; then
      load_vfio_pci
  fi
  if is_yes "$BUILD_TUNED"; then
    build_tuned "$BUILD_TUNED_LOG"
  fi
  if is_yes "$BUILD_TRUNK"; then
    build_vlans_ifs "$DOT1Q_VLAN_ID_LIST" $DOT1Q_ETH_NAME
  fi
  if is_yes $WITH_QAT; then
    # optional steps
    build_qat
  fi
  if is_yes "$BUILD_SRIOV"; then
    log_console_and_file "Building SRIOV."
    enable_sriov "$SRIOV_PCI_LIST" "$MAX_VFS_PER_PCI"
  fi
  if is_yes "$BUILD_HUGEPAGES"; then
    log_console_and_file "Building hugepages."
    build_hugepages "$BUILD_HUGEPAGES_LOG" "$PAGES" "$PAGES_1GB"
  fi
  if is_yes "$BUILD_PTP"; then
      log_console_and_file "Building ptp configuration."
      build_ptp "$BUILD_PTP_BUILD_LOG"
  fi

  # generate default dhcp and if needed adapter with static
  # ip address
  generate_default_network

  # generate adapter
  build_vlans_ifs "$DOT1Q_VLAN_ID_LIST" "$DOT1Q_VLAN_TRUNK_PCI"


  if is_cdrom_mounted "cdrom"; then
    umount /dev/cdrom
  fi

  if generate_manual_photon_config "/boot/photon.cfg2"; then
    echo "Config file generated successfully"
  else
    echo "Error generating config file"
  fi

  if is_yes "$DO_REBOOT"; then
    reboot
  fi
}

main