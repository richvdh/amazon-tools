#!/bin/sh

set -e

amazon_dir=$(dirname "$(readlink -f "$0")")
if [ -d "${amazon_dir}/../etc" ]; then
    etc_dir="${amazon_dir}/../etc"
else
    etc_dir="/etc/amazon"
fi

out=`${amazon_dir}/start-instance.sh ${etc_dir}/userdata/ssh-server.yaml`

echo "$out"

exec "${amazon_dir}/amazon-ssh.sh" "$out" "$@"
