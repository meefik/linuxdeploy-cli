#!/bin/sh
# Linux Deploy Component
# (c) Anton Skshidlevsky <meefik@gmail.com>, GPLv3

[ -n "${SUITE}" ] || SUITE="latest-stable"

if [ -z "${ARCH}" ]
then
    case "$(get_platform)" in
    x86) ARCH="x86" ;;
    x86_64) ARCH="x86_64" ;;
    arm) ARCH="armhf" ;;
    arm_64) ARCH="aarch64" ;;
    esac
fi

[ -n "${SOURCE_PATH}" ] || SOURCE_PATH="http://dl-cdn.alpinelinux.org/alpine/"

apk_install()
{
    local packages="$@"
    [ -n "${packages}" ] || return 1
    (set -e
        chroot_exec -u root apk update || true
        chroot_exec -u root apk add ${packages}
    exit 0)
    return $?
}

do_install()
{
    is_archive "${SOURCE_PATH}" && return 0

    msg ":: Installing ${COMPONENT} ... "

    msg -n "Retrieving rootfs archive ... "
    local repo_url="${SOURCE_PATH%/}/${SUITE}"
    local rootfs_name=$(wget -q -O - "${repo_url}/releases/${ARCH}/latest-releases.yaml" | grep -m1 "file: alpine-minirootfs" | awk '{print $2}')
    wget -q -O - "${repo_url}/releases/${ARCH}/${rootfs_name}" | tar xz -C "${CHROOT_DIR}"
    is_ok "fail" "done" || return 1

    component_exec core/emulator core/mnt core/net

    msg "Installing packages: "
    apk_install shadow sudo tzdata ${EXTRA_PACKAGES}
    is_ok || return 1

    return 0
}

do_help()
{
cat <<EOF
   --arch="${ARCH}"
     Architecture of Linux distribution, supported "aarch64", "armhf", "x86" and "x86_64".

   --suite="${SUITE}"
     Version of Linux distribution, supported version "latest-stable", "edge".

   --source-path="${SOURCE_PATH}"
     Installation source, can specify address of the repository or path to the rootfs archive.

   --extra-packages="${EXTRA_PACKAGES}"
     List of optional installation packages, separated by spaces.

EOF
}
