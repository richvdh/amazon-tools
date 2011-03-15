#!/bin/bash
#
# TODO: touch something when boot has completed and ssh in to check it
# TODO: make this check ssh host keys? (otherwise we get intermittent
#       failures)
# TODO: figure out how to get most recent ubuntu AMI
# TODO: remove ~/amazon from everywhere
# TODO: use snapshots rather than an EBS volume, to enable free use of
#       availability zones (and to enable attaching at image start time)

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
"$toolsdir/write-mime-multipart" --output=userdata.txt "$@"

#cat userdata.txt >&2
gzip userdata.txt

echo "starting instance..." >&2
"$EC2_HOME/bin/ec2-run-instances" \
 ami-f6340182 \
 -k awskey \
 --instance-type t1.micro \
 --instance-initiated-shutdown-behavior terminate \
 --user-data-file userdata.txt.gz \
 --availability-zone eu-west-1b \
 > "run-output" || { cat "run-output" >&2; exit 1; }

instance_id=`grep '^INSTANCE' "run-output" | cut -f2`
echo "instance id: $instance_id" >&2

echo -n "waiting for instance to start" >&2
while state=$(ec2-describe-instances "$instance_id" | grep ^INSTANCE | \
    cut -f6) && [ "$state" = 'pending' ]; do
    echo -n "." >&2
    sleep 1
done
echo "" >&2

ip=`ec2-describe-instances "$instance_id" | grep '^INSTANCE' | cut -f 17`
echo "ip: $ip" >&2

echo -n "attaching volume" >&2
ec2-attach-volume vol-aca405c5 -i $instance_id -d /dev/sdc >/dev/null
while state=$(ec2-describe-volumes vol-aca405c5 | grep '^ATTACHMENT' | \
    cut -f5) && [ "$state" = 'attaching' ]; do
    echo -n "." >&2
    sleep 1
done
echo "" >&2

echo -n "waiting for ssh to work" >&2
while ! ssh -o StrictHostKeyChecking=no -i ~/amazon/keys/id_rsa -q ubuntu@$ip true; do
   echo -n . >&2
   sleep 1
done
echo >&2

echo "mounting backup drive" >&2
ssh ubuntu@$ip -i ~/amazon/keys/id_rsa sudo mount /dev/sdc1 /mnt

# finally, write the results
echo -e "instance:\t$instance_id"
echo -e "ip:\t$ip"


