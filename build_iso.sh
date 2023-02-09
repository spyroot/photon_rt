#!/bin/bash
# This script will build custom ISO image.
# and name it to DEFAULT_DST_IMAGE_NAME, this value shared in shared.bash.
# unpack iso, re-adjust kickstart , repack back iso.
#
#
# spyroot@gmail.com
# Author Mustafa Bayramov

source shared.bash

log() {
  printf "%b %s %b\n" "${GREEN}" "$@" "${NC}"
}

current_os=$(uname -a)
if [[ $current_os == *"xnu"* ]];
then
  echo "You must run the script inside docker runtime."
exit 2
fi

function file_exists {
  local -r a_file="$1"
  [[ -f "$a_file" ]]
}

workspace_dir=$(pwd)

function generate_isolinux() {  
  # generate isolinux
  cat > isolinux/isolinux.cfg << EOF
include menu.cfg
default vesamenu.c32
prompt 1
timeout 1
EOF
}

function generate_menu() {  
  # generate isolinux
   cat >> isolinux/menu.cfg << EOF
label my_unattended
	menu label ^Unattended Install
    menu default
	kernel vmlinuz
	append initrd=initrd.img root=/dev/ram0 ks=cdrom:/isolinux/ks.cfg loglevel=3 photon.media=cdrom
EOF
}

function generate_grub() {
  # generate grub
  cat > boot/grub2/grub.cfg << EOF
set default=1
set timeout=1
loadfont ascii
set gfxmode="1024x768"
gfxpayload=keep

set theme=/boot/grub2/themes/photon/theme.txt
terminal_output gfxterm
probe -s photondisk -u (\$root)

menuentry "Install" {
    linux /isolinux/vmlinuz root=/dev/ram0 ks=cdrom:/isolinux/ks.cfg loglevel=3 photon.media=UUID=\$photondisk
    initrd /isolinux/initrd.img
}
EOF
}

function generate_iso() {
  local dst_iso_dir=$1
  sed -i 's/default install/default my_unattended/g' "$dst_iso_dir"/isolinux/menu.cfg
  mkisofs -quiet -R -l -L -D -b isolinux/isolinux.bin -c isolinux/boot.cat -log-file /tmp/mkisofs.log \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -eltorito-alt-boot --eltorito-boot boot/grub2/efiboot.img -no-emul-boot \
    -V "PHOTON_$(date +%Y%m%d)" . >"$workspace_dir"/"$DEFAULT_DST_IMAGE_NAME"
}

function clean_up() {
  local old_dst_image=$1
  local old_src_image_dir=$2
  local generated_img_location=""

  log "Removing old build from $old_dst_image"
  rm -rf "$old_dst_image"
  log "Unmount $old_src_image_dir"
  umount -q "$old_src_image_dir" 2>/dev/null
  log "Removing old $old_src_image_dir"
  rm -rf "$old_src_image_dir" 2>/dev/null
  generated_img_location="$workspace_dir"/"$DEFAULT_DST_IMAGE_NAME"
  rm -rf "$generated_img_location"
  rm -rf "$generated_img_location".sha
}

function main() {
  local src_iso_dir=""
  local dst_iso_dir=""
  local additional_files=""
  local kick_start_file=""
  local full_path_kick_start=""
  if [[ -z "$BUILD_TYPE" ]]; then
    echo "Please make sure you have in shared.bash BUILD_TYPE var"
    exit 99
  fi

  local DEFAULT_JSON_SPEC_DIR=$DEFAULT_SPEC_FOLDER/"online"
  if [[ -n "$BUILD_TYPE" ]]; then
    DEFAULT_JSON_SPEC_DIR=$DEFAULT_SPEC_FOLDER/$BUILD_TYPE
  fi

  src_iso_dir=/tmp/"$BUILD_TYPE"_photon-iso
  dst_iso_dir=/tmp/"$BUILD_TYPE"_photon-ks-iso
  kick_start_file=$BUILD_TYPE"_ks.cfg"
  additional_files=$DEFAULT_JSON_SPEC_DIR/additional_files.json

  clean_up "$dst_iso_dir" "$src_iso_dir"

  log "Source image temp location $src_iso_dir"
  log "Source image temp location $dst_iso_dir"

  kick_start_file=$BUILD_TYPE"_ks.cfg"
  full_path_kick_start=$workspace_dir/$kick_start_file

  mkdir -p "$src_iso_dir"
  mkdir -p "$dst_iso_dir"
  log "Mount $DEFAULT_SRC_IMAGE_NAME to $src_iso_dir"
  mount "$DEFAULT_SRC_IMAGE_NAME" "$src_iso_dir" 2>/dev/null

  log "Copy data from $src_iso_dir/* to $dst_iso_dir/"
  cp -r "$src_iso_dir"/* "$dst_iso_dir"/

  cp post.sh "$dst_iso_dir"/ > /dev/null

  local docker_files
  docker_files=$(cat "$additional_files" | jq -r '.additional_files[][]'|xargs -I {} echo "docker_images{}")
  local separator=' '
  local docker_images=""
  IFS=$separator read -ra docker_images <<<"$docker_files"
  for img in "${docker_images[@]}"; do
      log "Copy $img to $dst_iso_dir"
      cp "$img" "$dst_iso_dir"
#      cat "$dst_iso_dir"/post.sh | sed "s/DOCKER_IMAGE=/DOCKER_IMAGE=\"$img/g" >> post.sh
      cp post.sh "$dst_iso_dir"/ > /dev/null
      cat "$dst_iso_dir"/post.sh | sed "s/DOCKER_IMAGE=/DOCKER_IMAGE=\"$img/g" > post_adjusted.sh
  done

  mkdir -p "$dst_iso_dir"/"$DEFAULT_RPM_DST_DIR"
  mkdir -p "$dst_iso_dir"/"$DEFAULT_GIT_DST_DIR"
  mkdir -p "$dst_iso_dir"/"$DEFAULT_ARC_DST_DIR"

  log "Copy rpms from $DEFAULT_RPM_DIR to $dst_iso_dir / $DEFAULT_RPM_DST_DIR"
  cp $DEFAULT_RPM_DIR/* "$dst_iso_dir"/"$DEFAULT_RPM_DST_DIR"

  log "Copy git tar.gz from $DEFAULT_GIT_DIR to $dst_iso_dir / $DEFAULT_GIT_DST_DIR"
  cp $DEFAULT_GIT_DIR/* "$dst_iso_dir"/"$DEFAULT_GIT_DST_DIR"

  log "Copy arcs from $DEFAULT_ARC_DIR to $dst_iso_dir / $DEFAULT_ARC_DST_DIR"
  cp $DEFAULT_ARC_DIR/* "$dst_iso_dir"/"$DEFAULT_ARC_DST_DIR"

  log "Changing director to $dst_iso_dir"
  pushd "$dst_iso_dir"/ || exit > /dev/null
  log "Copy $full_path_kick_start to isolinux/ks.cfg"
  if file_exists "$full_path_kick_start"; then
    if file_exists "isolinux/ks.cfg"; then
      echo "Failed locate source ks"
      exit 99;
    fi
    cp "$full_path_kick_start" isolinux/ks.cfg
  fi

  generate_isolinux
  generate_menu
  generate_grub
  generate_iso "$dst_iso_dir"

  popd || exit > /dev/null
  umount "$src_iso_dir" > /dev/null
  local generated_img_location=""
  generated_img_location="$workspace_dir"/"$DEFAULT_DST_IMAGE_NAME"
  local dst_hash
  dst_hash=$(md5sum "$generated_img_location")
  log "Generated ISO in $generated_img_location hash $dst_hash"
  echo "$dst_hash" > "$generated_img_location".sha
}

main
