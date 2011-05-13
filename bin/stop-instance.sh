#!/bin/sh

set -e

toolsdir=$(cd `dirname "$0"` && pwd)
wd="$1"
instance_id=`cat "$wd/instance_id"`
"${toolsdir}/aws" terminate-instances "$instance_id" > /dev/null
rm -r "$wd"

