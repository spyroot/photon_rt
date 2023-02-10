#!/bin/bash
# This scripts bare-metal installer.
# source should have following.
# comma separated list of IPS in the env.
#example:
#
# Before you boot.  note if DRAC has pending changes that requires reboot.
# you need reboot host first or clear all pending changes.
#
# The post script will re-adjust all SRIOV based on spec.
# By default, Sriov disabled on Dell servers.
#
# Secondly we want to minimum optimization for
# a server for real-time.
#
# we can check what scheduled / completed etc / check manual, it will be scheduled
# export IDRAC_IP="$addr"; idrac_ctl --json_only --debug --verbose jobs --scheduled
# more details verbose mode
# export IDRAC_IP="$addr"; idrac_ctl --verbose --debug bios-change  --attr_name MemTest,SriovGlobalEnable,OsWatchdogTimer,ProcTurboMode,ProcCStates,MemFrequency --attr_value Disabled,Enabled,Disabled,Disabled,Enabled,Disabled,MaxPerf on-reset -r
# idrac_ctl bios --attr_only --filter SriovGlobalEnable
# Example what you should have in env.
#export IDRAC_IPS="192.168.1.1,192.168.1.2"
#export IDRAC_PASSWORD="password"
#export IDRAC_USERNAME"root"
#export IDRAC_REMOTE_HTTP

source shared.bash

if [[ -z "$DEFAULT_DST_IMAGE_NAME" ]]; then
  echo "Please make sure you have in shared\.bash DEFAULT_DST_IMAGE_NAME var"
  exit 99
fi

# image name in shared.bash
DEFAULT_IMAGE_NAME=$DEFAULT_DST_IMAGE_NAME
# a location where to copy iso, assume same host runs http.
DEFAULT_LOCATION_MOVE="/var/www/html"
IDRAC_IP_ADDR=""
# this flag wil skip bios configuration.
SKIP_BIOS="yes"

# all envs
if [ ! -f cluster.env ]; then
  echo "Please create cluster.env file.  Content should look like
  export IDRAC_IPS=\"x.x.x.x\"
  export IDRAC_PASSWORD=\"passs\"
  export IDRAC_USERNAME=root
  export IDRAC_REMOTE_HTTP=x.x.x.x"
  exit 99
else
  source cluster.env
fi

#trim white spaces
trim() {
  local var="$*"
  var="${var#"${var%%[![:space:]]*}"}"
  var="${var%"${var##*[![:space:]]}"}"
  echo "$var"
}

# usage log "msg"
log() {
  printf "%b %s. %b\n" "${GREEN}" "$@" "${NC}"
}

if [ ! -f "$DEFAULT_IMAGE_NAME" ]; then
  echo "Please create iso file $DEFAULT_IMAGE_NAME first."
  exit 99
fi

if [[ -z "$IDRAC_IPS" ]]; then
  echo "Please set address of http server in IDRAC_REMOTE_HTTP environment variable."
  exit 99
fi

if ! command -v pip &>/dev/null; then
  echo "please install pip3"
  exit 99
fi

function install_idrac_ctl() {
  # always get the latest.
  pip --quiet install idrac_ctl -U &>/dev/null
  pip --quiet pygments tqdm requests -U &>/dev/null
}

function compare_sha() {
  local src_hash
  local dst_hash
  src_hash=$(md5sum "$DEFAULT_IMAGE_NAME")
  dst_hash=$(md5sum $DEFAULT_LOCATION_MOVE/"$DEFAULT_IMAGE_NAME")
  if [ "$src_hash" != "$dst_hash" ]; then
    log "Coping $DEFAULT_IMAGE_NAME to $DEFAULT_LOCATION_MOVE"
    cp "$DEFAULT_IMAGE_NAME" $DEFAULT_LOCATION_MOVE
  fi
}

function adjust_bios() {
  local addr=$1
  local bios_config=$2
  local default_bios_config="bios/bios.json"
  # first we check if SRIOV enabled or not, ( Default disabled)
  if is_yes "$SKIP_BIOS"; then
    log "Skipping bios reconfiguration"
  else
    # reset all bios pending.
    export IDRAC_IP="$addr"
    idrac_ctl idrac_ctl bios-clear-pending --from_spec "$bios_config"
    export IDRAC_IP="$addr"
    idrac_ctl job-apply job-apply
    # commit changes and reboot
    export IDRAC_IP="$addr"
    idrac_ctl idrac_ctl bios-change --from_spec bios/bios.json on-reset --commit --reboot
  fi
}
function boot_host() {
  local addr=$1
  local resp=""
  IDRAC_IP="$addr" idrac_ctl eject_vm --device_id 1
  resp=$(IDRAC_IP="$addr" idrac_ctl --nocolor get_vm --device_id 1 --filter_key Inserted | jq --raw-output -r '.data')
  if is_true "$resp"; then
    log "cdrom ejected on server $addr."
    log "Mount cdrom on server $addr"
    idrac_ctl insert_vm --uri_path http://"$IDRAC_REMOTE_HTTP"/"$DEFAULT_IMAGE_NAME" --device_id 1
    log "Booting server $addr from the image"
    IDRAC_IP="$addr" idrac_ctl boot-one-shot --device Cd -r --power_on
  fi
}

function main() {
  local idrac_ip_list
  local existing_file
  existing_file=$DEFAULT_LOCATION_MOVE/"$DEFAULT_IMAGE_NAME"
  if file_exists $$DEFAULT_LOCATION_MOVE/"$DEFAULT_IMAGE_NAME"; then
      echo "Removing $existing_file"
    rm -rf "$existing_file"
  fi

  # by a default we always do clean build
  if [[ -z "$IDRAC_IPS" ]]; then
    log "IDRAC_IPS variable is empty, it must store either IP address or list comma seperated."
    exit 99
  else
    log "Using $IDRAC_IPS."
  fi

  # first trim all whitespace and then iterate.
  idrac_ip_list=$(trim "$IDRAC_IPS")
  IFS=',' read -ra IDRAC_IP_ADDR <<<"$idrac_ip_list"
  for IDRAC_HOST in "${IDRAC_IP_ADDR[@]}"; do
    local addr
    addr=$(trim "$IDRAC_HOST")
    boot_host "$addr"
  done
}

main
