#!/bin/sh
#
# amazon-ssh.sh <state-dir>
#
set -e

if [ -z "$1" -o ! -d "$1" ]; then
    echo "usage: amazon-ssh.sh <state-dir>" >&2
    exit 1
fi

cd "$1"
shift

ip=`cat ip`
exec ssh -oStrictHostKeyChecking=yes \
         -oUserKnownHostsFile=known_hosts \
         -iid_rsa ubuntu@$ip "$@"
