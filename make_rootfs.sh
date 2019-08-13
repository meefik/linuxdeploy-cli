#!/bin/bash

EXTERNAL_STORAGE="$1"
[ -n "${EXTERNAL_STORAGE}" ] || EXTERNAL_STORAGE="./rootfs"
[ -e "${EXTERNAL_STORAGE}" ] || mkdir -p "${EXTERNAL_STORAGE}"

CONFIG_DIR="$2"
[ -n "${CONFIG_DIR}" ] || CONFIG_DIR="./config"

find "${CONFIG_DIR}" -type f -name "*.conf" | sort | while read cfg_file
do
    cfg_name="$(basename ${cfg_file%.*})"
    tgz_file="${EXTERNAL_STORAGE}/${cfg_name}.tgz"
    echo "### deploy: ${cfg_name}"
    [ ! -e "${tgz_file}" ] || continue
    (set -e
    ./cli.sh -d -p "${cfg_name}" deploy --source-path=""
    ./cli.sh -d -p "${cfg_name}" export "${tgz_file}"
    ./cli.sh -d -p "${cfg_name}" umount
    exit 0)
    if [ $? -ne 0 ]
    then
        echo "Exit with an error!"
        exit 1
    fi
done
