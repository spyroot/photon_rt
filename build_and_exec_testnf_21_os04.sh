#!/bin/bash
# this script will pass that will
# trigger Photon 5 build.
#
# spyroot@gmail.com
# Author Mustafa Bayramov
BUILD_TYPE="offline_testnf_os4_flex21" ./build_and_exec.sh
BUILD_TYPE="offline_testnf_os4_flex21" ./build_iso.sh
BUILD_TYPE="offline_testnf_os4_flex21" ./build_in_parallel_boot.sh