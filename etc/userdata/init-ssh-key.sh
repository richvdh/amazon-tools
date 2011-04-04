#!/bin/sh
#
# user-data init script which grants access to backup@ for root@faith.

set -e -x

mkdir -p ~backup/.ssh
cat >> ~backup/.ssh/authorized_keys <<EOF
command="rdiff-backup --server --restrict /mnt",no-port-forwarding,no-X11-forwarding,no-pty ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAn7u7ubXCvFJcv4r4xmgw7G/1ijolZzfsu43mDxZIu87MIBsxBQxmPjYZdWRxBalpS8TIgJiF0uYkJ2SYbhzXVbuJuEERBzQuo7cEKmQvBG2RfJEguRoe+6QXHa6pADbQmwNEGmEJMYj1lCdOWlgj7pz77NzJlOx6N/DMr6padtBYkNFFNbmTHXgM5/Mzs741vQZbg0lzLqC6COvtHLRy5MaEcfTn6xd+LBiKRtc7+1ttcebRWuT0Vmg9IAYkOlfPfSnnMYkugDjyTNuITN3HqKUWkN5lh+xDqupV0Xoki8QQKHe2Pi8CH/468z5yguWGsUQup/HY6E05L1PjGqobBw== root@faith
EOF

chown -R backup ~backup/.ssh
chmod 600 ~backup/.ssh/authorized_keys
