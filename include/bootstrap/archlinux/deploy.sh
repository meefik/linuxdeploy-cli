#!/bin/sh
# Linux Deploy Component
# (c) Anton Skshidlevsky <meefik@gmail.com>, GPLv3

if [ -z "${ARCH}" ]
then
    case "$(get_platform)" in
    x86) ARCH="i686" ;;
    x86_64) ARCH="x86_64" ;;
    arm) ARCH="armv7h" ;;
    arm_64) ARCH="aarch64" ;;
    esac
fi

if [ -z "${SOURCE_PATH}" ]
then
    case "$(get_platform ${ARCH})" in
    x86) SOURCE_PATH="http://mirror.archlinux32.org/" ;;
    x86_64) SOURCE_PATH="http://mirrors.kernel.org/archlinux/" ;;
    arm*) SOURCE_PATH="http://mirror.archlinuxarm.org/" ;;
    esac
fi

pacman_install()
{
    local packages="$@"
    [ -n "${packages}" ] || return 1
    (set -e
        #rm -f ${CHROOT_DIR}/var/lib/pacman/db.lck || true
        chroot_exec -u root pacman -Syq --overwrite="*" --noconfirm ${packages}
        rm -f "${CHROOT_DIR}"/var/cache/pacman/pkg/* || true
    exit 0)
    return $?
}

pacman_repository()
{
    case "$(get_platform ${ARCH})" in
    x86_64) local repo_url="${SOURCE_PATH%/}/\$repo/os/\$arch" ;;
    arm*|x86) local repo_url="${SOURCE_PATH%/}/\$arch/\$repo" ;;
    *) return 1 ;;
    esac
    sed -i "s|^[[:space:]]*Architecture[[:space:]]*=.*$|Architecture = ${ARCH}|" "${CHROOT_DIR}/etc/pacman.conf"
    sed -i "s|^[[:space:]]*\(CheckSpace\)|#\1|" "${CHROOT_DIR}/etc/pacman.conf"
    sed -i "s|^[[:space:]]*SigLevel[[:space:]]*=.*$|SigLevel = Never|" "${CHROOT_DIR}/etc/pacman.conf"
    if $(grep -q "^[[:space:]]*Server" "${CHROOT_DIR}/etc/pacman.d/mirrorlist")
    then sed -i "s|^[[:space:]]*Server[[:space:]]*=.*|Server = ${repo_url}|" "${CHROOT_DIR}/etc/pacman.d/mirrorlist"
    else echo "Server = ${repo_url}" >> "${CHROOT_DIR}/etc/pacman.d/mirrorlist"
    fi
}

do_install()
{
    is_archive "${SOURCE_PATH}" && return 0

    msg ":: Installing ${COMPONENT} ... "

    local repo_url
    case "$(get_platform ${ARCH})" in
    x86_64) repo_url="${SOURCE_PATH%/}/core/os/${ARCH}" ;;
    arm*|x86) repo_url="${SOURCE_PATH%/}/${ARCH}/core" ;;
    *) return 1 ;;
    esac

    msg -n "Preparing for deployment ... "
    local cache_dir="${CHROOT_DIR}/var/cache/pacman/pkg"
    mkdir -p "${cache_dir}"
    is_ok "fail" "done" || return 1

    msg -n "Retrieving packages list ... "
    local core_files=$(wget -q -O - "${repo_url}/core.db.tar.gz" | tar xOz | grep '.pkg.tar.xz$' | grep -v -e '^linux-' -e '^grub-' -e '^efibootmgr-' -e '^openssh-' | sort)
    is_ok "fail" "done" || return 1

    msg "Retrieving packages: "
    local fs_file=$(echo ${core_files} | grep -m1 '^filesystem-')
    for pkg_file in ${fs_file} ${core_files}
    do
        msg -n "${pkg_file%-*} ... "
        # download
        local i
        for i in 1 2 3
        do
            wget -q -c -O "${cache_dir}/${pkg_file}" "${repo_url}/${pkg_file}" && break
            sleep 30s
        done
        # unpack
        tar xJf "${cache_dir}/${pkg_file}" -C "${CHROOT_DIR}" --exclude='./dev' --exclude='./sys' --exclude='./proc' --exclude='.INSTALL' --exclude='.MTREE' --exclude='.PKGINFO'
        is_ok "fail" "done" || return 1
    done

    component_exec core/emulator core/mnt core/net

    msg -n "Updating repository ... "
    pacman_repository
    is_ok "fail" "done"

    msg "Installing packages: "
    pacman_install base $(echo ${core_files} | sed 's/-[0-9].*$//') ${EXTRA_PACKAGES}
    is_ok || return 1

    msg -n "Clearing cache ... "
    rm -f "${cache_dir}"/* $(find "${CHROOT_DIR}/etc" -type f -name "*.pacnew")
    is_ok "skip" "done"

    return 0
}

do_help()
{
cat <<EOF
   --arch="${ARCH}"
     Architecture of Linux distribution, supported "arm", "armv6h", "armv7h", "aarch64", "i686" and "x86_64".

   --source-path="${SOURCE_PATH}"
     Installation source, can specify address of the repository or path to the rootfs archive.

   --extra-packages="${EXTRA_PACKAGES}"
     List of optional installation packages, separated by spaces.

EOF
}
