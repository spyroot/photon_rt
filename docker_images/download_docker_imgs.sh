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

function download() {
  local url=$1
  if is_not_empty "$url"; then
    echo "Downloading images from $url"
    wget -q -nc "$url"
  fi
}

if is_not_empty "$BUILD_WEB_HOST"; then
  echo "Downloading images from $BUILD_WEB_HOST"
  download http://"$BUILD_WEB_HOST"/testnf/testnf-du-flexran-base210.tar
  download http://"$BUILD_WEB_HOST"/testnf/testnf-du-flexran-base210.tar
  download http://"$BUILD_WEB_HOST"/testnf/testnf-du-lite210.tar
  download http://"$BUILD_WEB_HOST"/testnf/testnf-du-lite220.tar
fi
