#!/bin/sh

set -e

amazon_dir=$(dirname "$(readlink -f "$0")")

. /etc/backup/config

export AMAZON_ZONE

out=`su amazon -c "${amazon_dir}/start-instance.sh /etc/amazon/userdata/backup-server.yaml /etc/amazon/userdata/init-ssh-key.sh"`
cd "$out"

instance_id=`cat instance_id`
ip=`cat ip`

trap 'su amazon -c "'${amazon_dir}'/stop-instance.sh '$out'"' EXIT

su amazon -c "${amazon_dir}/attach-volume.sh ${BACKUP_VOL} $instance_id /dev/sdc"

echo "mounting backup drive" >&2
ssh -o StrictHostKeyChecking=yes -oUserKnownHostsFile=known_hosts -iid_rsa ubuntu@$ip sudo mount /dev/sdc1 /mnt

backup_path="backup@$ip::/mnt"
echo "running backup to $backup_path"


backup()
{
    path="$1"; shift
    conf="$1"; shift
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
    schema="/bin/bash -c 'ssh -C -oStrictHostKeyChecking=yes -oUserKnownHostsFile=known_hosts \"%s\" rdiff-backup --server < <(cstream -v 1 -t 40000)'"

    if [ -r /etc/backup/exclusions.${conf} ]; then
        args="$args --exclude-globbing-filelist /etc/backup/exclusions.${conf}"
    fi
    
    dest="${backup_path}/${path}"
    rdiff-backup $args --remote-schema "$schema" "$@" "$path" "$dest"
    
    # remove old backups
    rdiff-backup --remote-schema "$schema" --force --remove-older-than 1M12h "$dest"
}

backup /home home --include=/home/mysql/log --exclude=/home/mysql
backup /etc etc
backup /usr/local local
backup /var/lib/cyrus var

