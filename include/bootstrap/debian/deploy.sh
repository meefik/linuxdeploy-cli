#!/bin/sh
# Linux Deploy Component
# (c) Anton Skshidlevsky <meefik@gmail.com>, GPLv3

[ -n "${SUITE}" ] || SUITE="jessie"

if [ -z "${ARCH}" ]
then
    case "$(get_platform)" in
    x86) ARCH="i386" ;;
    x86_64) ARCH="amd64" ;;
    arm) ARCH="armhf" ;;
    arm_64) ARCH="arm64" ;;
    esac
fi

[ -n "${SOURCE_PATH}" ] || SOURCE_PATH="http://ftp.debian.org/debian/"

apt_install()
{
    local packages="$@"
    [ -n "${packages}" ] || return 1
    (set -e
        chroot_exec -u root apt-get update -yq
        chroot_exec -u root "DEBIAN_FRONTEND=noninteractive apt-get install -yfq --no-install-recommends ${packages}"
        chroot_exec -u root apt-get clean
    exit 0)
    return $?
}

apt_repository()
{
    # Backup sources.list
    if [ -e "${CHROOT_DIR}/etc/apt/sources.list" ]; then
        cp "${CHROOT_DIR}/etc/apt/sources.list" "${CHROOT_DIR}/etc/apt/sources.list.bak"
    fi
    # Fix for resolv problem in stretch
    echo 'Debug::NoDropPrivs "true";' > "${CHROOT_DIR}/etc/apt/apt.conf.d/00no-drop-privs"
    # Fix for seccomp policy
    echo 'apt::sandbox::seccomp "false";' > "${CHROOT_DIR}/etc/apt/apt.conf.d/999seccomp-off"
    # Update sources.list
    echo "deb ${SOURCE_PATH} ${SUITE} main contrib non-free" > "${CHROOT_DIR}/etc/apt/sources.list"
    echo "deb-src ${SOURCE_PATH} ${SUITE} main contrib non-free" >> "${CHROOT_DIR}/etc/apt/sources.list"
}

do_install()
{
    is_archive "${SOURCE_PATH}" && return 0

    msg ":: Installing ${COMPONENT} ... "

    local include_packages="locales,sudo,man-db"
    local exclude_packages="init,systemd-sysv"
    #selinux_support && include_packages="${include_packages},selinux-basics"
    
    local cache_dir="${TEMP_DIR}/deploy/debian"
    
    mkdir -p "${cache_dir}"
    
    (set -e
        DEBOOTSTRAP_DIR="$(component_dir bootstrap/debian)/debootstrap"
        . "${DEBOOTSTRAP_DIR}/debootstrap" --cache-dir="${cache_dir}" --no-check-gpg --foreign --extractor=ar --arch="${ARCH}" --exclude="${exclude_packages}" --include="${include_packages}" "${SUITE}" "${CHROOT_DIR}" "${SOURCE_PATH}"
    exit 0)
    is_ok || return 1

    component_exec core/emulator core/mnt core/net

    unset DEBOOTSTRAP_DIR
    chroot_exec /debootstrap/debootstrap --no-check-gpg --second-stage
    is_ok || return 1

    msg -n "Updating repository ... "
    apt_repository
    is_ok "fail" "done"

    if [ -n "${EXTRA_PACKAGES}" ]; then
      msg "Installing extra packages: "
      apt_install ${EXTRA_PACKAGES}
      is_ok || return 1
    fi
    
    msg -n "Clearing cache ... "
    rm -f "${CHROOT_DIR}/var/cache/apt/archives"/*
    is_ok "skip" "done"

    return 0
}

do_help()
{
cat <<EOF
   --arch="${ARCH}"
     Architecture of Linux distribution, supported "armel", "armhf", "arm64", "i386" and "amd64".

   --suite="${SUITE}"
     Version of Linux distribution, supported versions "jessie", "stretch" and "buster" (also can be used "stable", "testing", "unstable" or "oldstable").

   --source-path="${SOURCE_PATH}"
     Installation source, can specify address of the repository or path to the rootfs archive.

   --extra-packages="${EXTRA_PACKAGES}"
     List of optional installation packages, separated by spaces.

EOF
}
