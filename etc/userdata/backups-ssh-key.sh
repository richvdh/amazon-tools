#!/bin/sh
#
# user-data init script which grants access to backup@ for root@faith 
# and root@buffy

set -e -x

mkdir -p ~backup/.ssh
cat >> ~backup/.ssh/authorized_keys <<EOF
command="rdiff-backup --server --restrict /mnt",no-port-forwarding,no-X11-forwarding,no-pty ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAn7u7ubXCvFJcv4r4xmgw7G/1ijolZzfsu43mDxZIu87MIBsxBQxmPjYZdWRxBalpS8TIgJiF0uYkJ2SYbhzXVbuJuEERBzQuo7cEKmQvBG2RfJEguRoe+6QXHa6pADbQmwNEGmEJMYj1lCdOWlgj7pz77NzJlOx6N/DMr6padtBYkNFFNbmTHXgM5/Mzs741vQZbg0lzLqC6COvtHLRy5MaEcfTn6xd+LBiKRtc7+1ttcebRWuT0Vmg9IAYkOlfPfSnnMYkugDjyTNuITN3HqKUWkN5lh+xDqupV0Xoki8QQKHe2Pi8CH/468z5yguWGsUQup/HY6E05L1PjGqobBw== root@faith
command="rdiff-backup --server --restrict /mnt",no-port-forwarding,no-X11-forwarding,no-pty ssh-dss AAAAB3NzaC1kc3MAAACBAOKEPksfAMHRtumqKaHS/oUuGU5uDTa1EfwVOVISDCMCeHdVdERGkFRkKNdqC04/SqgNB5gfNZwZ3qh8gC5+za6Uonb4dPTvhwz2wj9jF80crN+lAFWpKyL3UPcVvXl55rC+W15qiXGdYJPNY+6UE12HCvSQEGxJlBr/gUmKP7W/AAAAFQDqksbnermHCsrT7MWyCENLlgq2pwAAAIACLrfWLUUsSGL0tF9dRM0+SxrcDFAkiUEM4Auw5HJKz0vUnroxfvMzMXA2eFIDN7KrON3Ms83OYmese5mQcGRhzndyJpRqG4sX6Lp6BzumvSQoSnY+m5o+jtjOjsV7fO6b9jr5nzEkkF8Nzo42/4Mr0Mu3/6tN0AIMyrs52CEo6wAAAIBmttwLCnTeKabkPV7zlDIreLVQ1WhAVieZSxn6f3aS7Q0wDJlA8uiA4l1O8rlfSzeZfHBOoCqembxoIq84esNrHrnpQaNcDIocTT4c9aPyUB/XMjxl+AXBYX/V8kNMuMDmb2aNRAgEo8lVpUErDKjlzMneZVeQTmPA/PPG0aDmyw== root@buffy.sw1v.org
EOF

chown -R backup ~backup/.ssh
chmod 600 ~backup/.ssh/authorized_keys
