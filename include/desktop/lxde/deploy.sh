#!/bin/sh
# Linux Deploy Component
# (c) Anton Skshidlevsky <meefik@gmail.com>, GPLv3

do_install()
{
    msg ":: Installing ${COMPONENT} ... "
    local packages=""
    case "${DISTRIB}:${ARCH}:${SUITE}" in
    debian:*|ubuntu:*|kali:*)
        packages="desktop-base x11-xserver-utils xfonts-base xfonts-utils lxde lxde-common menu-xdg hicolor-icon-theme gtk2-engines"
        apt_install ${packages}
    ;;
    archlinux:*)
        packages="xorg-xauth xorg-fonts-misc ttf-dejavu lxde gtk-engines"
        pacman_install ${packages}
    ;;
    fedora:*)
        packages="xorg-x11-server-utils xorg-x11-fonts-misc dejavu-* @lxde-desktop-environment"
        dnf_install ${packages}
    ;;
    esac
}

do_configure()
{
    msg ":: Configuring ${COMPONENT} ... "
    local xsession="${CHROOT_DIR}$(user_home ${USER_NAME})/.xsession"
    echo 'exec startlxde' > "${xsession}"
    # fix error "No session for pid"
    if [ -e "${CHROOT_DIR}/etc/xdg/autostart/lxpolkit.desktop" ]; then
        rm "${CHROOT_DIR}/etc/xdg/autostart/lxpolkit.desktop"
    fi
    if [ -e "${CHROOT_DIR}/usr/bin/lxpolkit" ]; then
        mv "${CHROOT_DIR}/usr/bin/lxpolkit" "${CHROOT_DIR}/usr/bin/lxpolkit.bak"
    fi
    return 0
}
