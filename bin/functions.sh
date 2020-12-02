# set up etc_dir
if [ -d "/etc/amazon" ]; then
    etc_dir="/etc/amazon"
else
    etc_dir="${amazon_dir}/../etc"
fi

snapid_file=/root/backup/snapid

# read the snapshot id from /root/backup/snapid
function read_snapid
{
    snapid=`cat "$snapid_file"`

    if [ -z "$snapid" ]; then
        echo "unable to read snapshot id from $snapid_file" >&2
        exit 1
    fi
    echo $snapid
}

