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

# instance ids available at
#   https://cloud-images.ubuntu.com/locator/
#
# amd64 hvm-ssd eu-west-1
AMI_ID=ami-0b7fd7bc9c6fb1c78
EC2_INSTANCE_TYPE=t2.micro
SUBNET_ID=subnet-f423fc91
if [ -z "$AMAZON_ZONE" ]; then
    # has to match the subnet ID
    AMAZON_ZONE="eu-west-1b"
fi

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

region=`echo $AMAZON_ZONE | perl -ne '/([a-z-]*[0-9])/ && print $1'`

if [ -z "$region" ]; then
    echo "unable to parse zone $AMAZON_ZONE" >&2
    exit 1
fi

echo "starting instance in zone ${AMAZON_ZONE}" >&2
set -- --region "${region}" "$@"
# set -- --availability-zone "$AMAZON_ZONE" "$@"

# make work dir
wd=`mktemp -t -d amazon.XXXXXXXX`
cd "$wd"

# set a trap so that if we have any errors, we shut down the instance again.
trap 'terminate_instance' EXIT

terminate_instance() {
    if [ -f "$wd/instance_id" ]; then
        instance_id=`cat "$wd/instance_id"`
        if [ -f "$wd/ip" ]; then
            ip=`cat "$wd/ip"`
            echo "cloud-init log follows:">&2
            ssh -oStrictHostKeyChecking=yes -oUserKnownHostsFile=known_hosts -i id_rsa ubuntu@$ip \
               cat /var/log/cloud-init.log >&2 || true
            echo "----END---" >&2
        fi

        echo "terminating instance...">&2
        "${amazon_dir}/aws" --region "$region" ec2 terminate-instances --instance-ids "$instance_id"

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
        "${amazon_dir}/aws" --region "$region" ec2 get-console-output --instance-id "$instance_id" >&2
        echo "----END---" >&2
    fi
    cd /
    rm -r "$wd"
}

# stash the aws region, for other scripts
echo "${region}" > aws_region

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


echo "starting instance..." >&2
"${amazon_dir}/aws" ec2 run-instances \
 --output text \
 --query 'Instances[*].[InstanceId]' \
 --instance-type "$EC2_INSTANCE_TYPE" \
 --instance-initiated-shutdown-behavior terminate \
 --user-data fileb://userdata.txt.gz \
 --associate-public-ip-address \
 --subnet-id "$SUBNET_ID" \
 --image-id "$AMI_ID" \
 "$@" \
 > "run-output" || { cat "run-output" >&2; exit 1; }

instance_id=`cat run-output`
echo "instance id: $instance_id" >&2

if [ -z "$instance_id" ]; then
    echo "unable to read instance-id from output:" >&2
    cat "run-output" >&2
    exit 1
fi

echo $instance_id > instance_id

echo -n "waiting for instance to start" >&2
a=0
while true; do
    "${amazon_dir}/aws" ec2 describe-instances --region "$region" \
        --output text \
        --query 'Reservations[*].Instances[*].[State.Name, PublicIpAddress]' \
        --instance-ids "$instance_id" > "run-output"

    state=`cat run-output | cut -f1`
    case "$state" in
        running)
            break
	    ;;
	pending)
	    # loop
	    ;;
	*)
            echo -e "unexpected instance state $state" >&2
            exit 1
    esac

    if [ $a -gt 200 ]; then
	echo -e "\nGave up after 200 secs" >&2
	exit 1
    fi
    let a=a+1
    echo -n "." >&2
    sleep 1
done

ip=`cat "run-output" | cut -f2`
if [ -z "$ip" -o "$ip" == "None" ]; then
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
while ! ssh \
        -M -S ssh_control -oControlPersist=yes \
        -oStrictHostKeyChecking=yes -oUserKnownHostsFile=known_hosts \
        -i id_rsa ubuntu@$ip echo ok &>/dev/null; do
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

echo -n "waiting for boot to complete" >&2
a=0
while ! ssh -S ssh_control ubuntu@$ip \
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

