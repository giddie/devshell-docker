#!/usr/bin/env bash

set -euo pipefail

project_dir=${DEVSHELL_PROJECT_DIR:=""}
if [[ $project_dir == "" ]]; then
  echo DEVSHELL_PROJECT_DIR must be set. >&2
  exit 1
fi

cd $project_dir

host_uid=$(stat -c %u .)
host_gid=$(stat -c %g .)

group_name=$((getent group $host_gid || echo) | cut -d: -f1)
if [[ ! $group_name ]]; then
  group_name=user
  groupadd -g $host_gid $group_name
fi

user_name=$((getent passwd $host_uid || echo) | cut -d: -f1)
if [[ ! $user_name ]]; then
  user_name=user
  useradd -mg $host_gid -u $host_uid $user_name 2> /dev/null
fi

# It's helpful to use the same home directory regardless of base image.
HOME=/home/user
mkdir -p $HOME
chown $host_uid:$host_gid /home/user

if [[ $host_uid == 0 ]]; then
  # The container engine is likely remapping ids, so root _is_ our user and
  # we'll just have to roll with it.
  rm -rf /root
  ln -s /home/user /root
else
  if [[ ! -f /etc/sudoers.d/user ]]; then
    usermod -d /home/user $user_name
    echo "$user_name:secret" | chpasswd

    echo "$user_name ALL=(ALL:ALL) ALL" > /etc/sudoers.d/user
    echo "Defaults lecture = never" > /etc/sudoers.d/lecture
  fi
fi

exec setpriv \
  --reuid $host_uid \
  --regid $host_gid \
  --clear-groups \
  /usr/local/bin/entrypoint-user.sh \
  "$@"
