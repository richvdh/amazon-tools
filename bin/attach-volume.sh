#!/bin/bash
#
# attach-volume.sh <vol_id> <instance_id> <device>

set -e

if [ $# -ne 3 ]; then
    echo "usage: attach-volume.sh <vol_id> <instance_id> <device>" >&2
    exit 1
fi

vol_id="$1"
instance_id="$2"
device="$3"
amazon_dir=$(dirname "$(readlink -f "$0")")

echo -n "attaching volume $vol_id" >&2
IFS=" "
out=`"${amazon_dir}/aws" --xml attach-volume $vol_id -i $instance_id -d $device`
if echo $out | grep -i '<error>' > /dev/null; then
    echo -e "\nerror attaching volume:" >&2
    echo $out >&2
    exit 1
fi

a=0
while ! "${amazon_dir}/aws" --xml dvol $vol_id | grep '<status>attached</status>' >/dev/null; do
    if [ $a -gt 100 ]; then
	echo -e "\nGave up after 100 secs" >&2
	exit 1
    fi
    let a=a+1
    echo -n "." >&2
    sleep 1
done
echo "" >&2
