#!/bin/bash
#
# TODO: make this check ssh host keys? (otherwise we get intermittent
#       failures)
# TODO: use snapshots rather than an EBS volume, to enable free use of
#       availability zones (and to enable attaching at image start time)
# TODO: figure out how to get most recent ubuntu AMI

set -e

. /etc/amazon/env

# find the tools
cd `dirname "$0"`
toolsdir=`pwd`

# make temporary dir
t=`mktemp -d`
trap "cd /; rm -rf -- '$t'" EXIT
cd "$t"

echo "building user-data..." >&2
"$toolsdir/write-mime-multipart" --output=userdata.txt \
    "$@" "/etc/amazon/userdata/touch-boot-complete.conf"

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

echo -n "attaching volume" >&2
ec2-attach-volume vol-aca405c5 -i $instance_id -d /dev/sdc >/dev/null
a=0
while state=$(ec2-describe-volumes vol-aca405c5 | grep '^ATTACHMENT' | \
    cut -f5) && [ "$state" = 'attaching' ]; do
    if [ $a -gt 100 ]; then
	echo -e "\nGave up after 100 secs" >&2
	exit 1
    fi
    let a=a+1
    echo -n "." >&2
    sleep 1
done
echo "" >&2

echo -n "waiting for boot to complete" >&2
a=0
while ! ssh -o StrictHostKeyChecking=no -i /etc/amazon/keys/id_rsa -q ubuntu@$ip \
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


echo "mounting backup drive" >&2
ssh ubuntu@$ip -i /etc/amazon/keys/id_rsa sudo mount /dev/sdc1 /mnt

# finally, write the results
echo -e "instance:\t$instance_id"
echo -e "ip:\t$ip"
