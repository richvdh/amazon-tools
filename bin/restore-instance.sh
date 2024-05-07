#!/bin/bash
#
# start an EC2 instance, with the latest backup snapshot mounted at /mnt
#
# restore-instance.sh [<snap_id>]

set -e

amazon_dir=$(dirname "$(readlink -f "$0")")
. "${amazon_dir}/functions.sh"

[ -f /etc/backup/config ] && . /etc/backup/config

if [ $# -lt 1 ]; then
    snapid=`read_snapid`
else
    snapid="$1"
fi


BACKUP_DEVICE=${BACKUP_DEVICE:-/dev/sdf}
system_backup_device=/dev/xvdf

out=$(sudo -u amazon "${amazon_dir}/start-instance.sh" \
    -u "${etc_dir}/userdata/backup-server.yaml" \
    -- --block-device-mappings "DeviceName=${BACKUP_DEVICE},Ebs={SnapshotId=$snapid,VolumeType=gp2}"
)

cd "$out"
instance_id=`cat instance_id`
ip=`cat ip`

echo "adding ssh key to backup@"
ssh_key="$(cat id_rsa.pub)"
echo "$ssh_key" | ssh -S "ssh_control" admin@$ip sudo tee -a "~backup/.ssh/authorized_keys" > /dev/null

if [ -n "$BACKUP_PASSPHRASE" ]; then
    echo "unlocking encrypted drive"
    echo -n "$BACKUP_PASSPHRASE" |
        ssh -S "ssh_control" admin@$ip sudo cryptsetup open "$system_backup_device" crypt_backup
    system_backup_device=/dev/mapper/crypt_backup
fi


echo "mounting backup drive"
ssh -S "ssh_control" admin@$ip sudo mount "${system_backup_device}" /mnt

echo "EC2 instance started at $ip; ssh via \"${amazon_dir}/amazon-ssh.sh\" $out."
echo "shut it down with \"${amazon_dir}/terminate-instance.sh\" $out."
