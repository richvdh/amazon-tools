#!/bin/sh

set -e

. /etc/amazon/env

wd="$1"
instance_id=`cat "$wd/instance_id"`
ec2-terminate-instances "$instance_id"
rm -r "$wd"

