#!/bin/sh
# Linux Deploy Component
# (c) Anton Skshidlevsky <meefik@gmail.com>, GPLv3

do_install()
{
    msg ":: Installing ${COMPONENT} ... "
    local packages=""
    case "${DISTRIB}:${ARCH}:${SUITE}" in
    debian:*|ubuntu:*|kalilinux:*)
        packages="dbus"
        apt_install ${packages}
    ;;
    archlinux:*)
        packages="dbus"
        pacman_install ${packages}
    ;;
    fedora:*)
        packages="dbus"
        dnf_install ${packages}
    ;;
    centos:*)
        packages="dbus"
        yum_install ${packages}
    ;;
    gentoo:*)
        packages="sys-apps/dbus"
        emerge_install ${packages}
    ;;
    esac
}

do_configure()
{
    msg ":: Configuring ${COMPONENT} ... "
    make_dirs /run/dbus /var/run/dbus
    chmod 644 "${CHROOT_DIR}/etc/machine-id"
    chroot_exec -u root dbus-uuidgen > "${CHROOT_DIR}/etc/machine-id"
    case "${DISTRIB}:${ARCH}:${SUITE}" in
    archlinux:*)
        local user_names="systemd-timesync systemd-network colord systemd-resolve polkitd avahi dbus"
        for username in ${user_names}
        do
            chroot_exec -u root groupadd -f ${username}
            chroot_exec -u root useradd -g ${username} -s /bin/false ${username}
        done

        chroot_exec -u root groupadd -f network
    ;;
    esac
    return 0
}

do_start()
{
    msg -n ":: Starting ${COMPONENT} ... "
    is_stopped /run/dbus/pid /run/dbus/messagebus.pid /run/messagebus.pid /var/run/dbus/pid /var/run/dbus/messagebus.pid /var/run/messagebus.pid
    is_ok "skip" || return 0
    remove_files /run/dbus/pid /run/dbus/messagebus.pid /run/messagebus.pid /var/run/dbus/pid /var/run/dbus/messagebus.pid /var/run/messagebus.pid
    chroot_exec -u root dbus-daemon --system --fork
    is_ok "fail" "done"
    return 0
}

do_stop()
{
    msg -n ":: Stopping ${COMPONENT} ... "
    kill_pids /run/dbus/pid /run/dbus/messagebus.pid /run/messagebus.pid /var/run/dbus/pid /var/run/dbus/messagebus.pid /var/run/messagebus.pid
    is_ok "fail" "done"
    return 0
}

do_status()
{
    msg -n ":: ${COMPONENT} ... "
    is_started /run/dbus/pid /run/dbus/messagebus.pid /run/messagebus.pid /var/run/dbus/pid /var/run/dbus/messagebus.pid /var/run/messagebus.pid
    is_ok "stopped" "started"
    return 0
}
