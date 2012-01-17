# set up etc_dir
if [ -d "/etc/amazon" ]; then
    etc_dir="/etc/amazon"
else
    etc_dir="${amazon_dir}/../etc"
fi


# read the snapshot id from /root/backup/snapid
function read_snapid
{
    snapid_file=/root/backup/snapid
    snapid=`cat "$snapid_file"`

    if [ -z "$snapid" ]; then
        echo "unable to read snapshot id from $snapid_file" >&2
        exit 1
    fi
    echo $snapid
}

# start the backup instance. Writes out the name of the state dir
function start_backup_instance
{
    # faith's backup device is a disk; buffy's is a partition...
    BACKUP_DEVICE=${BACKUP_DEVICE:-/dev/sdc}
    su amazon -c "\"${amazon_dir}/start-instance.sh\" -u \"${etc_dir}/userdata/backup-server.yaml\" -u \"${etc_dir}/userdata/backups-ssh-key.sh\" -- -b \"${BACKUP_DEVICE}=$snapid\""
}

function mount_backup_device
{
    echo "mounting backup drive"
    ssh -o StrictHostKeyChecking=yes -oUserKnownHostsFile=known_hosts -iid_rsa ubuntu@$ip sudo mount /dev/sdc1 /mnt
}
