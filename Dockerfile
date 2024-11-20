FROM archlinux:base-devel AS dev

RUN pacman -Syu --noconfirm

RUN useradd --create-home makepkg \
  && echo "makepkg ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers.d/makepkg
USER makepkg
RUN curl https://aur.archlinux.org/cgit/aur.git/snapshot/yay.tar.gz | tar -C /home/makepkg -xz \
      && cd /home/makepkg/yay \
      && makepkg -sri --noconfirm
RUN yay -S gosu --noconfirm --removemake
USER root
RUN rm /etc/sudoers.d/makepkg \
  && userdel -r makepkg

RUN pacman -Syu --noconfirm \
  zsh
RUN rm -f /var/cache/pacman/pkg/*

COPY entrypoint.sh /usr/local/bin
COPY entrypoint-user.sh /usr/local/bin

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/zsh"]
