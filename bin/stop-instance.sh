#!/bin/sh

set -e

toolsdir=$(cd `dirname "$0"` && pwd)
wd="$1"
instance_id=`cat "$wd/instance_id"`

out=`"${toolsdir}/aws" --xml terminate-instances "$instance_id"`
if echo $out | grep -i '<error>' > /dev/null; then
    echo -e "error terminating instance:" >&2
    echo $out >&2
    exit 1
fi

rm -r "$wd"

