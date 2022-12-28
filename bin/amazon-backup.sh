#!/bin/bash
#
# This script uses two separate users on the remote server:
#
#   admin@, which must have sudo permissions. We create an ssh keypair locally
#     and grant access for it via the userdata.
#
#   backup@, which is used to run the rdiff-backup server. We add ssh access to
#     that after booting.

set -e
set -o pipefail

amazon_dir=$(dirname "$(readlink -f "$0")")

. "${amazon_dir}/functions.sh"
. /etc/backup/config

LOCK_FILE="/var/run/amazon-backup"

lockfile-create --retry 0 "$LOCK_FILE" || { echo "backup apparently already running"; exit 1; }
lockfile-touch "$LOCK_FILE" &
LOCKTOUCHPID="$!"

function remove_lockfile
{
    kill $LOCKTOUCHPID
    lockfile-remove "$LOCK_FILE"
}

trap 'remove_lockfile' EXIT

BACKUP_DEVICE=${BACKUP_DEVICE:-/dev/sdf}
system_backup_device=/dev/xvdf

if [ -f "$snapid_file" ]; then
    snapid=`read_snapid`
    backup_device_opts="Ebs={SnapshotId=$snapid,VolumeType=gp2}"
else
    echo "$snapid_file does not exist; will start with a new 20G volume"
    snapid=""
    backup_device_opts="Ebs={VolumeSize=20,VolumeType=gp2}"
fi

function dump_cloud_logs
{
    {
        echo "cloud-init.log:"
        ssh -S "ssh_control" admin@$(<"$out"/ip) cat /var/log/cloud-init.log
        echo "----"
        echo "cloud-final.service log:"
        ssh -S "ssh_control" admin@$(<"$out"/ip) journalctl -u cloud-final.service -b
        echo "----"
    } >&2
}

function terminate_instance
{
    remove_lockfile
    sudo -Hu amazon "${amazon_dir}/terminate-instance.sh" "$out"
}


out=$(sudo -Hu amazon "${amazon_dir}/start-instance.sh" \
    -u "${etc_dir}/userdata/backup-server.yaml" \
    -- --block-device-mappings "DeviceName=${BACKUP_DEVICE},${backup_device_opts}"
)
trap 'dump_cloud_logs; terminate_instance' EXIT

cd "$out"
instance_id=`cat instance_id`
ip=`cat ip`
region=`cat aws_region`

echo "adding ssh key to backup@"
ssh_key="$(cat id_rsa.pub)"
echo 'command="rdiff-backup --server --restrict /mnt",no-port-forwarding,no-X11-forwarding,no-pty '"$ssh_key" |
    ssh -S "ssh_control" admin@$ip sudo tee -a "~backup/.ssh/authorized_keys"

if [ -n "$BACKUP_PASSPHRASE" ]; then
    echo "unlocking encrypted drive"
    echo -n "$BACKUP_PASSPHRASE" |
        ssh -S "ssh_control" admin@$ip sudo cryptsetup open "$system_backup_device" crypt_backup
    system_backup_device=/dev/mapper/crypt_backup
fi

if [ -z "$snapid" ]; then
    echo "formatting new backup volume"
    ssh -S "ssh_control" admin@$ip sudo mkfs -t ext4 "$system_backup_device"
fi

remote_backup_dir="/mnt"
echo "mounting backup drive"
ssh -S "ssh_control" admin@$ip sudo mount $BACKUP_DEVICE_MOUNT_OPTIONS "${system_backup_device}" "${remote_backup_dir}"
ssh -S "ssh_control" admin@$ip sudo chown backup "${remote_backup_dir}"

echo "starting SSH master for backup@$ip"
ssh -C -M -S "ssh_control.backup" -oControlPersist=yes \
    -oStrictHostKeyChecking=yes -oUserKnownHostsFile="$out/known_hosts" \
    -i id_rsa "backup@$ip" -O forward

backup()
{
    path="$1"; shift

    echo "backing up: $path"

    args="--terminal-verbosity 3 -v 8 --force \
          --exclude-globbing-filelist /etc/backup/exclusions.common \
          --create-full-path"

    # the use of process substitution rather than a simple pipe here
    # is to ensure that we don't get stuck if the ssh fails to start
    # (hence never returns any output, hence the rdiff client never
    # sends any data, hence the cstream never notices the ssh has died,
    # hence the pipe persists).
    #
    # rdiff-backup uses subprocess.py, which hardcodes /bin/sh, which
    # doesn't support process substitutions. sigh.
    #
    schema="ssh -S ssh_control.backup \"%s\" rdiff-backup --server"
    schema="$schema < <(cstream -v 1 -T 10 -t ${RATE_LIMIT:-300000})"
    schema="/bin/bash -c '$schema'"
    # echo "using schema: $schema"

    dest="backup@$ip::${remote_backup_dir}/${path}"
    rdiff-backup $args --remote-schema "$schema" "$@" "$path" "$dest"

    # remove old backups
    rdiff-backup --remote-schema "$schema" --force --remove-older-than "${MAX_INCREMENT_AGE:-1M12h}" "$dest"

    # rotate the log
    ssh -S "ssh_control" admin@$ip sudo savelog "${remote_backup_dir}/${path}/rdiff-backup-data/backup.log"
}

run_backups

# shut down the control master to avoid a perms error on the socket
ssh -S "ssh_control.backup" "backup@$ip" -O exit

mkdir -p /root/backup
{
    date
    ssh -S "ssh_control" admin@$ip df "$remote_backup_dir" | tail -n +2
} >> /root/backup/df.log

# need to stop the instance before we can take a snapshot
sudo -Hu amazon "${amazon_dir}/terminate-instance.sh" -s -w "$out"

# get the volume id
vol_id=$(sudo -Hu amazon "${amazon_dir}/aws" ec2 describe-instances \
    --region "$region" \
    --output text \
    --query "Reservations[*].Instances[*].BlockDeviceMappings[?DeviceName==\`${BACKUP_DEVICE}\`].Ebs.VolumeId" \
    --instance-ids "$instance_id"
)

echo "creating S3 snapshot of backup volume"
desc="`hostname -s` backup `date +'%Y%m%d'`"
newsnapid=$(sudo -Hu amazon "${amazon_dir}/aws" ec2 create-snapshot \
    --region "$region" \
    --output text \
    --query 'SnapshotId' \
    --description "$desc" \
    --volume-id "$vol_id"
)

echo "snapshot id: $newsnapid"
mv "$snapid_file" "${snapid_file}.0" 2>/dev/null || true
echo $newsnapid > "$snapid_file"

if [ -n "$snapid" ]; then
    echo "deleting old snapshot $snapid"
    sudo -Hu amazon "${amazon_dir}/aws" ec2 delete-snapshot \
        --region "$region" \
        --snapshot-id "$snapid"
fi

# don't dump the cloud logs
trap 'terminate_instance' EXIT
