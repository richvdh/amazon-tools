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

. /etc/amazon/env

# find the tools
cd `dirname "$0"`
toolsdir=`pwd`

# make work dir
wd="/var/run/amazon/$$"
mkdir "$wd"
cd "$wd"

# set a trap so that if we have any errors, we shut down the instance again.
trap 'terminate_instance' EXIT

terminate_instance() {
    echo "terminating instance...">&2
    if [ -f "$wd/instance_id" ]; then
	ec2-terminate-instances `cat "$wd/instance_id"`
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
"$toolsdir/write-mime-multipart" --output=userdata.txt \
    "$@" "ssh-keys.yaml" "/etc/amazon/userdata/touch-boot-complete.conf"

#cat userdata.txt >&2
gzip userdata.txt

# ids come from http://uec-images.ubuntu.com/releases/10.04/release/
#  ami-f6340182 \
echo "starting instance..." >&2
"$EC2_HOME/bin/ec2-run-instances" \
 ami-3d1f2b49 \
 -k awskey \
 --instance-type t1.micro \
 --instance-initiated-shutdown-behavior terminate \
 --user-data-file userdata.txt.gz \
 --availability-zone eu-west-1b \
 > "run-output" || { cat "run-output" >&2; exit 1; }

instance_id=`grep '^INSTANCE' "run-output" | cut -f2`
echo "instance id: $instance_id" >&2
echo $instance_id > instance_id

echo -n "waiting for instance to start" >&2
a=0
while state=$(ec2-describe-instances "$instance_id" | grep ^INSTANCE | \
    cut -f6) && [ "$state" = 'pending' ]; do
    if [ $a -gt 100 ]; then
	echo -e "\nGave up after 100 secs" >&2
	exit 1
    fi
    let a=a+1
    echo -n "." >&2
    sleep 1
done
echo "" >&2

ip=`ec2-describe-instances "$instance_id" | grep '^INSTANCE' | cut -f 17`
echo "ip: $ip" >&2
echo $ip > ip

echo "building known hosts... " >&2
(echo -n "$ip "; cat ssh_host_rsa_key.pub) > known_hosts

echo -n "waiting for boot to complete" >&2
a=0
while ! ssh -oStrictHostKeyChecking=yes -oUserKnownHostsFile=known_hosts -i id_rsa -q ubuntu@$ip \
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

