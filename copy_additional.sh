#!/bin/bash


# r=$(cat offline_testnf_os4_flex21_ks.cfg | jq --raw-output '.additional_packages[]'| xargs -I {} ls "direct_rpms/{}*.rpm")

docker_files=$(cat offline_testnf_os4_flex21_ks.cfg | jq -r '.additional_packages[]' | xargs -I {} echo "direct_rpms/{}*.rpm")
echo "$docker_files"
