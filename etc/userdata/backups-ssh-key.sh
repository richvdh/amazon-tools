#!/bin/sh
#
# user-data init script which grants access to backup@ for root@faith 
# and root@buffy

set -e -x

mkdir -p ~backup/.ssh
cat >> ~backup/.ssh/authorized_keys <<EOF
command="rdiff-backup --server --restrict /mnt",no-port-forwarding,no-X11-forwarding,no-pty ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAn7u7ubXCvFJcv4r4xmgw7G/1ijolZzfsu43mDxZIu87MIBsxBQxmPjYZdWRxBalpS8TIgJiF0uYkJ2SYbhzXVbuJuEERBzQuo7cEKmQvBG2RfJEguRoe+6QXHa6pADbQmwNEGmEJMYj1lCdOWlgj7pz77NzJlOx6N/DMr6padtBYkNFFNbmTHXgM5/Mzs741vQZbg0lzLqC6COvtHLRy5MaEcfTn6xd+LBiKRtc7+1ttcebRWuT0Vmg9IAYkOlfPfSnnMYkugDjyTNuITN3HqKUWkN5lh+xDqupV0Xoki8QQKHe2Pi8CH/468z5yguWGsUQup/HY6E05L1PjGqobBw== root@faith
command="rdiff-backup --server --restrict /mnt",no-port-forwarding,no-X11-forwarding,no-pty ssh-dss AAAAB3NzaC1kc3MAAACBAOKEPksfAMHRtumqKaHS/oUuGU5uDTa1EfwVOVISDCMCeHdVdERGkFRkKNdqC04/SqgNB5gfNZwZ3qh8gC5+za6Uonb4dPTvhwz2wj9jF80crN+lAFWpKyL3UPcVvXl55rC+W15qiXGdYcommand="rdiff-backup --server --restrict /mnt",no-port-forwarding,no-X11-forwarding,no-pty ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC8EIgxJdhprlVW6j3TwPI3QTzCTGiTgqeJCTuWeJ9ZzA6y7lbBG5Q3GT6DgCnX7Zb++I3BTgayRFlXZ4VLJKPXOXco8TZMZFCOOnBY9jo+8IVrK6JbFDeGiW4YJ8TUK0LB/vKq2FiMXJRB3hiHhsm2FHJv+HVHN/lPnUFg5MegvDYH/n9nHm6bY3e7PKIGeXQgeRTvks/oOgAjvOeUg2H6gqo/la2hKEGiDGey7ei5ha0NNcRsGumcGjbfSrJyWvltC87OrHBinAxDDb7wfzlZPZLLdb3bvhe07SjMaSa9VoyrTG/C/hu4KQXYhYYH2ECaySnOhpZY/MUNqgcLZMAV root@storage1
command="rdiff-backup --server --restrict /mnt",no-port-forwarding,no-X11-forwarding,no-pty ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEYxhVZZ/OSKyfA87QpjC6g1cUWXvnhQQenXQRs2/jJP+ORos+zQtlZT/8uyoP7tf2u8W7kYB3S1miM05k07grQ= root@kendra
EOF

chown -R backup ~backup/.ssh
chmod 600 ~backup/.ssh/authorized_keys
chsh -s /bin/bash backup
