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
#
# export IDRAC_IPS="192.168.1.1,192.168.1.2"
# export IDRAC_PASSWORD="password"
# export IDRAC_USERNAME"root"
# export IDRAC_REMOTE_HTTP

source shared.bash

if [ -z "$DEFAULT_OVERWRITE_FILE" ]; then
    log_error "Make sure you have defined DEFAULT_OVERWRITE_FILE in shared bash file"
    exit 99
fi

source "$DEFAULT_OVERWRITE_FILE"

if [[ -z "$DEFAULT_DST_IMAGE_NAME" ]]; then
  echo "Please make sure you have in shared\.bash DEFAULT_DST_IMAGE_NAME var"
  exit 99
fi

# image name in shared.bash
DEFAULT_IMAGE_NAME=$DEFAULT_DST_IMAGE_NAME
# a location where to copy iso, assume same host runs http.
DEFAULT_LOCATION_MOVE="/var/www/html"

if [[ -z "$DEFAULT_WEB_DIR" ]]; then
  log_info "Using default location $DEFAULT_LOCATION_MOVE"
else
  DEFAULT_LOCATION_MOVE=$DEFAULT_WEB_DIR
fi

# this flag wil skip bios configuration.
SKIP_BIOS="yes"

# all envs
if [ ! -f "$DEFAULT_CLUSTER_ENV_FILENAME" ]; then
  log_error "Please create cluster.env file.
  Content should contain:
  export IDRAC_IPS=\"x.x.x.x\"
  export IDRAC_PASSWORD=\"pass\"
  export IDRAC_USERNAME=root
  export IDRAC_REMOTE_HTTP=x.x.x.x"
  exit 99
else
  source "$DEFAULT_CLUSTER_ENV_FILENAME"
fi

#trim white spaces
trim() {
  local var="$*"
  var="${var#"${var%%[![:space:]]*}"}"
  var="${var%"${var##*[![:space:]]}"}"
  echo "$var"
}

if [ ! -f "$DEFAULT_IMAGE_NAME" ]; then
  log_error "Please create iso file $DEFAULT_IMAGE_NAME first."
  exit 99
fi

if [[ -z "$IDRAC_IPS" ]]; then
  log_error "Please set address of http server in IDRAC_REMOTE_HTTP environment variable."
  exit 99
fi

if ! command -v pip &>/dev/null; then
  log_error "please install pip3"
  exit 99
fi

#Function installs idrac_ctl
function install_idrac_ctl() {
  # always get the latest.
  pip --quiet install idrac_ctl -U &>/dev/null
  pip --quiet pygments tqdm requests -U &>/dev/null
}

function default_img_location() {
  echo $DEFAULT_LOCATION_MOVE/"$DEFAULT_IMAGE_NAME"
}

# Function compare hash between two files
# first and second arg full path to a file.
function compare_sha() {
  declare -r source_path=$1
  declare -r dst_path=$2

  if file_exists "$source_path" && file_exists "$dst_path"; then
    local src_hash
    local dst_hash
    src_hash=$(md5sum "$source_path")
    dst_hash=$(md5sum "$dst_path")
    if [ "$src_hash" == "$dst_hash" ]; then
      return 0
    fi
  fi

  return 1
}

# Function adjust bios configuration on each server
# if bios confing expected on each server.
function adjust_bios_if_needed() {
  declare addr=$1
  declare bios_config

  if is_not_empty "$addr"; then
    printf "Processing server %s\n"  "$addr"
  else
    log_error "Empty server address"
  fi

  # we save entire bios, so we use can check each value
  if [ -z "$DEFAULT_BIOS_CONFIG" ]; then
    log "Skipping bios configuration"
    exit 99
  else
    bios_config=$DEFAULT_BIOS_CONFIG
    if file_exists "$bios_config"; then
      log_info "Reading bios spec from $bios_config"
    else
      log_error "Failed read spec."
      exit 99
    fi
    log_info "- Checking bios configuration on a server $addr"
    local bios_tmp_file
    bios_tmp_file="/tmp/$addr.bios.json"
    IDRAC_IP="$addr" idrac_ctl --nocolor bios --attr_only | jq --raw-output '.data'[] >"$bios_tmp_file"
    if file_exists "$bios_tmp_file"; then
      declare bios_keys
      # read current bios for a host and check for any mismatch if we find at least one
      # we apply bios config
      jq --raw-output '.Attributes | keys'[] "$DEFAULT_BIOS_CONFIG" | while read -r bios_keys; do
        declare bios_value
        bios_value=$(jq --raw-output ".Attributes.$bios_keys" "$DEFAULT_BIOS_CONFIG")
        declare curren_bios_value
        curren_bios_value=$(jq --raw-output ".$bios_keys" "$bios_tmp_file")
        print_expected_green "  -Check bios configuration for: $bios_keys" "$bios_value" "$curren_bios_value"
        if [ "$bios_value" != "$curren_bios_value" ]; then
          print_expected_red "BIOS configuration must be applied for:$bios_keys" "$bios_value" "$curren_bios_value"
          IDRAC_IP="$addr" idrac_ctl job-apply bios
          IDRAC_IP="$addr" idrac_ctl idrac_ctl bios-change --from_spec "$bios_config" --commit --reboot
        fi
      done
    else
      log_error "Failed to save bios configuration $bios_tmp_file"
    fi
  fi
}

function boot_host() {
  local addr=$1
  local resp=""

  IDRAC_IP="$addr" idrac_ctl eject_vm --device_id 1
  resp=$(IDRAC_IP="$addr" idrac_ctl --nocolor get_vm --device_id 1 --filter_key Inserted | jq --raw-output -r '.data')
  log "Respond for get virtual medial $resp"
  if is_cdrom_connected "$resp"; then
    log "cdrom ejected on server $addr."
  fi

  log "Mount cdrom on server $addr"
  IDRAC_IP="$addr" idrac_ctl insert_vm --uri_path http://"$IDRAC_REMOTE_HTTP"/"$DEFAULT_IMAGE_NAME" --device_id 1
  log "Booting server $addr from the image"
  IDRAC_IP="$addr" idrac_ctl boot-one-shot --device Cd -r --power_on
}

function main() {
  declare idrac_ip_list
  declare idrac_ipaddr_array=""
  declare -r image_name=$DEFAULT_IMAGE_NAME
  declare -r image_location=$DEFAULT_LOCATION_MOVE
  declare -r target_img_location="$image_location"/"$image_name"

  if file_exists "$target_img_location"; then
    log "Removing $target_img_location"
    rm -rf "$target_img_location"
  else
    log_error "Failed locate $target_img_location"
    exit 99
  fi

  log "Coping.. $image_name $target_img_location"
  cp "$image_name" "$target_img_location"
  if file_exists "$target_img_location"; then
    log "File successfully copied $target_img_location"
  fi

  install_idrac_ctl

  # by a default we always do clean build
  if [[ -z "$IDRAC_IPS" ]]; then
    log_error "IDRAC_IPS variable is empty, it must store either IP address or list comma seperated."
    exit 99
  else
    log_info "Current cluster spec server list.$IDRAC_IPS."
  fi

  # first trim all whitespace and then iterate.
  idrac_ip_list=$(trim "$IDRAC_IPS")
  IFS=',' read -ra IDRAC_IP_ADDR <<<"$idrac_ip_list"
  for idrac_server in "${idrac_ipaddr_array[@]}"; do
    local addr
    addr=$(trim "$idrac_server")
    adjust_bios_if_needed "$addr"
    boot_host "$addr"
  done
}

main
