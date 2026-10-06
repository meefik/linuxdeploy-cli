#!/bin/bash
################################################################################
#
# Linux Deploy CLI
# (C) 2012-2019 Anton Skshidlevsky <meefik@gmail.com>, GPLv3
#
################################################################################

VERSION="2.5.1"

################################################################################
# Common
################################################################################

msg()
{
    echo "$@"
}

is_ok()
{
    if [ $? -eq 0 ]; then
        if [ -n "$2" ]; then
            msg "$2"
        fi
        return 0
    else
        if [ -n "$1" ]; then
            msg "$1"
        fi
        return 1
    fi
}

get_platform()
{
    local arch="$1"
    if [ -z "${arch}" ]; then
        arch=$(uname -m)
    fi
    case "${arch}" in
    arm64|aarch64)
        echo "arm_64"
    ;;
    arm*)
        echo "arm"
    ;;
    x86_64|amd64)
        echo "x86_64"
    ;;
    i[3-6]86|x86)
        echo "x86"
    ;;
    *)
        echo "unknown"
    ;;
    esac
}

get_uuid()
{
    cat /proc/sys/kernel/random/uuid
}

multiarch_support()
{
    if [ -d "/proc/sys/fs/binfmt_misc" ]; then
        return 0
    else
        return 1
    fi
}

selinux_inactive()
{
    if [ -e "/sys/fs/selinux/enforce" ]; then
        return $(cat /sys/fs/selinux/enforce)
    else
        return 0
    fi
}

loop_support()
{
    if [ -n "$(losetup -f)" ]; then
        return 0
    else
        return 1
    fi
}

user_home()
{
    [ -e "${CHROOT_DIR}/etc/passwd" ] || return 1
    local user_name="$1"
    [ -n "${user_name}" ] || return 1
    echo $(grep -m1 "^${user_name}:" "${CHROOT_DIR}/etc/passwd" | awk -F: '{print $6}')
}

user_shell()
{
    [ -e "${CHROOT_DIR}/etc/passwd" ] || return 1
    local user_name="$1"
    [ -n "${user_name}" ] || return 1
    echo $(grep -m1 "^${user_name}:" "${CHROOT_DIR}/etc/passwd" | awk -F: '{print $7}')
}

is_mounted()
{
    local mount_point="$1"
    [ -n "${mount_point}" ] || return 1
    mount_point="${mount_point%/}"
    [ -n "${mount_point}" ] || mount_point="/"
    awk -v m="${mount_point}" '$2 == m {found=1; exit} END {exit !found}' /proc/mounts
}

list_chroot_mounts()
{
    # List descendants only, deepest first, so nested bind mounts are released
    # before their parents. Linux Deploy mount targets normally contain no
    # whitespace; /proc/mounts escapes whitespace when present.
    awk -v root="${CHROOT_DIR%/}/" 'index($2, root) == 1 {print length($2), $2}' /proc/mounts |
        sort -k1,1nr -k2,2r |
        awk '{ $1=""; sub(/^ /,""); print }'
}

is_archive()
{
    local src="$1"
    [ -n "${src}" ] || return 1
    if [ -z "${src##*gz}" -o -z "${src##*bz2}" -o -z "${src##*xz}" ]; then
        return 0
    fi
    return 1
}

get_pids()
{
    local pidfile pid pids proc_root
    for pidfile in $*
    do
        pidfile="${CHROOT_DIR}${pidfile}"
        [ -e "${pidfile}" ] || continue
        pid=$(cat "${pidfile}" 2>/dev/null)
        case "${pid}" in
            ''|*[!0-9]*) continue ;;
        esac
        [ -d "/proc/${pid}" ] || continue

        # A stale PID file can point to a PID that Android has already reused.
        # For real chroots, only accept a process whose root is this container.
        if [ "${METHOD}" = "chroot" ]; then
            proc_root=$(readlink "/proc/${pid}/root" 2>/dev/null)
            [ "${proc_root}" = "${CHROOT_DIR%/}" ] || continue
        fi

        pids="${pids} ${pid}"
    done
    if [ -n "${pids}" ]; then
        echo ${pids}
        return 0
    else
        return 1
    fi
}

is_started()
{
    get_pids $* >/dev/null
}

is_stopped()
{
    is_started $*
    test $? -ne 0
}

kill_pids()
{
    local pids=$(get_pids $*)
    if [ -n "${pids}" ]; then
        kill -9 ${pids}
        return $?
    fi
    return 0
}

remove_files()
{
    local item target
    for item in $*
    do
        target="${CHROOT_DIR}${item}"
        if [ -e "${target}" ]; then
            rm -f "${target}"
        fi
    done
    return 0
}

make_dirs()
{
    local item target
    for item in $*
    do
        target="${CHROOT_DIR}${item}"
        if [ -d "${target%/*}" -a ! -d "${target}" ]; then
            mkdir "${target}"
        fi
    done
    return 0
}

chroot_exec()
{
    unset TMP TEMP TMPDIR LD_PRELOAD LD_DEBUG
    local path="${PATH}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    if [ "$1" = "-u" ]; then
        local username="$2"
        shift 2
    fi
    case "${METHOD}" in
    chroot)
        if [ -n "${username}" ]; then
            if [ $# -gt 0 ]; then
                chroot "${CHROOT_DIR}" /bin/su - ${username} -c "$*"
            else
                chroot "${CHROOT_DIR}" /bin/su - ${username}
            fi
        else
            PATH="${path}" chroot "${CHROOT_DIR}" $*
        fi
    ;;
    proot)
        if [ -z "${PROOT_TMP_DIR}" ]; then
            export PROOT_TMP_DIR="${TEMP_DIR}"
        fi
        local mounts="-b /proc -b /dev -b /sys"
        if [ -n "${MOUNTS}" ]; then
            mounts="${mounts} -b ${MOUNTS// / -b }"
        fi
        local emulator
        if [ -n "${EMULATOR}" ]; then
            emulator="-q ${EMULATOR}"
        fi
        if [ -n "${username}" ]; then
            if [ $# -gt 0 ]; then
                proot -r "${CHROOT_DIR}" -w / ${mounts} ${emulator} -0 -l -e /bin/su - ${username} -c "$*"
            else
                proot -r "${CHROOT_DIR}" -w / ${mounts} ${emulator} -0 -l -e /bin/su - ${username}
            fi
        else
            PATH="${path}" proot -r "${CHROOT_DIR}" -w / ${mounts} ${emulator} -0 -l -e $*
        fi
    ;;
    esac
}

################################################################################
# Params
################################################################################

params_read()
{
    local conf_file="$1"
    [ -e "${conf_file}" ] || return 1
    local item key val
    while read item
    do
        key=$(echo ${item} | grep -o '^[0-9A-Z_]\{1,32\}')
        val=${item#${key}=}
        if [ -n "${key}" ]; then
            eval ${key}="${val}"
            if [ -n "${OPTLST##* ${key} *}" ]; then
                OPTLST="${OPTLST}${key} "
            fi
        fi
    done < ${conf_file}
}

params_write()
{
    local conf_file="$1"
    [ -n "${conf_file}" ] || return 1
    echo "# ${conf_file##*/} $(date '+%F %R')" > ${conf_file}
    local key val
    for key in ${OPTLST}
    do
        eval "val=\$${key}"
        if [ -n "${key}" -a -n "${val}" ]; then
            echo "${key}=\"${val}\"" >> ${conf_file}
        fi
    done
}

params_parse()
{
    OPTIND=1
    if [ $# -gt 0 ] ; then
        local item key val
        for item in "$@"
        do
            key=$(expr "${item}" : '--\([0-9a-z-]\{1,32\}=\{0,1\}\)' | sed 'y/-abcdefghijklmnopqrstuvwxyz/_ABCDEFGHIJKLMNOPQRSTUVWXYZ/')
            if [ -n "${key##*=*}" ]; then
                val="true"
            else
                key=${key%*=}
                val=$(expr "${item}" : '--[0-9a-z-]\{1,32\}=\(.*\)')
            fi
            if [ -n "${key}" ]; then
                eval ${key}=\"${val}\"
                let OPTIND=OPTIND+1
                if [ -n "${OPTLST##* ${key} *}" ]; then
                    OPTLST="${OPTLST}${key} "
                fi
            fi
        done
    fi
    #echo ${OPTLST} | tr ' ' '\n' | awk '!x[$0]++'
}

params_check()
{
    local params_list="$@"
    local key val params_lost
    for key in ${params_list}
    do
        eval "val=\$${key}"
        if [ -z "${val}" ]; then
            params_lost="${params_lost} ${key}"
        fi
    done
    if [ -n "${params_lost}" ]; then
        msg "Missing parameters:${params_lost}"
        return 1
    fi
    return 0
}


################################################################################
# Configs
################################################################################

config_which()
{
    local conf_file="$1"
    if [ -n "${conf_file}" ]; then
        if [ -n "${conf_file##*/*}" ]; then
            conf_file="${CONFIG_DIR}/${conf_file}.conf"
        fi
        echo "${conf_file}"
    fi
}

config_update()
{
    local source_conf="$1"; shift
    local target_conf="$1"; shift
    params_read "${source_conf}"
    params_parse "$@"
    params_write "${target_conf}"
}

config_list()
{
    local conf_file="$1"
    local conf
    for conf in $(ls "${CONFIG_DIR}/")
    do
        (
            unset DISTRIB ARCH SUITE INCLUDE
            . "${CONFIG_DIR}/${conf}"
            formated_desc=$(printf "%-15s %-10s %-10s %-10s %.30s\n" "${conf%.conf}" "${DISTRIB}" "${ARCH}" "${SUITE}" "${INCLUDE}")
            msg "${formated_desc}"
        )
    done
}

config_remove()
{
    local conf_file="$1"
    if [ -e "${conf_file}" ]; then
        rm -f "${conf_file}"
    else
        return 1
    fi
}

################################################################################
# Components
################################################################################

component_is_compatible()
{
    local target="$@"
    [ -n "${target}" ] || return 0
    local item
    for item in ${target}
    do
        case "${DISTRIB}:${ARCH}:${SUITE}" in
        ${item})
            return 0
        ;;
        esac
    done
    return 1
}

component_is_exclude()
{
    local component="$1"
    [ -n "${component}" ] || return 1
    for item in ${EXCLUDE_COMPONENTS}
    do
        case "${component}" in
        ${item}*)
            return 0
        ;;
        esac
    done
    return 1
}

component_depends()
{
    local components="$@"
    [ -n "${components}" ] || return 0
    local component conf_file TARGET DEPENDS
    for component in ${components}
    do
        component="${component%/}"
        # check deadlocks
        [ -z "${IGNORE_DEPENDS##* ${component} *}" ] && continue
        IGNORE_DEPENDS="${IGNORE_DEPENDS}${component} "
        # check component exist
        conf_file="${INCLUDE_DIR}/${component}/deploy.conf"
        [ -e "${conf_file}" ] || continue
        # read component variables
        eval $(grep -e '^TARGET=' -e '^DEPENDS=' "${conf_file}")
        # check compatibility
        if [ "${WITHOUT_CHECK}" != "true" ]; then
            component_is_compatible ${TARGET} || continue
        fi
        if [ "${REVERSE_DEPENDS}" = "true" ]; then
            # output
            echo ${component}
            # process depends
            component_depends ${DEPENDS}
        else
            # process depends
            component_depends ${DEPENDS}
            # output
            echo ${component}
        fi
    done
}

component_exec()
{
    local components="$@"
    if [ "${WITHOUT_DEPENDS}" != "true" ]; then
        components=$(IGNORE_DEPENDS=" " component_depends ${components})
    fi
    [ -n "${components}" ] || return 1
    (set -e
        for COMPONENT in ${components}
        do
            COMPONENT_DIR="${INCLUDE_DIR}/${COMPONENT}"
            [ -d "${COMPONENT_DIR}" ] || continue
            unset NAME DESC TARGET PARAMS DEPENDS EXTENDS
            TARGET='*:*:*'
            # read config
            . "${COMPONENT_DIR}/deploy.conf"
            # default functions
            do_install() { return 0; }
            do_configure() { return 0; }
            do_start() { return 0; }
            do_stop() { return 0; }
            do_status() { return 0; }
            do_help() { return 0; }
            # load extends
            for component in ${EXTENDS} ${COMPONENT}
            do
                if [ -e "${INCLUDE_DIR}/${component}/deploy.sh" ]; then
                    . "${INCLUDE_DIR}/${component}/deploy.sh"
                fi
            done
            # exclude components
            component_is_exclude ${COMPONENT} && continue
            # check parameters
            [ "${WITHOUT_CHECK}" != "true" ] && params_check ${PARAMS}
            # exec action
            [ "${DEBUG_MODE}" = "true" ] && msg "## ${COMPONENT} : ${DO_ACTION}"
            set +e
            eval ${DO_ACTION} || exit 1
            set -e
        done
    exit 0)
    is_ok || return 1
}

component_list()
{
    local components="$@"
    local component output DESC
    if [ -z "${components}" ]; then
        components=$(cd "${INCLUDE_DIR}" && find . -type f -name "deploy.conf" | while read f
            do
                component="${f%/*}"
                component="${component#*/}"
                echo "${component}"
            done)
    fi
    components=$(IGNORE_DEPENDS=" " component_depends ${components} | sort)
    for component in $components
    do
        # output
        DESC=''
        eval $(grep '^DESC=' "${INCLUDE_DIR}/${component}/deploy.conf")
        output=$(printf "%-30s %.49s\n" "${component}" "${DESC}")
        msg "${output}"
    done
}

component_dir() {
    echo "${INCLUDE_DIR}/$1"
}

################################################################################
# Containers
################################################################################

container_mounted()
{
    if [ "${METHOD}" = "chroot" ]; then
        is_mounted "${CHROOT_DIR}"
    else
        return 0
    fi
}

fs_check()
{
    is_mounted "${CHROOT_DIR}" && return 254

    local checkfs
    checkfs=$(command -v e2fsck 2>/dev/null) || return 254
    [ -n "${checkfs}" ] || return 254

    case "${TARGET_TYPE}" in
        file|partition)
            "${checkfs}" -p "${TARGET_PATH}" >/dev/null 2>&1
            return $?
        ;;
    esac
    return 254
}

mount_part()
{
    case "$1" in
    root)
        msg -n "/ ... "
        if ! is_mounted "${CHROOT_DIR}" ; then
            [ -d "${CHROOT_DIR}" ] || mkdir -p "${CHROOT_DIR}"
            local mnt_opts
            [ -d "${TARGET_PATH}" ] && mnt_opts="bind" || mnt_opts="rw,relatime"
            mount -o ${mnt_opts} "${TARGET_PATH}" "${CHROOT_DIR}" &&
            mount -o remount,exec,suid,dev "${CHROOT_DIR}"
            is_ok "fail" "done" || return 1
        else
            msg "skip"
        fi
    ;;
    proc)
        msg -n "/proc ... "
        local target="${CHROOT_DIR}/proc"
        if ! is_mounted "${target}" ; then
            [ -d "${target}" ] || mkdir -p "${target}"
            mount -t proc proc "${target}"
            is_ok "fail" "done"
        else
            msg "skip"
        fi
    ;;
    sys)
        msg -n "/sys ... "
        local target="${CHROOT_DIR}/sys"
        if ! is_mounted "${target}" ; then
            [ -d "${target}" ] || mkdir -p "${target}"
            mount -t sysfs sys "${target}"
            is_ok "fail" "done"
        else
            msg "skip"
        fi
    ;;
    dev)
        msg -n "/dev ... "
        local target="${CHROOT_DIR}/dev"
        if ! is_mounted "${target}" ; then
            [ -d "${target}" ] || mkdir -p "${target}"
            mount -o bind /dev "${target}"
            is_ok "fail" "done"
        else
            msg "skip"
        fi
    ;;
    shm)
        msg -n "/dev/shm ... "
        if ! is_mounted "/dev/shm" ; then
            [ -d "/dev/shm" ] || mkdir -p /dev/shm
            mount -o rw,nosuid,nodev,mode=1777 -t tmpfs tmpfs /dev/shm
        fi
        local target="${CHROOT_DIR}/dev/shm"
        if ! is_mounted "${target}" ; then
            mount -o bind /dev/shm "${target}"
            is_ok "fail" "done"
        else
            msg "skip"
        fi
    ;;
    pts)
        msg -n "/dev/pts ... "
        if ! is_mounted "/dev/pts" ; then
            [ -d "/dev/pts" ] || mkdir -p /dev/pts
            mount -o rw,nosuid,noexec,gid=5,mode=620,ptmxmode=000 -t devpts devpts /dev/pts
        fi
        local target="${CHROOT_DIR}/dev/pts"
        if ! is_mounted "${target}" ; then
            mount -o bind /dev/pts "${target}"
            is_ok "fail" "done"
        else
            msg "skip"
        fi
    ;;
    fd)
        if [ ! -e "/dev/fd" -o ! -e "/dev/stdin" -o ! -e "/dev/stdout" -o ! -e "/dev/stderr" ]; then
            msg -n "/dev/fd ... "
            [ -e "/dev/fd" ] || ln -s /proc/self/fd /dev/
            [ -e "/dev/stdin" ] || ln -s /proc/self/fd/0 /dev/stdin
            [ -e "/dev/stdout" ] || ln -s /proc/self/fd/1 /dev/stdout
            [ -e "/dev/stderr" ] || ln -s /proc/self/fd/2 /dev/stderr
            is_ok "fail" "done"
        fi
    ;;
    tty)
        if [ ! -e "/dev/tty0" ]; then
            msg -n "/dev/tty ... "
            ln -s /dev/null /dev/tty0
            is_ok "fail" "done"
        fi
    ;;
    tun)
        if [ ! -e "/dev/net/tun" ]; then
            msg -n "/dev/net/tun ... "
            [ -d "/dev/net" ] || mkdir -p /dev/net
            mknod /dev/net/tun c 10 200
            is_ok "fail" "done"
        fi
    ;;
    binfmt_misc)
        multiarch_support || return 0
        local binfmt_dir="/proc/sys/fs/binfmt_misc"
        if ! is_mounted "${binfmt_dir}" ; then
            msg -n "${binfmt_dir} ... "
            mount -t binfmt_misc binfmt_misc "${binfmt_dir}"
            is_ok "fail" "done"
        fi
    ;;
    esac

    return 0
}

container_mount()
{
    [ "${METHOD}" = "chroot" ] || return 0

    if [ $# -eq 0 ]; then
        container_mount root proc sys dev shm pts fd tty tun binfmt_misc
        return $?
    fi

    params_check TARGET_PATH || return 1

    msg -n "Checking file system ... "
    fs_check
    local fs_rc=$?
    case "${fs_rc}" in
        0)   msg "done" ;;
        1)   msg "corrected" ;;
        2|3) msg "corrected (reboot/recheck indicated)" ;;
        254) msg "skip" ;;
        *)
            msg "fail (e2fsck rc=${fs_rc})"
            return 1
        ;;
    esac

    msg "Mounting the container: "
    local item
    for item in $*
    do
        mount_part ${item} || return 1
    done

    return 0
}

pid_is_chrooted_here()
{
    local pid="$1" proc_root
    case "${pid}" in ''|*[!0-9]*) return 1 ;; esac
    [ -d "/proc/${pid}" ] || return 1
    proc_root=$(readlink "/proc/${pid}/root" 2>/dev/null)
    case "${proc_root}" in
        "${CHROOT_DIR%/}"|"${CHROOT_DIR%/}"/*) return 0 ;;
    esac
    return 1
}

fuser_available()
{
    command -v fuser >/dev/null 2>&1 && return 0
    if command -v busybox >/dev/null 2>&1; then
        busybox --list 2>/dev/null | grep -qx 'fuser' && return 0
    fi
    return 1
}

run_fuser()
{
    if command -v fuser >/dev/null 2>&1; then
        command fuser "$@"
        return $?
    fi
    if command -v busybox >/dev/null 2>&1 && busybox --list 2>/dev/null | grep -qx 'fuser'; then
        busybox fuser "$@"
        return $?
    fi
    return 127
}

release_mount_fuser()
{
    # fuser -m can report host processes for shared bind-mounted filesystems.
    # Treat its output only as candidates and kill processes whose /proc root
    # proves they are actually inside this chroot.
    local part="$1" pids pid comm valid="" foreign=""

    fuser_available || return 2
    pids=$(run_fuser -m "${part}" 2>/dev/null || true)
    [ -n "${pids}" ] || return 1

    for pid in ${pids}
    do
        case "${pid}" in ''|*[!0-9]*) continue ;; esac
        [ "${pid}" = "$$" ] && continue
        [ "${pid}" = "${PPID}" ] && continue
        if pid_is_chrooted_here "${pid}"; then
            valid="${valid} ${pid}"
        else
            foreign="${foreign} ${pid}"
        fi
    done

    if [ -n "${valid}" ]; then
        msg -n "fuser chroot holders:"
        for pid in ${valid}
        do
            comm=""
            IFS= read -r comm < "/proc/${pid}/comm" 2>/dev/null || true
            msg -n " ${pid}${comm:+(${comm})}"
        done
        msg ""
        for pid in ${valid}
        do
            kill -KILL "${pid}" 2>/dev/null || true
        done
        sleep 0.10
    fi

    if [ -n "${foreign}" ]; then
        msg -n "fuser ignored non-chroot holders:"
        for pid in ${foreign}
        do
            comm=""
            IFS= read -r comm < "/proc/${pid}/comm" 2>/dev/null || true
            msg -n " ${pid}${comm:+(${comm})}"
        done
        msg ""
    fi

    [ -n "${valid}" ] && return 0
    return 3
}

pid_holds_chroot()
{
    local pid="$1" link fd target root="${CHROOT_DIR%/}"
    case "${pid}" in ''|*[!0-9]*) return 1 ;; esac
    [ -d "/proc/${pid}" ] || return 1
    [ "${pid}" = "$$" ] && return 1
    [ "${pid}" = "${PPID}" ] && return 1

    for link in root cwd
    do
        target=$(readlink "/proc/${pid}/${link}" 2>/dev/null || true)
        case "${target}" in
            "${root}"|"${root}"/*) return 0 ;;
        esac
    done

    for fd in /proc/${pid}/fd/*
    do
        [ -e "${fd}" -o -L "${fd}" ] || continue
        target=$(readlink "${fd}" 2>/dev/null || true)
        target=${target% (deleted)}
        case "${target}" in
            "${root}"|"${root}"/*) return 0 ;;
        esac
    done
    return 1
}

pid_descendants_of()
{
    # Lightweight parent/child snapshot. Unlike pid_holds_chroot(), this does
    # not inspect cwd/root/fds; it only reads /proc/PID/stat with shell builtins.
    # It is used after the one expensive holder scan so descendant discovery
    # does not repeat that scan's cost.
    local seeds="$*" proc pid stat rest ppid parents="" descendants="" frontier next

    for proc in /proc/[0-9]*
    do
        [ -r "${proc}/stat" ] || continue
        pid=${proc##*/}
        stat=""
        IFS= read -r stat < "${proc}/stat" 2>/dev/null || continue
        rest=${stat##*) }
        [ "${rest}" != "${stat}" ] || continue
        # /proc/PID/stat after the closing comm field begins: state ppid ...
        set -- ${rest}
        ppid=${2:-0}
        case "${ppid}" in ''|*[!0-9]*) ppid=0 ;; esac
        parents="${parents} ${pid}:${ppid}"
    done

    frontier="${seeds}"
    while [ -n "${frontier}" ]
    do
        next=""
        for proc in ${parents}
        do
            pid=${proc%%:*}
            ppid=${proc#*:}
            case " ${frontier} " in
                *" ${ppid} "*)
                    case " ${seeds} ${descendants} " in
                        *" ${pid} "*) ;;
                        *) descendants="${descendants} ${pid}"; next="${next} ${pid}" ;;
                    esac
                ;;
            esac
        done
        frontier="${next}"
    done

    printf '%s
' "${descendants}"
}

release_chroot_pid_scan()
{
    # Slow explicit fallback used only when requested with -k. Perform one
    # expensive /proc holder scan (root/cwd/fds), then one much lighter PPID
    # snapshot to include the holders' current descendants. This avoids a
    # second expensive holder scan in the normal recovery path.
    local proc pid comm holders="" descendants="" tracked=""

    for proc in /proc/[0-9]*
    do
        [ -d "${proc}" ] || continue
        pid=${proc##*/}
        if pid_holds_chroot "${pid}"; then
            case " ${holders} " in *" ${pid} "*) ;; *) holders="${holders} ${pid}" ;; esac
        fi
    done

    [ -n "${holders}" ] || return 1

    # Snapshot descendants immediately after identifying the holders. This
    # catches helper children such as a shell's current sleep process without
    # repeating the expensive root/cwd/fd checks for every PID.
    descendants=$(pid_descendants_of ${holders})

    msg -n "PID-scan chroot holders:"
    for pid in ${holders}
    do
        comm=""
        IFS= read -r comm < "/proc/${pid}/comm" 2>/dev/null || true
        msg -n " ${pid}${comm:+(${comm})}"
    done
    msg ""

    if [ -n "${descendants}" ]; then
        msg -n "PID-scan descendants:"
        for pid in ${descendants}
        do
            comm=""
            IFS= read -r comm < "/proc/${pid}/comm" 2>/dev/null || true
            msg -n " ${pid}${comm:+(${comm})}"
        done
        msg ""
    fi

    tracked="${holders} ${descendants}"

    # Ask the complete captured tree to exit, then force only survivors. A
    # bounded second full scan is available to the caller only if umount is
    # still busy because of a process race after this snapshot.
    for pid in ${tracked}
    do
        [ "${pid}" = "$$" ] && continue
        [ "${pid}" = "${PPID}" ] && continue
        kill -TERM "${pid}" 2>/dev/null || true
    done
    sleep 0.20
    for pid in ${tracked}
    do
        [ "${pid}" = "$$" ] && continue
        [ "${pid}" = "${PPID}" ] && continue
        [ -d "/proc/${pid}" ] && kill -KILL "${pid}" 2>/dev/null || true
    done
    sleep 0.10
    return 0
}

manual_pid_scan_hint()
{
    [ "${PID_SCAN_FALLBACK}" = "true" ] && return 0
    [ "${PID_SCAN_HINTED}" = "true" ] && return 0
    msg "Manual fallback available: retry with -k to scan /proc and terminate chroot holders."
    PID_SCAN_HINTED="true"
}

try_manual_pid_scan()
{
    [ "${PID_SCAN_FALLBACK}" = "true" ] || return 2
    case "${PID_SCAN_COUNT:-0}" in
        0) msg -n "Manual PID holder scan ... " ;;
        1) msg -n "Manual PID holder rescan ... " ;;
        *) return 1 ;;
    esac
    PID_SCAN_COUNT=$(( ${PID_SCAN_COUNT:-0} + 1 ))
    if release_chroot_pid_scan; then
        msg "done"
        return 0
    fi
    msg "no holders found"
    return 1
}

loop_devices_for_target()
{
    local out line dev backing

    out=$(losetup -j "${TARGET_PATH%/}" 2>/dev/null || true)
    if [ -n "${out}" ]; then
        printf '%s\n' "${out}" | while IFS= read -r line
        do
            dev=${line%%:*}
            [ -n "${dev}" ] && printf '%s\n' "${dev}"
        done
        return 0
    fi

    losetup -a 2>/dev/null | while IFS= read -r line
    do
        case "${line}" in
            *' ('*')')
                dev=${line%%:*}
                backing=${line##* (}
                backing=${backing%)}
                [ "${backing}" = "${TARGET_PATH%/}" ] && printf '%s\n' "${dev}"
            ;;
        esac
    done
}

container_umount()
{
    params_check TARGET_PATH || return 1
    container_mounted || { msg "The container is not mounted." ; return 0; }

    msg -n "Release resources ... "
    if release_mount_fuser "${CHROOT_DIR%/}"; then
        msg "done"
    else
        case $? in
            1) msg "done (no holders)" ;;
            2) msg "fuser unavailable; continuing to unmount" ;;
            3) msg "done (only non-chroot holders ignored)" ;;
            *) msg "done" ;;
        esac
    fi

    msg "Unmounting partitions: "
    local parts part part_name fuser_rc loop loops
    local failures=0
    PID_SCAN_COUNT=0
    PID_SCAN_HINTED="false"

    parts=$(list_chroot_mounts)
    if [ -z "${parts}" ]; then
        msg " ...nothing mounted"
    else
        for part in ${parts}
        do
            part_name=$(echo "${part}" | sed "s|^${CHROOT_DIR%/}/*|/|g")
            msg -n "${part_name} ... "
            if umount "${part}"; then
                msg "done"
                continue
            fi

            msg "busy"
            msg -n "Fast holder lookup ... "
            if release_mount_fuser "${part}"; then
                msg -n "${part_name} retry ... "
                if umount "${part}"; then
                    msg "done"
                    continue
                fi
                msg "still busy"
            else
                fuser_rc=$?
                case "${fuser_rc}" in
                    1) msg "no holders found" ;;
                    2) msg "fuser unavailable" ;;
                    3) msg "no chroot holders eligible for kill" ;;
                    *) msg "holder lookup failed" ;;
                esac
            fi

            if try_manual_pid_scan; then
                msg -n "${part_name} retry after PID scan ... "
                if umount "${part}"; then
                    msg "done"
                    continue
                fi
                msg "still busy"
                if try_manual_pid_scan; then
                    msg -n "${part_name} retry after PID rescan ... "
                    if umount "${part}"; then
                        msg "done"
                        continue
                    fi
                    msg "fail"
                fi
            else
                manual_pid_scan_hint
            fi
            failures=1
        done
    fi

    if is_mounted "${CHROOT_DIR}"; then
        msg -n "/ ... "
        if umount "${CHROOT_DIR}"; then
            msg "done"
        else
            msg "busy"
            msg -n "Fast holder lookup ... "
            if release_mount_fuser "${CHROOT_DIR}"; then
                msg -n "/ retry ... "
                if umount "${CHROOT_DIR}"; then
                    msg "done"
                else
                    msg "still busy"
                    if try_manual_pid_scan; then
                        msg -n "/ retry after PID scan ... "
                        if umount "${CHROOT_DIR}"; then
                            msg "done"
                        else
                            msg "still busy"
                            if try_manual_pid_scan; then
                                msg -n "/ retry after PID rescan ... "
                                if umount "${CHROOT_DIR}"; then
                                    msg "done"
                                else
                                    msg "fail"
                                    failures=1
                                fi
                            else
                                failures=1
                            fi
                        fi
                    else
                        manual_pid_scan_hint
                        failures=1
                    fi
                fi
            else
                fuser_rc=$?
                case "${fuser_rc}" in
                    1) msg "no holders found" ;;
                    2) msg "fuser unavailable" ;;
                    3) msg "no chroot holders eligible for kill" ;;
                    *) msg "holder lookup failed" ;;
                esac
                if try_manual_pid_scan; then
                    msg -n "/ retry after PID scan ... "
                    if umount "${CHROOT_DIR}"; then
                        msg "done"
                    else
                        msg "still busy"
                        if try_manual_pid_scan; then
                            msg -n "/ retry after PID rescan ... "
                            if umount "${CHROOT_DIR}"; then
                                msg "done"
                            else
                                msg "fail"
                                failures=1
                            fi
                        else
                            failures=1
                        fi
                    fi
                else
                    manual_pid_scan_hint
                    failures=1
                fi
            fi
        fi
    fi

    # The mount table is the final authority. Do not report success while any
    # configured chroot mount remains. Clear a transient earlier failure only
    # if the mount table proves cleanup actually succeeded.
    if is_mounted "${CHROOT_DIR}" || [ -n "$(list_chroot_mounts)" ]; then
        failures=1
    else
        failures=0
    fi

    # Only detach loop devices whose backing file exactly matches TARGET_PATH.
    if [ "${failures}" -eq 0 ]; then
        loops=$(loop_devices_for_target)
        for loop in ${loops}
        do
            msg -n "Disassociating loop device ${loop} ... "
            if losetup -d "${loop}"; then
                msg "done"
            else
                msg "fail"
                failures=1
            fi
        done
    fi

    [ -z "$(loop_devices_for_target)" ] || failures=1
    [ "${failures}" -eq 0 ]
}

container_start()
{
    container_mounted || { msg "The container is not mounted." ; return 1; }

    DO_ACTION='do_start'
    if [ $# -gt 0 ]; then
        component_exec "$@"
    else
        component_exec "${INCLUDE}"
    fi
}

container_stop()
{
    container_mounted || { msg "The container is not mounted." ; return 1; }

    DO_ACTION='do_stop'
    if [ $# -gt 0 ]; then
        component_exec "$@"
    else
        component_exec "${INCLUDE}"
    fi
}

container_shell()
{
    container_mounted || container_mount || return 1

    DO_ACTION='do_start'
    component_exec core

    USER="root"
    SHELL="$(user_shell $USER)"
    HOME="$(user_home $USER)"
    [ -n "${TERM}" ] || TERM="linux"
    [ -n "${PS1}" ] || PS1="\u@\h:\w\\$ "
    export USER SHELL HOME TERM PS1

    if [ -e "${CHROOT_DIR}/etc/motd" ]; then
        msg $(cat "${CHROOT_DIR}/etc/motd")
    fi

    chroot_exec "$@" 2>&1

    return $?
}

rootfs_import()
{
    local rootfs_file="$1"
    [ -n "${rootfs_file}" ] || return 1

    container_mounted || container_mount root || return 1

    case "${rootfs_file}" in
    *tar)
        msg -n "Importing rootfs from tar archive ... "
        if [ -e "${rootfs_file}" ]; then
            tar xf "${rootfs_file}" -C "${CHROOT_DIR}"
        elif [ -z "${rootfs_file##http*}" ]; then
            wget -q -O - "${rootfs_file}" | tar x -C "${CHROOT_DIR}"
        else
            msg "fail"; return 1
        fi
        is_ok "fail" "done" || return 1
    ;;
    *gz)
        msg -n "Importing rootfs from tar.gz archive ... "
        if [ -e "${rootfs_file}" ]; then
            tar xzf "${rootfs_file}" -C "${CHROOT_DIR}"
        elif [ -z "${rootfs_file##http*}" ]; then
            wget -q -O - "${rootfs_file}" | tar xz -C "${CHROOT_DIR}"
        else
            msg "fail"; return 1
        fi
        is_ok "fail" "done" || return 1
    ;;
    *bz2)
        msg -n "Importing rootfs from tar.bz2 archive ... "
        if [ -e "${rootfs_file}" ]; then
            tar xjf "${rootfs_file}" -C "${CHROOT_DIR}"
        elif [ -z "${rootfs_file##http*}" ]; then
            wget -q -O - "${rootfs_file}" | tar xj -C "${CHROOT_DIR}"
        else
            msg "fail"; return 1
        fi
        is_ok "fail" "done" || return 1
    ;;
    *xz)
        msg -n "Importing rootfs from tar.xz archive ... "
        if [ -e "${rootfs_file}" ]; then
            tar xJf "${rootfs_file}" -C "${CHROOT_DIR}"
        elif [ -z "${rootfs_file##http*}" ]; then
            wget -q -O - "${rootfs_file}" | tar xJ -C "${CHROOT_DIR}"
        else
            msg "fail"; return 1
        fi
        is_ok "fail" "done" || return 1
    ;;
    *)
        msg "Incorrect filename, supported only tar, tar.gz, tar.bz2 or tar.xz archives."
        return 1
    ;;
    esac
    return 0
}

rootfs_export()
{
    local rootfs_file="$1"
    [ -n "${rootfs_file}" ] || return 1

    container_mounted || container_mount root || return 1

    case "${rootfs_file}" in
    *gz)
        msg -n "Exporting rootfs as tar.gz archive ... "
        tar czvf "${rootfs_file}" --exclude='./dev' --exclude='./sys' --exclude='./proc' -C "${CHROOT_DIR}" . >/dev/null
        is_ok "fail" "done" || return 1
    ;;
    *bz2)
        msg -n "Exporting rootfs as tar.bz2 archive ... "
        tar cjvf "${rootfs_file}" --exclude='./dev' --exclude='./sys' --exclude='./proc' -C "${CHROOT_DIR}" . >/dev/null
        is_ok "fail" "done" || return 1
    ;;
    *xz)
        msg -n "Exporting rootfs as tar.xz archive ... "
        tar cJvf "${rootfs_file}" --exclude='./dev' --exclude='./sys' --exclude='./proc' -C "${CHROOT_DIR}" . >/dev/null
        is_ok "fail" "done" || return 1
    ;;
    *)
        msg "Incorrect filename, supported only gz, bz2 or xz archives."
        return 1
    ;;
    esac
}

container_status()
{
    local model=$(which getprop >/dev/null && getprop ro.product.model)
    if [ -n "${model}" ]; then
        msg -n "Device: "
        msg "${model}"
    fi

    local android=$(which getprop >/dev/null && getprop ro.build.version.release)
    if [ -n "${android}" ]; then
        msg -n "Android: "
        msg "${android}"
    fi

    msg -n "Architecture: "
    msg "$(uname -m)"

    msg -n "Kernel: "
    msg "$(uname -r)"

    msg -n "Memory: "
    local mem_total=$(grep ^MemTotal /proc/meminfo | awk '{print $2}')
    let mem_total=${mem_total}/1024
    local mem_free=$(grep ^MemFree /proc/meminfo | awk '{print $2}')
    let mem_free=${mem_free}/1024
    msg "${mem_free}/${mem_total} MB"

    msg -n "Swap: "
    local swap_total=$(grep ^SwapTotal /proc/meminfo | awk '{print $2}')
    let swap_total=${swap_total}/1024
    local swap_free=$(grep ^SwapFree /proc/meminfo | awk '{print $2}')
    let swap_free=${swap_free}/1024
    msg "${swap_free}/${swap_total} MB"

    msg -n "SELinux: "
    selinux_inactive && msg "inactive" || msg "active"

    msg -n "Loop devices: "
    loop_support && msg "yes" || msg "no"

    msg -n "Support binfmt_misc: "
    multiarch_support && msg "yes" || msg "no"

    msg -n "Supported FS: "
    local supported_fs=$(printf '%s ' $(grep -v nodev /proc/filesystems | sort))
    msg "${supported_fs}"

    msg -n "Installed system: "
    local linux_version=$([ -r "${CHROOT_DIR}/etc/os-release" ] && . "${CHROOT_DIR}/etc/os-release"; [ -n "${PRETTY_NAME}" ] && echo "${PRETTY_NAME}" || echo "unknown")
    msg "${linux_version}"

    msg "Status of components: "
    local DO_ACTION='do_status'
    component_exec "${INCLUDE}"

    msg "Mounted parts: "
    local item
    for item in $(grep "${CHROOT_DIR%/}" /proc/mounts | awk '{print $2}' | sed "s|${CHROOT_DIR%/}/*|/|g")
    do
        msg "* ${item}"
    done
}

helper()
{
cat <<EOF
Linux Deploy ${VERSION}
(c) 2012-2019 Anton Skshidlevsky, GPLv3

USAGE:
   ${0##*/} [OPTIONS] COMMAND ...

OPTIONS:
   -p NAME - configuration profile
   -d - enable debug mode
   -t - enable trace mode

COMMANDS:
   config [...] [PARAMETERS] [NAME ...] - configuration management
      - without parameters displays a list of configurations
      -r - remove the current configuration
      -i FILE - import the configuration
      -x - dump of the current configuration
      -l - list of dependencies for the specified or are connected components
      -a - list of all components without check compatibility
   deploy [...] [PARAMETERS] [-n NAME] [NAME ...] - install the distribution and included components
      -m - mount the container before deployment
      -i - install without configure
      -c - configure without install
      -n NAME - skip installation of this component
   import FILE|URL - import a rootfs into the current container from archive (tgz, tbz2 or txz)
   export FILE - export the current container as a rootfs archive (tgz, tbz2 or txz)
   shell [-u USER] [COMMAND] - execute the specified command in the container, by default /bin/bash
      -u USER - switch to the specified user
   mount - mount the container
   umount [-k] - unmount the container
      -k - after normal/fuser cleanup fails, allow a slow /proc holder scan and terminate proven chroot holders
   start [-m] [NAME ...] - start all included or only specified components
      -m - mount the container before start
   stop [-u] [-k] [NAME ...] - stop all included or only specified components
      -u - unmount the container after stop
      -k - with -u, allow the explicit slow /proc holder scan fallback if normal/fuser cleanup fails
   status [NAME ...] - display the status of the container and components
   help [NAME ...] - show this help or help of components

EOF
}

do_info()
{
cat <<EOF
Name: ${COMPONENT}
Description: ${DESC}
Target: ${TARGET}
Depends: ${DEPENDS}
Help:

EOF
}

################################################################################

umask 0022
unset LANG
if [ -z "${ENV_DIR}" ]; then
    ENV_DIR=$(readlink "$0")
    ENV_DIR="${ENV_DIR%/*}"
    if [ -z "${ENV_DIR}" ]; then
        ENV_DIR=$(realpath "${0%/*}")
    fi
fi
if [ -e "${ENV_DIR}/cli.conf" ]; then
    . "${ENV_DIR}/cli.conf"
fi
if [ -z "${CONFIG_DIR}" ]; then
    CONFIG_DIR="${ENV_DIR}/config"
fi
if [ -z "${INCLUDE_DIR}" ]; then
    INCLUDE_DIR="${ENV_DIR}/include"
fi
if [ -z "${TEMP_DIR}" ]; then
    TEMP_DIR="${ENV_DIR}/tmp"
fi
if [ -z "${CHROOT_DIR}" ]; then
    CHROOT_DIR="${ENV_DIR}/mnt"
fi
if [ -z "${METHOD}" ]; then
    METHOD="chroot"
fi

# parse options
OPTIND=1
while getopts :p:dt FLAG
do
    case "${FLAG}" in
    p)
        PROFILE="${OPTARG}"
    ;;
    d)
        DEBUG_MODE="true"
    ;;
    t)
        TRACE_MODE="true"
    ;;
    *)
        if [ ${OPTIND} -gt 1 ]; then
            let OPTIND=OPTIND-1
        fi
        break
    ;;
    esac
done
shift $((OPTIND-1))

# log level
exec 3>&1
if [ "${DEBUG_MODE}" != "true" -a "${TRACE_MODE}" != "true" ]; then
    exec 2>/dev/null
fi
if [ "${TRACE_MODE}" = "true" ]; then
    set -x
fi

# which config
CONF_FILE=$(config_which "${PROFILE}")
PROFILE=$(basename "${CONF_FILE}" ".conf")

# read config
OPTLST=" " # space is required
params_read "${CONF_FILE}"

# fix params
WITHOUT_CHECK="false"
WITHOUT_DEPENDS="false"
REVERSE_DEPENDS="false"
EXCLUDE_COMPONENTS=""
PID_SCAN_FALLBACK="false"

# make dirs
[ -d "${CONFIG_DIR}" ] || mkdir "${CONFIG_DIR}"
[ -d "${INCLUDE_DIR}" ] || mkdir "${INCLUDE_DIR}"
[ -d "${TEMP_DIR}" ] || mkdir "${TEMP_DIR}"
[ -d "${CHROOT_DIR}" ] || mkdir "${CHROOT_DIR}"

# parse command
OPTCMD="$1"; shift
case "${OPTCMD}" in
config|conf)
    if [ $# -eq 0 ]; then
        config_list "${CONF_FILE}"
        exit $?
    fi
    conf_file="${CONF_FILE}"

    # parse options
    OPTIND=1
    while getopts :i:rxla FLAG
    do
        case "${FLAG}" in
        r)
            config_remove "${CONF_FILE}"
            exit $?
        ;;
        x)
            dump_flag="true"
        ;;
        i)
            conf_file=$(config_which "${OPTARG}")
        ;;
        l)
            list_flag="true"
        ;;
        a)
            WITHOUT_CHECK="true"
        ;;
        *)
            if [ ${OPTIND} -gt 1 ]; then
                let OPTIND=OPTIND-1
            fi
            break
        ;;
        esac
    done
    shift $((OPTIND-1))

    if [ "${dump_flag}" = "true" ]; then
        [ -e "${CONF_FILE}" ] && cat "${CONF_FILE}"
    elif [ "${list_flag}" = "true" ]; then
        if [ $# -eq 0 ]; then
            if [ "${WITHOUT_CHECK}" = "true" ]; then
                component_list
            else
                component_list "${INCLUDE}"
            fi
        else
            component_list "$@"
        fi
    else
        config_update "${conf_file}" "${CONF_FILE}" "$@"
    fi
;;
deploy)
    DO_ACTION='do_install && do_configure'

    # parse options
    OPTIND=1
    while getopts :n:mic FLAG
    do
        case "${FLAG}" in
        m)
            mount_flag="true"
        ;;
        i)
            DO_ACTION='do_install'
        ;;
        c)
            DO_ACTION='do_configure'
        ;;
        n)
            EXCLUDE_COMPONENTS="${EXCLUDE_COMPONENTS} ${OPTARG}"
        ;;
        *)
            if [ ${OPTIND} -gt 1 ]; then
                let OPTIND=OPTIND-1
            fi
            break
        ;;
        esac
    done
    shift $((OPTIND-1))

    # parse parameters
    params_parse "$@"
    shift $((OPTIND-1))

    if [ "${mount_flag}" = "true" ]; then
        container_mount || exit 1
    fi

    if [ $# -gt 0 ]; then
        component_exec "$@"
    else
        component_exec "${INCLUDE}"
    fi
;;
import)
    rootfs_import "$@"
;;
export)
    rootfs_export "$@"
;;
shell)
    container_shell "$@"
;;
mount)
    container_mount
;;
umount)
    OPTIND=1
    while getopts :k FLAG
    do
        case "${FLAG}" in
        k)
            PID_SCAN_FALLBACK="true"
        ;;
        *)
            if [ ${OPTIND} -gt 1 ]; then
                let OPTIND=OPTIND-1
            fi
            break
        ;;
        esac
    done
    shift $((OPTIND-1))
    container_umount
;;
start)
    # parse options
    OPTIND=1
    while getopts :m FLAG
    do
        case "${FLAG}" in
        m)
            mount_flag="true"
        ;;
        *)
            if [ ${OPTIND} -gt 1 ]; then
                let OPTIND=OPTIND-1
            fi
            break
        ;;
        esac
    done
    shift $((OPTIND-1))

    if [ "${mount_flag}" = "true" ]; then
        container_mount || exit 1
    fi

    container_start "$@"
;;
stop)
    # parse options
    OPTIND=1
    while getopts :uk FLAG
    do
        case "${FLAG}" in
        u)
            umount_flag="true"
        ;;
        k)
            PID_SCAN_FALLBACK="true"
        ;;
        *)
            if [ ${OPTIND} -gt 1 ]; then
                let OPTIND=OPTIND-1
            fi
            break
        ;;
        esac
    done
    shift $((OPTIND-1))

    stop_rc=0
    umount_rc=0
    container_stop "$@" || stop_rc=$?

    # If -u was requested, always attempt cleanup even when a component's
    # do_stop failed. Report failure after the requested unmount has run.
    if [ "${umount_flag}" = "true" ]; then
        container_umount || umount_rc=$?
    fi

    if [ "${stop_rc}" -ne 0 -o "${umount_rc}" -ne 0 ]; then
        exit 1
    fi
;;
status)
    if [ $# -gt 0 ]; then
        DO_ACTION='do_status'
        component_exec "$@"
    else
        container_status
    fi
;;
help)
    if [ $# -eq 0 ]; then
        helper
        if [ -n "${INCLUDE}" ]; then
            msg "PARAMETERS: "
            WITHOUT_CHECK="true"
            REVERSE_DEPENDS="true"
            DO_ACTION='do_help'
            component_exec "${INCLUDE}" ||
            msg -e '   Included components do not have parameters.\n'
        fi
    else
        WITHOUT_CHECK="true"
        WITHOUT_DEPENDS="true"
        DO_ACTION='do_info && do_help'
        component_exec "$@"
    fi
;;
*)
    helper
;;
esac
