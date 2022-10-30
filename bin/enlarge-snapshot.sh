#!/bin/bash
#
# enlarges the backup snapshot
#
# usage:
#  enlarge-snapshot.sh <new size> [<new desc>]
#
# new size: in GB
#
# NB doesn't delete the old snapshot.

set -e

# find the tools
amazon_dir=$(dirname "$(readlink -f "$0")")
. "${amazon_dir}/functions.sh"
. /etc/backup/config


if [ $# -lt 1 ]; then
    echo "usage: enlarge-snapshot.sh <new size in G> [<new desc>]" >&2
    exit 1
fi

newsize="$1"
newdesc="$2"

snapid=`read_snapid`

BACKUP_DEVICE=${BACKUP_DEVICE:-/dev/xvdf}
system_backup_device=/dev/xvdf

# fire up an ec2 instance which we'll use to run the resize2fs command, with the snapshot attached
out=`sudo -u amazon "${amazon_dir}/start-instance.sh" -- --block-device-mappings "DeviceName=${BACKUP_DEVICE},Ebs={SnapshotId=$snapid,VolumeType=gp2,VolumeSize=${newsize}}"`

cd "$out"
instance_id=`cat instance_id`
ip=`cat ip`
region=`cat aws_region`
trap 'echo "warning: ec2 instance $instance_id still extant" &>2' EXIT

if [ -n "$BACKUP_PASSPHRASE" ]; then
    echo "unlocking encrypted drive"
    echo -n "$BACKUP_PASSPHRASE" |
        ssh -S "ssh_control" admin@$ip sudo cryptsetup open "$system_backup_device" crypt_backup
    system_backup_device=/dev/mapper/crypt_backup
fi

# resize2fs requires us to run a fsck before it will do its stuff
echo "running e2fsck..." >&2
sudo -u amazon "${amazon_dir}/amazon-ssh.sh" -s "-t" "$out" sudo e2fsck -f -v "$system_backup_device"

echo "running resize2fs..." >&2
sudo -u amazon "${amazon_dir}/amazon-ssh.sh" "$out" sudo resize2fs "$system_backup_device"

# need to shut down the instance before we can take a snapshot.
# Note that this only stops the instance, rather than terminating it,
# so that we know the device is still kicking around. We do the actual
# termination below.
sudo -u amazon "${amazon_dir}/terminate-instance.sh" -s -w "$out"

# get the volume id
sudo -u amazon "${amazon_dir}/aws" --region "$region" --xml din "$instance_id" > din.tmp
vol_id=`perl -ne 'BEGIN {$v=shift}
   /<blockDeviceMapping>/ and $b=1; next unless $b;
   /<deviceName>(.*)<\/deviceName>/ and $d=($1 eq $v); next unless $d;
   if(/<volumeId>(.*)<\/volumeId>/) {print "$1\n"; exit 0}' ${BACKUP_DEVICE} < din.tmp`
rm din.tmp

echo "creating S3 snapshot of resized volume" >&2
newdesc="${newdesc:-enlarged $snapid}"
sudo -u amazon "${amazon_dir}/aws" --region "$region" --xml csnap "$vol_id" --description "$newdesc" > csnap.out
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
