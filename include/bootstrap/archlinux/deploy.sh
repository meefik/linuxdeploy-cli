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
        chroot_exec -u root pacman -Syq --force --noconfirm ${packages}
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

    local base_packages="filesystem acl archlinux-keyring attr bash bzip2 ca-certificates ca-certificates-mozilla ca-certificates-utils coreutils cracklib curl db e2fsprogs expat findutils gcc-libs gdbm glib2 glibc gmp gnupg gnutls gpgme iana-etc keyutils krb5 libarchive libassuan libcap libffi libgcrypt libgpg-error libidn libidn2 libksba libldap libnghttp2 libpsl libsasl libsecret libssh2 libsystemd libtasn1 libtirpc libunistring libutil-linux linux-api-headers lz4 ncurses nettle npth openssl p11-kit pacman pacman-mirrorlist pam pambase pcre perl pinentry readline shadow sqlite sudo tzdata util-linux which xz zlib zstd"

    case "$(get_platform ${ARCH})" in
    x86_64) local repo_url="${SOURCE_PATH%/}/core/os/${ARCH}" ;;
    arm*|x86) local repo_url="${SOURCE_PATH%/}/${ARCH}/core" ;;
    *) return 1 ;;
    esac

    msg "URL: ${repo_url}"

    msg -n "Preparing for deployment ... "
    local cache_dir="${CHROOT_DIR}/var/cache/pacman/pkg"
    mkdir -p "${cache_dir}"
    is_ok "fail" "done" || return 1

    msg -n "Retrieving packages list ... "
    local pkg_list=$(wget -q -O - "${repo_url}/" | sed -n '/<a / s/^.*<a [^>]*href="\([^\"]*\)".*$/\1/p' | awk -F'/' '{print $NF}' | sort -rn)
    is_ok "fail" "done" || return 1

    msg "Retrieving base packages: "
    for package in ${base_packages}
    do
        msg -n "${package} ... "
        local pkg_file=$(echo "${pkg_list}" | grep -m1 -e "^${package}-[[:digit:]].*\.xz$" -e "^${package}-[[:digit:]].*\.gz$")
        test "${pkg_file}"; is_ok "fail" || return 1
        # download
        local i
        for i in 1 2 3
        do
            wget -q -c -O "${cache_dir}/${pkg_file}" "${repo_url}/${pkg_file}" && break
            sleep 30s
        done
        # unpack
        case "${pkg_file}" in
        *gz) tar xzf "${cache_dir}/${pkg_file}" -C "${CHROOT_DIR}" --exclude='./dev' --exclude='./sys' --exclude='./proc' --exclude='.INSTALL' --exclude='.MTREE' --exclude='.PKGINFO';;
        *bz2) tar xjf "${cache_dir}/${pkg_file}" -C "${CHROOT_DIR}" --exclude='./dev' --exclude='./sys' --exclude='./proc' --exclude='.INSTALL' --exclude='.MTREE' --exclude='.PKGINFO';;
        *xz) tar xJf "${cache_dir}/${pkg_file}" -C "${CHROOT_DIR}" --exclude='./dev' --exclude='./sys' --exclude='./proc' --exclude='.INSTALL' --exclude='.MTREE' --exclude='.PKGINFO';;
        *) msg "fail"; return 1;;
        esac
        is_ok "fail" "done" || return 1
    done

    component_exec core/emulator core/mnt core/net

    msg -n "Updating repository ... "
    pacman_repository
    is_ok "fail" "done"

    msg "Installing base packages: "
    pacman_install base ${base_packages}
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

EOF
}
