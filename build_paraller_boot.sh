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
DEFAULT_LOCATION_MOVE="/var/www/html/"
IDRAC_IP_ADDR=""
# this flag wil skip bios configuration.
SKIP_BIOS="yes"

# all envs
if [ ! -f cluster.env ]
then
    echo "Please create cluster.env file"
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

if [ ! -f "$DEFAULT_IMAGE_NAME" ]
then
    echo "Please create iso file $DEFAULT_IMAGE_NAME first."
    exit 99
fi

if [[ -z "$IDRAC_IPS" ]]; then
  echo "Please set address of http server in IDRAC_REMOTE_HTTP environment variable."
  exit 99
fi

if ! command -v pip &> /dev/null
then
    echo "please install pip3"
    exit 99
fi

# always get the latest.
pip --quiet install idrac_ctl -U &> /dev/null
pip --quiet pygments tqdm requests -U &> /dev/null

rm rf $DEFAULT_LOCATION_MOVE/"$DEFAULT_IMAGE_NAME"
echo "Removing  $DEFAULT_LOCATION_MOVE/"$DEFAULT_IMAGE_NAME"

## build-iso.sh generates ph4-rt-refresh_adj.iso
src_hash=$(md5sum "$DEFAULT_IMAGE_NAME")
dst_hash=$(md5sum $DEFAULT_LOCATION_MOVE/"$DEFAULT_IMAGE_NAME")
if [ "$src_hash" != "$dst_hash" ]
then
  log "Coping $DEFAULT_IMAGE_NAME to $DEFAULT_LOCATION_MOVE"
  cp "$DEFAULT_IMAGE_NAME" $DEFAULT_LOCATION_MOVE
fi

# by a default we always do clean build
if [[ -z "$IDRAC_IPS" ]]; then
  log "IDRAC_IPS variable is empty, it must store either IP address or list comma seperated."
	exit 99
else
  log "Using $IDRAC_IPS."
fi

# first trim all whitespace and then iterate.
IDRAC_IP_LIST=$(trim "$IDRAC_IPS")
echo "$IDRAC_IP_ADDR"
IFS=',' read -ra IDRAC_IP_ADDR <<< "$IDRAC_IP_LIST"
for IDRAC_HOST in "${IDRAC_IP_ADDR[@]}"
do
  addr=$(trim "$IDRAC_HOST")
  # first we check if SRIOV enabled or not, ( Default disabled)
  if [ -z "$SKIP_BIOS" ] || [ $SKIP_BIOS == "yes" ]; then
    log "Skipping bios reconfiguration"
  else
      # reset all bios pending.
      export IDRAC_IP="$addr"; idrac_ctl idrac_ctl bios-clear-pending --from_spec bios/bios.json
      export IDRAC_IP="$addr"; idrac_ctl job-apply job-apply
      # commit changes and reboot
      export IDRAC_IP="$addr"; idrac_ctl idrac_ctl bios-change --from_spec bios/bios.json on-reset --commit --reboot
  fi
  # we can check what scheduled / completed etc / check manual, it will be scheduled
  # export IDRAC_IP="$addr"; idrac_ctl --json_only --debug --verbose jobs --scheduled
  # more details verbose mode
  # export IDRAC_IP="$addr"; idrac_ctl --verbose --debug bios-change  --attr_name MemTest,SriovGlobalEnable,OsWatchdogTimer,ProcTurboMode,ProcCStates,MemFrequency --attr_value Disabled,Enabled,Disabled,Disabled,Enabled,Disabled,MaxPerf on-reset -r
  # idrac_ctl bios --attr_only --filter SriovGlobalEnable
  #
  # one shoot boot.
  log "Mount cdrom server $addr"
  export IDRAC_IP="$addr"; idrac_ctl get_vm --device_id 1 --filter_key Inserted
  export IDRAC_IP="$addr"; idrac_ctl eject_vm --device_id 1
  export IDRAC_IP="$addr"; idrac_ctl insert_vm --uri_path http://"$IDRAC_REMOTE_HTTP"/$DEFAULT_IMAGE_NAME --device_id 1
  export IDRAC_IP="$addr"; idrac_ctl boot-one-shot --device Cd -r --power_on
done