#!/bin/bash
#
# amazon-ssh.sh [-s <ssh opts>] <state-dir> [<command>]
#
set -e

temp=`getopt -n "$0" -o "+s:" -- "$@"`
eval set -- "$temp"
sshopts=()
while true; do
    case "$1" in
        "-s") sshopts+=("$2"); shift 2 ;;
        --) shift; break;;
    esac
done

if [ -z "$1" -o ! -d "$1" ]; then
    echo "usage: amazon-ssh.sh [-s <ssh opts>] <state-dir> [<command>]" >&2
    exit 1
fi

cd "$1"
shift

ip=`cat ip`
exec ssh -oStrictHostKeyChecking=yes \
         -oUserKnownHostsFile=known_hosts \
         -iid_rsa \
         "${sshopts[@]}" \
         ubuntu@$ip "$@"
