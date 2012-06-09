#!/bin/bash
#
# start up an amazon instance. 
# writes out the name of a working directory, which
# contains the following (among other stuff):
#   ip  - ip address of instance
#   instance_id - id of instance
#   id_rsa - ssh key which has perms for ubuntu@$ip
#
# TODO: figure out how to get most recent ubuntu AMI
# TODO: rewrite in python, or something. maybe with boto.

# usage:
#  start-instance.sh [-u <userdata file>] [run-instance args...]

set -e

# find the tools
amazon_dir=$(dirname "$(readlink -f "$0")")
if [ -d "/etc/amazon" ]; then
    etc_dir="/etc/amazon"
else
    etc_dir="${amazon_dir}/../etc"
fi

temp=`getopt -n "$0" -o "u:" -- "$@"`
eval set -- "$temp"
userdata=()
while true; do
    case "$1" in
        "-u") userdata+=("$2"); shift 2 ;;
        --) shift; break;;
    esac
done

if [ -n "${AMAZON_ZONE}" ]; then
    region=`echo $AMAZON_ZONE | perl -ne '/([a-z-]*[0-9])/ && print $1'`

    if [ -z "$region" ]; then
        echo "unable to parse zone $AMAZON_ZONE" >&2
        exit 1
    fi

    echo "starting instance in zone ${AMAZON_ZONE}" >&2
    set -- -availability-zone "$AMAZON_ZONE" "$@"
fi

# make work dir
wd=`mktemp -t -d amazon.XXXXXXXX`
cd "$wd"

# set a trap so that if we have any errors, we shut down the instance again.
trap 'terminate_instance' EXIT

terminate_instance() {
    if [ -f "$wd/instance_id" ]; then
        instance_id=`cat "$wd/instance_id"`
        echo "terminating instance...">&2
	"${amazon_dir}/aws" terminate-instances "$instance_id"

        
        echo "waiting for console output to become available..." >&2
        sleeptime=120
        if [ -t 0 ]; then
            # use read if we're in a terminal, to allow skipping it
            echo "(enter to skip)" >&2
            read -t $sleeptime
        else
            sleep $sleeptime
        fi

        echo "Console output follows:" >&2
        "${amazon_dir}/aws" get-console-output "$instance_id" >&2
        echo "----END---" >&2
    fi
    cd /
    rm -r "$wd"
}

echo "building ssh keys..." >&2
for i in rsa dsa; do
    ssh-keygen -f ssh_host_${i}_key -t ${i} -N "" > /dev/null
done
ssh-keygen -f id_rsa -t rsa -N "" > /dev/null

echo "building user-data..." >&2
(
    echo "#cloud-config"
    echo "ssh_keys:"
    for i in rsa dsa; do
        echo "    ${i}_private: |"
        sed -e 's/^/        /' "ssh_host_${i}_key"
	rm "ssh_host_${i}_key"
        echo -n "    ${i}_public: "
        cat ssh_host_${i}_key.pub
    done
    echo "ssh_authorized_keys:"
    echo -n " - "
    cat id_rsa.pub
) > ssh-keys.yaml

"$amazon_dir/write-mime-multipart" --output=userdata.txt \
    "${userdata[@]}" "ssh-keys.yaml"

#cat userdata.txt >&2
gzip userdata.txt


# instance ids available at
#   http://uec-images.ubuntu.com/releases/precise
#
# 64-bit ebs eu-west-1

echo "starting instance..." >&2
"${amazon_dir}/aws" run-instances \
 --simple \
 -instance-type t1.micro \
 -instance-initiated-shutdown-behavior terminate \
 -user-data-file userdata.txt.gz \
 "$@" \
 ami-e1e8d395 \
 > "run-output" || { cat "run-output" >&2; exit 1; }

instance_id=`cat "run-output" | cut -f1`
echo "instance id: $instance_id" >&2

if [ -z "$instance_id" ]; then
    echo "unable to read instance-id from output:" >&2
    cat "run-output" >&2
    exit 1
fi

echo $instance_id > instance_id

echo -n "waiting for instance to start" >&2
a=0
while state=$("${amazon_dir}/aws" describe-instances --simple "$instance_id" | \
    cut -f2) && [ "$state" = 'pending' ]; do
    if [ $a -gt 200 ]; then
	echo -e "\nGave up after 200 secs" >&2
	exit 1
    fi
    let a=a+1
    echo -n "." >&2
    sleep 1
done
echo "" >&2

if [ "$state" != 'running' ]; then
    echo -e "unexpected instance state $state" >&2
    exit 1
fi

"${amazon_dir}/aws" describe-instances --xml "$instance_id" > "run-output"
ip=`cat "run-output" | sed -e '/<ipAddress>/! d' -e 's/.*<ipAddress>//' -e 's/<.*//'`
if [ -z "$ip" ]; then
    echo "unable to read ip from output:" >&2
    cat "run-output" >&2
    exit 1
fi

echo "ip: $ip" >&2
echo $ip > ip

echo "building known hosts... " >&2
(echo -n "$ip "; cat ssh_host_rsa_key.pub) > known_hosts

echo -n "waiting for ssh to work" >&2
a=0
while ! ssh -oStrictHostKeyChecking=yes -oUserKnownHostsFile=known_hosts -i id_rsa ubuntu@$ip echo ok &>/dev/null; do
    if [ $a -gt 200 ]; then
	echo -e "\nGave up after 200 secs; giving one last try" >&2
        ssh -oStrictHostKeyChecking=yes -oUserKnownHostsFile=known_hosts -i id_rsa ubuntu@$ip echo ok 
	exit 1
    fi
    let a=a+1
    echo -n . >&2
    sleep 1
done
echo >&2

trap - EXIT

echo -n "waiting for boot to complete" >&2
a=0
while ! ssh -oStrictHostKeyChecking=yes -oUserKnownHostsFile=known_hosts -i id_rsa ubuntu@$ip \
       test -f /var/lib/cloud/instance/boot-finished; do
    if [ $a -gt 100 ]; then
	echo -e "\nGave up after 100 secs" >&2
	exit 1
    fi
    let a=a+1
    echo -n . >&2
    sleep 1
done
echo >&2

# finally, write the results and remove the exit trap
echo $wd
trap - EXIT

