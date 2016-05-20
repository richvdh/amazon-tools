#!/usr/bin/env python3
#
# creates an empty snapshot, ready to receive backups.
#
# run 'aws configure' to set up credentials for this script

import boto3
import time

userdata='''#!/bin/sh
set -e
mkfs -T ext4 /dev/xvdf
mount /dev/xvdf /mnt
chown backup /mnt
poweroff
'''

def await_instance_state(client, instance_id, state):
    while True:
        resp = client.describe_instance_status(
            InstanceIds=[instance_id],
            IncludeAllInstances=True,
        )
        s = resp['InstanceStatuses'][0]['InstanceState']['Name']
        if s == state:
            print ("State now %s. Done waiting." % s)
            return
        print ("State now: %s. Waiting." % s)
        time.sleep(2)


client = boto3.client('ec2')


# start an EC2 instance, with a volume attached to it
resp = client.run_instances(
    ImageId='ami-fd6cbd8a',
    SubnetId='subnet-f423fc91',
    MinCount=1, MaxCount=1,
    InstanceType='t2.micro',
    InstanceInitiatedShutdownBehavior='stop',
    UserData=userdata,
    Placement={
        'AvailabilityZone': 'eu-west-1b',
    },
    BlockDeviceMappings=[
        {
            'DeviceName': 'xvdf',
            'Ebs': {
                'VolumeSize': 15,
                'DeleteOnTermination': True,
            },
        },
    ],
)
inst=resp['Instances'][0]
instance_id=inst['InstanceId']

print ("started instance %s" % instance_id)

# wait for it to start, and stop
await_instance_state(client, instance_id, 'stopped')

# get the volume id
resp = client.describe_instance_attribute(
    InstanceId=instance_id,
    Attribute='blockDeviceMapping',
)

volume=[bd for bd in resp['BlockDeviceMappings'] if bd['DeviceName'] == 'xvdf'][0]
volume_id=volume['Ebs']['VolumeId']
print ("volume id is %s" % volume_id)

# take a snapshot of the volume
resp = client.create_snapshot(VolumeId=volume_id)
print ("Snapshot is %s." % resp['SnapshotId'])

# and finally terminate the instance
client.terminate_instances(
    InstanceId=[instance_id],
)
