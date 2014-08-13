#!/bin/sh
#
# enlarge an amazon ebs snapshot
#
# usage:
#  enlarge-snapshot.sh <snap id> <new size> [<new desc>]
#
# new size: in GB
#
# emits new snapshot id. NB doesn't delete the old snapshot.

set -e

# find the tools
amazon_dir=$(dirname "$(readlink -f "$0")")

if [ $# -lt 2 ]; then
    echo "usage: enlarge-snapshot.sh <snap id> <new size> <new desc>" >&2
    exit 1
fi

snapid="$1"
newsize="$2"
newdesc="$3"

DEVICE="/dev/xvdc1"

# fire up an ec2 instance which we'll use to run the resize2fs command, with the snapshot attached
out=`"${amazon_dir}/start-instance.sh" -- -b "$DEVICE=$snapid:$newsize"`

cd "$out"
instance_id=`cat instance_id`
ip=`cat ip`
trap 'echo "warning: ec2 instance $instance_id still extant" &>2' EXIT

# resize2fs requires us to run a fsck before it will do its stuff
echo "running e2fsck..." >&2
"${amazon_dir}/amazon-ssh.sh" -s "-t" "$out" sudo e2fsck -f -v "$DEVICE"

echo "running resize2fs..." >&2
"${amazon_dir}/amazon-ssh.sh" "$out" sudo resize2fs "$DEVICE"

# need to shut down the instance before we can take a snapshot.
# Note that this only stops the instance, rather than terminating it,
# so that we know the device is still kicking around. We do the actual
# termination below.
"${amazon_dir}/terminate-instance.sh" -s -w "$out"

# get the volume id
"${amazon_dir}/aws" --xml din "$instance_id" > din.tmp
vol_id=`perl -ne 'BEGIN {$v=shift}
   /<blockDeviceMapping>/ and $b=1; next unless $b;
   /<deviceName>(.*)<\/deviceName>/ and $d=($1 eq $v); next unless $d;
   if(/<volumeId>(.*)<\/volumeId>/) {print "$1\n"; exit 0}' ${DEVICE} < din.tmp`
rm din.tmp

echo "creating S3 snapshot of resized volume" >&2
newdesc="${newdesc:-enlarged $snapid}"
"${amazon_dir}/aws" --xml csnap "$vol_id" --description "$newdesc" > csnap.out
newsnapid=`cat csnap.out | sed -e '/<snapshotId>/! d' -e 's/.*<snapshotId>//' -e 's/<.*//'`

if [ -z "$newsnapid" ]; then
    echo "unable to retrieve snapshot id:" >&2
    cat csnap.out >&2
    rm csnap.out
    exit 1
fi
rm csnap.out

echo "done." >&2

echo $newsnapid

"${amazon_dir}/terminate-instance.sh" "$out"
trap - EXIT
