#!/bin/bash
# This mandatory shared vars.  Please don't change.
# spyroot@gmail.com
# Author Mustafa Bayramov

DEFAULT_BUILD_TYPE="offline_testnf_os4_flex21"
# offline
if [ -z "$BUILD_TYPE" ]; then
  export BUILD_TYPE=$DEFAULT_BUILD_TYPE
fi

# all direct rpms will download and stored in direct_rpms
DEFAULT_RPM_DIR="direct_rpms"
# all cloned and tar.gzed repos in git_repos
DEFAULT_GIT_DIR="git_images"
# all downloaded tar.gz ( drivers and other arc) will be in direct.
DEFAULT_ARC_DIR="direct"
# DEFAULT WEB DIR
DEFAULT_WEB_DIR="/var/www/html/"

# default location for spec folder
DEFAULT_SPEC_FOLDER="specs"
# default location for docker images
DEFAULT_DOCKER_IMAGES="docker_images"
# this directory will be created inside ISO
DEFAULT_RPM_DST_DIR="direct_rpms"
# this directory will be created inside ISO
DEFAULT_GIT_DST_DIR="git_images"
# this directory will be created inside ISO
DEFAULT_ARC_DST_DIR="direct"
# default overwrite file we copy to ISO
DEFAULT_OVERWRITE_FILE="overwrite.env"
# default post.
DEFAULT_POST_SH="post.sh"

#
DPDK_VER="21.11.3"
AVX_VERSION=4.5.3

#
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0m;34m'
PURPLE='\033[0m;35m'
CYAN='\033[0m;36m'
NC='\033[0m'

# bold
BBlack="\[\033[1;30m\]"       # Black
BRed="\[\033[1;31m\]"         # Red
BGreen="\[\033[1;32m\]"       # Green
BYellow="\[\033[1;33m\]"      # Yellow
BBlue="\[\033[1;34m\]"        # Blue
BPurple="\[\033[1;35m\]"      # Purple
BCyan="\[\033[1;36m\]"        # Cyan
BWhite="\[\033[1;37m\]"       # White


if [ -z "$PHOTON_5_X86" ]
then
    echo "PHOTON_5_X86 $PHOTON_5_X86 is unset, target build photon 4"
    DEFAULT_SRC_IMAGE_NAME="ph4-rt-refresh.iso"
    DEFAULT_DST_IMAGE_NAME="ph4-rt-refresh_adj_$BUILD_TYPE.iso"
else
    echo "PHOTON_5_X86 is $PHOTON_5_X86 is set, target build photon 5"
    DEFAULT_SRC_IMAGE_NAME="ph5-rt-refresh.iso"
    DEFAULT_DST_IMAGE_NAME="ph5-rt-refresh_adj_$BUILD_TYPE.iso"
fi

DO_CLEAN_UP_ONLY="no"

function log_error() {
  printf "%b %s %b\n" "${RED}" "$@" "${NC}"
}

function print_value_green() {
  local prefix_text=$1
  shift 1
  printf "%-5s %b %s %b\n" "$prefix_text" "${GREEN}" "$@" "${NC}"
}

# Function print msg expected value and current value
# first arg is msg , second current value, last arg expected.
function print_expected_green() {
  local msg=$1
  local value_a=$2
  local value_b=$3
  printf "%-5s %b %s %b expected %b %s %b\n" "$msg" "${GREEN}" "$value_a" "${NC}" "${GREEN}" "$value_b" "${NC}"
}

function print_expected_red() {
  local msg=$1
  local value_a=$2
  local value_b=$3
  printf "%-5s %b %s %b expected %b %s %b\n" "$msg" "${GREEN}" "$value_a" "${NC}" "${RED}" "$value_b" "${NC}"
}


function log_info() {
  printf "%b %s. %b\n" "${BLUE}" "$@" "${NC}"
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

# Function checks if string contains yes or not
function is_no() {
  local var=$1
  if [[ -z "$var" ]]; then
    return 1
  else
    if [ "$var" == "no" ]; then
      return 0
    else
      return 1
    fi
  fi
}

function is_cdrom_connected() {
  local var=$1
  if [[ -z "$var" ]]; then
    return 1
  else
    if [ "$var" == "False" ]; then
      return 0
    else
      return 1
    fi
  fi
}

function is_enabled() {
  local var=$1
  if [[ -z "$var" ]]; then
    return 1
  else
    if [ "$var" == "Enabled" ]; then
      return 0
    else
      return 1
    fi
  fi
}

function is_disabled() {
  local var=$1
  if [[ -z "$var" ]]; then
    return 1
  else
    if [ "$var" == "Disabled" ]; then
      return 0
    else
      return 1
    fi
  fi
}
function dir_exists() {
  local -r a_dir="$1"
  [[ -d "$a_dir" ]]
}

function file_exists() {
  local -r a_file="$1"
  [[ -f "$a_file" ]]
}
