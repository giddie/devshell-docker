#!/usr/bin/env bash

set -euo pipefail

project_dir=${HOST_PROJECT_DIR:=""}
if [[ $project_dir == "" ]]; then
  echo HOST_PROJECT_DIR must be set. >&2
  exit 1
fi

cd $project_dir

host_uid=$(stat -c %u .)
host_gid=$(stat -c %g .)

group_name=$((getent group $host_gid || echo) | cut -d: -f1)
if [[ ! $group_name ]]; then
  group_name=user
  groupadd -g $host_gid user
fi

user_name=$((getent passwd $host_uid || echo) | cut -d: -f1)
if [[ ! $user_name ]]; then
  user_name=user
  useradd -mg $host_gid -u $host_uid $user_name 2> /dev/null
fi

# If the home directory is mounted as a volume, it will initially be root-owned.
chown $host_uid:$host_gid /home/$user_name

if [[ ! -f /etc/sudoers.d/user ]]; then
  echo "$user_name ALL=(ALL:ALL) ALL" > /etc/sudoers.d/user
  echo "Defaults lecture = never" > /etc/sudoers.d/lecture
  echo "$user_name:secret" | chpasswd
fi

HOME=/home/$user_name
exec setpriv \
  --reuid $host_uid \
  --regid $host_gid \
  --clear-groups \
  /usr/local/bin/entrypoint-user.sh \
  "$@"
