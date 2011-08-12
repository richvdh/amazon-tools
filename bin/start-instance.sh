#!/bin/bash
#
# start up an amazon instance. takes a list of cloud-init files on the
# command line.  writes out the name of a working directory, which
# contains the following (among other stuff):
#   ip  - ip address of instance
#   instance_id - id of instance
#   id_rsa - ssh key which has perms for ubuntu@$ip
#
# TODO: use snapshots rather than an EBS volume, to enable free use of
#       availability zones (and to enable attaching at image start time)
# TODO: figure out how to get most recent ubuntu AMI

set -e

# find the tools
amazon_dir=$(dirname "$(readlink -f "$0")")
if [ -d "/etc/amazon" ]; then
    etc_dir="/etc/amazon"
else
    etc_dir="${amazon_dir}/../etc"
fi

# make work dir
wd="/var/run/amazon/$$"
mkdir "$wd"
cd "$wd"

# set a trap so that if we have any errors, we shut down the instance again.
trap 'terminate_instance' EXIT

terminate_instance() {
    echo "terminating instance...">&2
    if [ -f "$wd/instance_id" ]; then
	"${amazon_dir}/aws" terminate-instances `cat "$wd/instance_id"`
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
    "$@" "ssh-keys.yaml" "${etc_dir}/userdata/touch-boot-complete.conf"

#cat userdata.txt >&2
gzip userdata.txt

AMAZON_ZONE=${AMAZON_ZONE:-eu-west-1b}
region=`echo $AMAZON_ZONE | perl -ne '/([a-z-]*[0-9])/ && print $1'`

if [ -z "$region" ]; then
    echo "unable to parse zone $AMAZON_ZONE" >&2
    exit 1
fi


# instance ids available at
#   http://uec-images.ubuntu.com/releases/10.04
#
# 64-bit ebs eu-west-1
#
#  release-20101020   - ami-f6340182
#  release-20110201.1 - ami-3d1f2b49
#  release-20110719   - ami-5c417128

echo "starting instance..." >&2
"${amazon_dir}/aws" run-instances \
 --simple \
 -instance-type t1.micro \
 -instance-initiated-shutdown-behavior terminate \
 -user-data-file userdata.txt.gz \
 -availability-zone $AMAZON_ZONE \
 ami-5c417128 \
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
    if [ $a -gt 100 ]; then
	echo -e "\nGave up after 100 secs" >&2
	exit 1
    fi
    let a=a+1
    echo -n "." >&2
    sleep 1
done
echo "" >&2

ip=`"${amazon_dir}/aws" describe-instances "$instance_id" | grep "$instance_id" | cut -d '|' -f 13 | tr -d ' '`
echo "ip: $ip" >&2
echo $ip > ip

echo "building known hosts... " >&2
(echo -n "$ip "; cat ssh_host_rsa_key.pub) > known_hosts

echo -n "waiting for ssh to work" >&2
a=0
while ! ssh -oStrictHostKeyChecking=yes -oUserKnownHostsFile=known_hosts -i id_rsa ubuntu@$ip echo ok &>/dev/null; do
    if [ $a -gt 100 ]; then
	echo -e "\nGave up after 100 secs" >&2
	exit 1
    fi
    let a=a+1
    echo -n . >&2
    sleep 1
done
echo >&2

echo -n "waiting for boot to complete" >&2
a=0
while ! ssh -oStrictHostKeyChecking=yes -oUserKnownHostsFile=known_hosts -i id_rsa ubuntu@$ip \
       test -f /var/run/boot-complete; do
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

