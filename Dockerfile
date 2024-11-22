FROM archlinux:base-devel AS dev

RUN pacman -Syu --noconfirm

RUN useradd --create-home makepkg \
  && echo "makepkg ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers.d/makepkg
USER makepkg
RUN curl https://aur.archlinux.org/cgit/aur.git/snapshot/yay.tar.gz | tar -C /home/makepkg -xz \
      && cd /home/makepkg/yay \
      && makepkg -sri --noconfirm \
      && rm -rf /home/makepkg/{*,.cache,.config} \
      && sudo rm -f /var/cache/pacman/pkg/*

# # AUR Packages
# RUN yay --noconfirm --removemake -S \
#   package1 \
#   package2 \
#   && sudo rm -rf /home/makepkg/{*,.*} \
#   && sudo rm -f /var/cache/pacman/pkg/*

USER root
RUN rm /etc/sudoers.d/makepkg \
  && userdel -r makepkg

# Pacman Packages
RUN pacman -Syu --noconfirm \
  zsh \
  && rm -f /var/cache/pacman/pkg/*

COPY entrypoint.sh /usr/local/bin
COPY entrypoint-user.sh /usr/local/bin

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/zsh"]
