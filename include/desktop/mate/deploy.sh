#!/bin/sh
# Linux Deploy Component
# (c) Anton Skshidlevsky <meefik@gmail.com>, GPLv3

do_install()
{
    msg ":: Installing ${COMPONENT} ... "
    local packages=""
    case "${DISTRIB}:${ARCH}:${SUITE}" in
    debian:*|ubuntu:*|kali:*)
        packages="desktop-base dbus-x11 x11-xserver-utils xfonts-base xfonts-utils mate-core"
        apt_install ${packages}
    ;;
    archlinux:*)
        packages="xorg-xauth xorg-fonts-misc ttf-dejavu mate"
        pacman_install ${packages}
    ;;
    fedora:*)
        packages="xorg-x11-server-utils xorg-x11-fonts-misc dejavu-* @mate-desktop-environment"
        dnf_install ${packages}
    ;;
    esac
}

do_configure()
{
    msg ":: Configuring ${COMPONENT} ... "
    local xsession="${CHROOT_DIR}$(user_home ${USER_NAME})/.xsession"
    echo 'XKL_XMODMAP_DISABLE=1' > "${xsession}"
    echo 'export XKL_XMODMAP_DISABLE' >> "${xsession}"
    echo 'exec dbus-launch --exit-with-session mate-session' >> "${xsession}"
    return 0
}
