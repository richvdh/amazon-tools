#!/bin/sh

set -e

amazon_dir=$(dirname "$(readlink -f "$0")")

out=`${amazon_dir}/start-instance.sh /etc/amazon/userdata/ssh-server.yaml /etc/amazon/userdata/init-ssh-key.sh`
echo "$out"

exec "${amazon_dir}/amazon-ssh.sh" "$out" "$@"
