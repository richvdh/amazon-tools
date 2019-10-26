#!/bin/bash
#
# enlarge an amazon ebs snapshot
#
# usage:
#  enlarge-snapshot.sh <new size> [<new desc>]
#
# new size: in GB
#
# emits new snapshot id. NB doesn't delete the old snapshot.

set -e

# find the tools
amazon_dir=$(dirname "$(readlink -f "$0")")
. "${amazon_dir}/functions.sh"

if [ $# -lt 1 ]; then
    echo "usage: enlarge-snapshot.sh <new size in G> [<new desc>]" >&2
    exit 1
fi

newsize="$1"
newdesc="$2"

snapid=`read_snapid`

BACKUP_DEVICE=${BACKUP_DEVICE:-/dev/sdf}

# fire up an ec2 instance which we'll use to run the resize2fs command, with the snapshot attached
out=`sudo -u anazon "${amazon_dir}/start-instance.sh" -- -b "$BACKUP_DEVICE=$snapid:$newsize"`

cd "$out"
instance_id=`cat instance_id`
ip=`cat ip`
region=`cat aws_region`
trap 'echo "warning: ec2 instance $instance_id still extant" &>2' EXIT

# resize2fs requires us to run a fsck before it will do its stuff
echo "running e2fsck..." >&2
sudo -u amazon "${amazon_dir}/amazon-ssh.sh" -s "-t" "$out" sudo e2fsck -f -v "$BACKUP_DEVICE"

echo "running resize2fs..." >&2
sudo -u amazon "${amazon_dir}/amazon-ssh.sh" "$out" sudo resize2fs "$BACKUP_DEVICE"

# need to shut down the instance before we can take a snapshot.
# Note that this only stops the instance, rather than terminating it,
# so that we know the device is still kicking around. We do the actual
# termination below.
sudo -u amazon "${amazon_dir}/terminate-instance.sh" -s -w "$out"

# get the volume id
"${amazon_dir}/aws" --region "$region" --xml din "$instance_id" > din.tmp
vol_id=`perl -ne 'BEGIN {$v=shift}
   /<blockDeviceMapping>/ and $b=1; next unless $b;
   /<deviceName>(.*)<\/deviceName>/ and $d=($1 eq $v); next unless $d;
   if(/<volumeId>(.*)<\/volumeId>/) {print "$1\n"; exit 0}' ${BACKUP_DEVICE} < din.tmp`
rm din.tmp

echo "creating S3 snapshot of resized volume" >&2
newdesc="${newdesc:-enlarged $snapid}"
"${amazon_dir}/aws" --region "$region" --xml csnap "$vol_id" --description "$newdesc" > csnap.out
newsnapid=`cat csnap.out | sed -e '/<snapshotId>/! d' -e 's/.*<snapshotId>//' -e 's/<.*//'`

if [ -z "$newsnapid" ]; then
    echo "unable to retrieve snapshot id:" >&2
    cat csnap.out >&2
    rm csnap.out
    exit 1
fi
rm csnap.out

echo "snapshot id: $newsnapid"
mv "$snapid_file" "${snapid_file}.0"
echo $newsnapid > "$snapid_file"

sudo -u amazon "${amazon_dir}/terminate-instance.sh" "$out"
trap - EXIT
