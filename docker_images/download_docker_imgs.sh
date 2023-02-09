#!/bin/bash

# Function check if string "yes"
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

# Function check if string not empty
function is_not_empty() {
  local var=$1
  if [[ -z "$var" ]]; then
    return 1
  else
    return 0
  fi
}

DEFAULT_IMAGE_NAME=vcu.tar.gz
if is_not_empty "$DEFAULT_IMAGE_NAME" && is_not_empty "$BUILD_HOST"; then
  scp vmware@"$BUILD_HOST":/home/vmware/$DEFAULT_IMAGE_NAME $DEFAULT_IMAGE_NAME
fi

if is_not_empty "$BUILD_WEB_HOST"; then
  wget -q -nc http://"$BUILD_WEB_HOST"/testnf/testnf-du-flexran-base210.tar &
  wget -q -nc http://"$BUILD_WEB_HOST"/testnf/testnf-du-flexran-base220.tar &
  wget -q -nc http://"$BUILD_WEB_HOST"/testnf/testnf-du-lite210.tar &
  wget -q -nc http://"$BUILD_WEB_HOST"/testnf/testnf-du-lite220.tar &
fi
