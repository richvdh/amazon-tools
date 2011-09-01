#!/bin/sh
#
# start-and-ssh.sh [<availability-zone>] [<ssh args>]

set -e

amazon_dir=$(dirname "$(readlink -f "$0")")
if [ -d "/etc/amazon" ]; then
    etc_dir="/etc/amazon"
else
    etc_dir="${amazon_dir}/../etc"
fi

if [ -n "$1" ]; then
    export AMAZON_ZONE="$1"
fi
shift

out=`${amazon_dir}/start-instance.sh ${etc_dir}/userdata/ssh-server.yaml`

echo "$out"

exec "${amazon_dir}/amazon-ssh.sh" "$out" "$@"
