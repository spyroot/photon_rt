#!/bin/bash
# this script will pass that will
# trigger Photon 5 build.
#
# spyroot@gmail.com
# Author Mustafa Bayramov
PHOTON_5_X86=yes BUILD_TYPE="offline_testnf_os5_flex22" DPDK_VER="22.11" ./build_and_exec.sh
PHOTON_5_X86=yes BUILD_TYPE="offline_testnf_os5_flex22" DPDK_VER="22.11" ./build_iso.sh
#cp ph5-rt-refresh_adj_offline_testnf_os5_flex22.iso /var/www/html/
PHOTON_5_X86=yes BUILD_TYPE="offline_testnf_os5_flex22" DPDK_VER="22.11" ./build_in_parallel_boot.sh

# sda
#PHOTON_5_X86=yes BUILD_TYPE="offline_testnf_os5_flex22" DPDK_VER="22.11" TARGET_DISK="/dev/sda" ./build_and_exec.sh
#PHOTON_5_X86=yes BUILD_TYPE="offline_testnf_os5_flex22" DPDK_VER="22.11" TARGET_DISK="/dev/sda" ./build_iso.sh
#PHOTON_5_X86=yes BUILD_TYPE="offline_testnf_os5_flex22" DPDK_VER="22.11" TARGET_DISK="/dev/sda" ./build_in_parallel_boot.sh

