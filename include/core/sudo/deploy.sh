#!/bin/sh
# Linux Deploy Component
# (c) Anton Skshidlevsky <meefik@gmail.com>, GPLv3

do_configure()
{
    msg ":: Configuring ${COMPONENT} ... "
    local sudo_str="${USER_NAME} ALL=(ALL:ALL) NOPASSWD:ALL"
    if ! grep -q "${sudo_str}" "${CHROOT_DIR}/etc/sudoers"; then
        chmod 640 "${CHROOT_DIR}/etc/sudoers"
        echo ${sudo_str} >> "${CHROOT_DIR}/etc/sudoers"
        chmod 440 "${CHROOT_DIR}/etc/sudoers"
    fi
    if [ -e "${CHROOT_DIR}/etc/profile.d" ]; then
        echo '[ -n "$PS1" -a "$(whoami)" = "'${USER_NAME}'" ] || return 0' > "${CHROOT_DIR}/etc/profile.d/sudo.sh"
        echo 'alias su="sudo su"' >> "${CHROOT_DIR}/etc/profile.d/sudo.sh"
    fi
    return 0
}
