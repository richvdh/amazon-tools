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
toolsdir=$(cd `dirname "$0"` && pwd)

echo -n "attaching volume $vol_id" >&2
"${toolsdir}/aws" attach-volume $vol_id -i $instance_id -d $device >/dev/null
a=0
while state=$("${toolsdir}/aws" describe-volumes $vol_id | grep $vol_id | \
    cut -d'|' -f5 | tr -d ' ') && [ "$state" != 'in-use' ]; do
    if [ $a -gt 100 ]; then
	echo -e "\nGave up after 100 secs" >&2
	exit 1
    fi
    let a=a+1
    echo -n "." >&2
    sleep 1
done
echo "" >&2

"${toolsdir}/aws" describe-volumes $vol_id
