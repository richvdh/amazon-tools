#!/bin/sh

set -e

. ~/amazon/env
ec2-terminate-instances "$@"
