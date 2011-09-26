#!/bin/bash
#
# usage: terminate-instance.sh [-k] [-w] <workingdir>
# -k: don't delete working dir
# -w: wait for server to shut down
# -s: stop, don't terminate (can be restarted with aws start-instances). Implies -k

set -e

amazon_dir=$(cd `dirname "$0"` && pwd)

temp=`getopt -n terminate-instance.sh -o kws -- "$@"`
eval set -- "$temp"

keep=
wait=
cmd=terminate-instances
while true; do
    case "$1" in
        -k) keep=1; shift ;;
        -w) wait=1; shift ;;
        -s) cmd=stop-instances; keep=1; shift;;
        --) shift; break;;
    esac
done

if [ "$#" -lt 1 ]; then
    echo "usage: terminate-instance.sh [-kw] <workingdir>" >&2
    exit 1
fi

wd="$1"
instance_id=`cat "$wd/instance_id"`

out=`"${amazon_dir}/aws" --xml "$cmd" "$instance_id"`
if echo $out | grep -i '<error>' > /dev/null; then
    echo "error terminating instance:" >&2
    echo $out >&2
    exit 1
fi

if [ -n "$wait" ]; then
    echo -n "waiting for instance to stop" >&2
    a=0
    while state=$("${amazon_dir}/aws" describe-instances --simple "$instance_id" | \
        cut -f2) && [ "$state" = 'shutting-down' -o "$state" = 'stopping' ]; do
        if [ $a -gt 200 ]; then
            echo -e "\nGave up after 200 secs" >&2
            exit 1
        fi
        let a=a+1
        echo -n "." >&2
        sleep 1
    done
    echo "" >&2
fi

if [ -z "$keep" ]; then
    rm -r "$wd"
fi


