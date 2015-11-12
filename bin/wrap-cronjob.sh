#!/bin/sh
#
# wrap a command such that output is suppressed unless the command returns an
# error

tf=`mktemp`

"$@" >"$tf" 2>&1
r=$?

if [ "$r" -ne 0 ]; then
    echo "$1 returned non-zero: $r"
    cat "$tf"
fi

rm "$tf"
exit $r

