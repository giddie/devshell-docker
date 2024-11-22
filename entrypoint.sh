#!/usr/bin/env bash

set -euo pipefail

project_dir=${HOST_PROJECT_DIR:=""}
if [[ $project_dir == "" ]]; then
  echo HOST_PROJECT_DIR must be set. >&2
  exit 1
fi

cd $project_dir

host_uid=$(stat -c %u .)
host_group=$(stat -c %g .)
groupadd -g $host_group user
useradd -mg $host_group -u $host_uid user 2> /dev/null
chown $host_uid:$host_group /home/user

echo "user ALL=(ALL:ALL) ALL" > /etc/sudoers.d/user
echo "user:secret" | chpasswd

exec setpriv \
  --reuid $host_uid \
  --regid $host_group \
  --init-groups \
  --reset-env \
  /usr/local/bin/entrypoint-user.sh \
  "$@"
