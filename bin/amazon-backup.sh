#!/bin/bash
#

set -e

amazon_dir=$(dirname "$(readlink -f "$0")")

. "${amazon_dir}/functions.sh"
. /etc/backup/config

LOCK_FILE="/var/run/amazon-backup.lock"

lockfile-create -l --retry 0 "$LOCK_FILE" || { echo "backup apparently already running"; exit 1; }
trap 'lockfile-remove -l "'$LOCK_FILE'"' EXIT

snapid=`read_snapid`

# faith's backup device is a disk; buffy's is a partition...
BACKUP_DEVICE=${BACKUP_DEVICE:-/dev/sdc}
out=`sudo -u amazon "${amazon_dir}/start-instance.sh" -u "${etc_dir}/userdata/backup-server.yaml" -u "${etc_dir}/userdata/backups-ssh-key.sh" -- -b "${BACKUP_DEVICE}=$snapid"`
trap 'sudo -u amazon "'${amazon_dir}'/terminate-instance.sh" "'$out'"; lockfile-remove -l "'$LOCK_FILE'"' EXIT

cd "$out"
instance_id=`cat instance_id`
ip=`cat ip`

echo "mounting backup drive"
"${amazon_dir}/amazon-ssh.sh" "$out" sudo mount $BACKUP_DEVICE_MOUNT_OPTIONS /dev/xvdc1 /mnt

backup_path="backup@$ip::/mnt"
echo "running backup to $backup_path"

backup()
{
    path="$1"; shift
    args="--terminal-verbosity 3 -v 8 --force \
          --exclude-globbing-filelist /etc/backup/exclusions.common"

    # the use of process substitution rather than a simple pipe here
    # is to ensure that we don't get stuck if the ssh fails to start
    # (hence never returns any output, hence the rdiff client never
    # sends any data, hence the cstream never notices the ssh has died,
    # hence the pipe persists).
    #
    # rdiff-backup uses subprocess.py, which hardcodes /bin/sh, which 
    # doesn't support process substitutions. sigh.
    #
    # if this fails with a public key error, check that root@ has been
    # given permission to ssh to backup@; in particular, check out 
    # userdata/backups-ssh-key.sh
    schema="/bin/bash -c 'ssh -C -oStrictHostKeyChecking=yes -oUserKnownHostsFile=\"$out/known_hosts\" \"%s\" rdiff-backup --server < <(cstream -v 1 -t 120000)'"
    echo "using schema: $schema"
    
    dest="${backup_path}/${path}"
    rdiff-backup $args --remote-schema "$schema" "$@" "$path" "$dest"
    
    # remove old backups
    rdiff-backup --remote-schema "$schema" --force --remove-older-than 1M12h "$dest"
}

run_backups

# need to shut down the instance before we can take a snapshot
su amazon -c "'${amazon_dir}'/terminate-instance.sh -s -w '$out'"

# get the volume id
su amazon -c "'${amazon_dir}'/aws --xml din '$instance_id'" > din.tmp
vol_id=`perl -ne 'BEGIN {$v=shift}
   /<blockDeviceMapping>/ and $b=1; next unless $b;
   /<deviceName>(.*)<\/deviceName>/ and $d=($1 eq $v); next unless $d;
   if(/<volumeId>(.*)<\/volumeId>/) {print "$1\n"; exit 0}' ${BACKUP_DEVICE} < din.tmp`
rm din.tmp

echo "creating S3 snapshot of backup volume"
desc="`hostname -s` backup `date +'%Y%m%d'`"
su amazon -c "${amazon_dir}/aws --xml csnap '$vol_id' --description '$desc'" > csnap.out
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
su amazon -c "${amazon_dir}/aws delete-snapshot '$snapid'"
