#!/bin/sh
# Linux Deploy Component
# (c) Anton Skshidlevsky <meefik@gmail.com>, GPLv3

get_qemu()
{
    local arch="$1"
    local qemu=""
    local host_platform=$(get_platform)
    local guest_platform=$(get_platform "${arch}")
    if [ "${host_platform}" != "${guest_platform}" ]; then
        case "${guest_platform}" in
        arm) qemu="qemu-arm-static" ;;
        arm_64) qemu="qemu-aarch64-static" ;;
        x86) qemu="qemu-i386-static" ;;
        x86_64) qemu="qemu-x86_64-static" ;;
        *) qemu="" ;;
        esac
    fi
    echo ${qemu}
}

[ -n "${EMULATOR}" ] || EMULATOR=$(get_qemu ${ARCH})

do_configure()
{
    do_start

    return 0
}

do_start()
{
    [ -n "${EMULATOR}" -a "${METHOD}" = "chroot" ] || return 0
    multiarch_support || return 0

    msg -n ":: Starting ${COMPONENT} ... "
    local source_path=$(which ${EMULATOR})
    local target_path="/usr/bin/${EMULATOR}"
    if [ ! -e "${CHROOT_DIR}${target_path%/*}" ]; then
        mkdir -p "${CHROOT_DIR}${target_path%/*}"
    fi
    if [ ! -e "${CHROOT_DIR}${target_path}" ]; then
        touch "${CHROOT_DIR}${target_path}"
    fi
    if ! is_mounted "${CHROOT_DIR}${target_path}"
    then
        mount -o bind "${source_path}" "${CHROOT_DIR}${target_path}"
    fi
    case "${EMULATOR}" in
    qemu-i386*)
        if [ ! -e "/proc/sys/fs/binfmt_misc/qemu-i386" ]; then
            echo ":qemu-i386:M::\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x03\x00:\xff\xff\xff\xff\xff\xfe\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:${target_path}:" > "/proc/sys/fs/binfmt_misc/register"
            is_ok "fail" "done"
        else
            msg "skip"
        fi
    ;;
    qemu-x86_64*)
        if [ ! -e "/proc/sys/fs/binfmt_misc/qemu-x86_64" ]; then
            echo ":qemu-x86_64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3e\x00:\xff\xff\xff\xff\xff\xfe\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:${target_path}:" > "/proc/sys/fs/binfmt_misc/register"
            is_ok "fail" "done"
        else
            msg "skip"
        fi
    ;;
    qemu-arm*)
        if [ ! -e "/proc/sys/fs/binfmt_misc/qemu-arm" ]; then
            echo ":qemu-arm:M::\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:${target_path}:" > "/proc/sys/fs/binfmt_misc/register"
            is_ok "fail" "done"
        else
            msg "skip"
        fi
    ;;
    qemu-aarch64*)
        if [ ! -e "/proc/sys/fs/binfmt_misc/qemu-aarch64" ]; then
            echo ":qemu-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:${target_path}:" > "/proc/sys/fs/binfmt_misc/register"
            is_ok "fail" "done"
        else
            msg "skip"
        fi
    ;;
    *)
        msg "skip"
    ;;
    esac

    return 0
}

do_stop()
{
    [ -n "${EMULATOR}" -a "${METHOD}" = "chroot" ] || return 0
    multiarch_support || return 0

    msg -n ":: Stopping ${COMPONENT} ... "
    local target_path="/usr/bin/${EMULATOR}"
    if is_mounted "${CHROOT_DIR}${target_path}"
    then
        umount "${CHROOT_DIR}${target_path}"
    fi
    case "${EMULATOR}" in
    qemu-i386*)
        if [ -e "/proc/sys/fs/binfmt_misc/qemu-i386" ]; then
            echo -1 > /proc/sys/fs/binfmt_misc/qemu-i386
            is_ok "fail" "done"
        else
            msg "skip"
        fi
    ;;
    qemu-x86_64*)
        if [ -e "/proc/sys/fs/binfmt_misc/qemu-x86_64" ]; then
            echo -1 > /proc/sys/fs/binfmt_misc/qemu-x86_64
            is_ok "fail" "done"
        else
            msg "skip"
        fi
    ;;
    qemu-arm*)
        if [ -e "/proc/sys/fs/binfmt_misc/qemu-arm" ]; then
            echo -1 > /proc/sys/fs/binfmt_misc/qemu-arm
            is_ok "fail" "done"
        else
            msg "skip"
        fi
    ;;
    qemu-aarch64*)
        if [ -e "/proc/sys/fs/binfmt_misc/qemu-aarch64" ]; then
            echo -1 > /proc/sys/fs/binfmt_misc/qemu-aarch64
            is_ok "fail" "done"
        else
            msg "skip"
        fi
    ;;
    *)
        msg "skip"
    ;;
    esac
    return 0
}

do_help()
{
cat <<EOF
   --emulator="${EMULATOR}"
     Specify which to use the emulator, by default QEMU.

EOF
}
