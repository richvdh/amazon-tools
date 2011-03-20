#!/bin/sh

set -e

. /etc/amazon/env
ec2-terminate-instances "$@"
