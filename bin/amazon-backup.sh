#!/bin/bash
#

set -e

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

snapid=`read_snapid`

BACKUP_DEVICE=${BACKUP_DEVICE:-/dev/sdf}
out=`sudo -u amazon "${amazon_dir}/start-instance.sh" -u "${etc_dir}/userdata/backup-server.yaml" -u "${etc_dir}/userdata/backups-ssh-key.sh" -- -b "${BACKUP_DEVICE}=${snapid}:::gp2"`
trap 'remove_lockfile; sudo -u amazon "'${amazon_dir}'/terminate-instance.sh" "'$out'"' EXIT

cd "$out"
instance_id=`cat instance_id`
ip=`cat ip`

remote_backup_dir="/mnt"
echo "mounting backup drive"
"${amazon_dir}/amazon-ssh.sh" "$out" sudo mount $BACKUP_DEVICE_MOUNT_OPTIONS /dev/xvdf "${remote_backup_dir}"

# if this fails with a public key error, check that root@ has been
# given permission to ssh to backup@; in particular, check out
# userdata/backups-ssh-key.sh
echo "starting SSH master for backup@$ip"
control_sock="${out}/ssh_control.backup"
ssh -C -M -S "${control_sock}" -oControlPersist=yes \
    -oStrictHostKeyChecking=yes -oUserKnownHostsFile="$out/known_hosts" \
    "backup@$ip" -O forward

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
    schema="ssh -S \"${control_sock}\" \"%s\" rdiff-backup --server"
    schema="$schema < <(cstream -v 1 -T 10 -t ${RATE_LIMIT:-300000})"
    schema="/bin/bash -c '$schema'"
    # echo "using schema: $schema"

    dest="backup@$ip::${remote_backup_dir}/${path}"
    rdiff-backup $args --remote-schema "$schema" "$@" "$path" "$dest"

    # remove old backups
    rdiff-backup --remote-schema "$schema" --force --remove-older-than "${MAX_INCREMENT_AGE:-1M12h}" "$dest"

    # rotate the log
    ssh -S "${control_sock}" "backup@$ip" sudo savelog "${remote_backup_dir}/${path}/rdiff-backup-data/backup.log"
}

run_backups

ssh -S "${control_sock}" "backup@$ip" df "$remote_backup_dir" >> /root/backup/df.log

# shut down the control master to avoid a perms error on the socket
ssh -S "${control_sock}" "backup@$ip" -O exit

# need to stop the instance before we can take a snapshot
sudo -u amazon "${amazon_dir}/terminate-instance.sh" -s -w "$out"

# get the volume id
sudo -u amazon "${amazon_dir}/aws" --xml din "$instance_id" > din.tmp
vol_id=`perl -ne 'BEGIN {$v=shift}
   /<blockDeviceMapping>/ and $b=1; next unless $b;
   /<deviceName>(.*)<\/deviceName>/ and $d=($1 eq $v); next unless $d;
   if(/<volumeId>(.*)<\/volumeId>/) {print "$1\n"; exit 0}' ${BACKUP_DEVICE} < din.tmp`
rm din.tmp

echo "creating S3 snapshot of backup volume"
desc="`hostname -s` backup `date +'%Y%m%d'`"
sudo -u amazon "${amazon_dir}/aws" --xml csnap "$vol_id" --description "$desc" > csnap.out
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

echo "deleting old snapshot $snapid"
sudo -u amazon "${amazon_dir}/aws" delete-snapshot "$snapid"
