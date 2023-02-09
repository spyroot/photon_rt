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

#function is_ubuntu_os() {
#  local -r ver="$1"
#  grep -q "Ubuntu $ver" /etc/*release &>/dev/null
#}

function is_mac_os {
  uname -a|grep Darwin &>/dev/null
}

# function generate random number on macOS
# usage
# my_rand_num
# rand_num=$(mac_random "my_rand_num")
# echo "my_rand_num"
function mac_random() {
  local num_times=1
  local _result_rand=$1
  local i="0"
  while [[ $i -lt $num_times ]]; do
    #LC_CTYPE=C tr -dc A-Za-z0-9_\!\@\#\$\%\^\&\*\(\)-+= </dev/random | head -c 20 | xargs
    LC_CTYPE=C tr -dc A-Za-z0-9 </dev/random | head -c 20 | xargs
    i=$((i + 1))
  done

  if [[ "$_result_rand" ]]; then
    eval "$_result_rand"="'$i'"
  fi
}

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

# function generate random
# in case mac it read from /dev/random
# in all other cases /proc/sys/kernel/random/uuid
# usage
# my_random_seq
# rand_num=$(random_seq "my_random_seq")
function random_seq() {
  local _result_rand_num=$1
  local rand_num
  if is_mac_os; then
    rand_num=$(mac_random "$rand_num")
  else
    while IFS= read -r rand_num; do echo "$rand_num"| head -c 5; done < /proc/sys/kernel/random/uuid
  fi
  if [[ "$_result_rand_num" ]]; then
    eval "$_result_rand_num"="'$rand_num'"
  else
    echo "$rand_num"
  fi
}

# function fetch file
# User download "http://my_http/download.me" "download.me"
# arg user and password optional
function download() {
  local url=$1
  local file_name=$2
  local user=$3
  local password=$4
  local rand_seq
  if is_not_empty "$url" && is_not_empty "$file_name"; then
    random_seq "rand_seq"
    echo "Downloading images from $url, log file $rand_seq.log"
    if is_not_empty "$user"; then
        wget --user="$user" --password="$password" -b -nc "$url" -o "$rand_seq.log"
    else
      wget -b -nc "$url" -O "$file_name" -o "$rand_seq.log"
    fi
  fi
}

# Function tar file to gz
function compress_tar() {
  local tar_filename=$1
  if [ -f "$tar_filename" ]; then
    if is_tar "$tar_filename"; then
      echo "Compressing $tar_filename"
      gzip -c "$tar_filename" > "$tar_filename.gz" >/dev/null 2>&1
    fi
  fi
}

#
if is_not_empty "$BUILD_WEB_HOST"; then
  rm -rf ./*.log
  echo "Downloading images from $BUILD_WEB_HOST"
  download "$BUILD_WEB_HOST"/testnf/testnf-du-flexran-base210.tar "testnf-du-flexran-base210.tar"
  download "$BUILD_WEB_HOST"/testnf/testnf-du-flexran-base220.tar "testnf-du-flexran-base220.tar"
  download "$BUILD_WEB_HOST"/testnf/testnf-du-lite210.tar "testnf-du-lite210.tar"
  download "$BUILD_WEB_HOST"/testnf/testnf-du-lite220.tar "testnf-du-lite220.tar"
fi

compress_tar "testnf-du-flexran-base210.tar"
compress_tar "testnf-du-flexran-base220.tar"
compress_tar "testnf-du-lite210.tar"
compress_tar "testnf-du-lite220.tar"
