#!/bin/sh
# Linux Deploy Component
# (c) Anton Skshidlevsky <meefik@gmail.com>, GPLv3

[ -n "${USER_NAME}" ] || USER_NAME="root"
[ -n "${USER_PASSWORD}" ] || USER_PASSWORD="changeme"

do_configure()
{
    msg ":: Configuring ${COMPONENT} ... "
    if [ -z "${USER_NAME%aid_*}" ]; then
        echo "Username \"${USER_NAME}\" is reserved."; return 1
    fi
    # user profile
    if [ "${USER_NAME}" != "root" ]; then
        chroot_exec -u root groupadd -f "${USER_NAME}" || return 1
        if ! grep -q "^${USER_NAME}:" "${CHROOT_DIR}/etc/passwd"; then
            chroot_exec -u root useradd -m -g "${USER_NAME}" -s /bin/sh "${USER_NAME}" || return 1
        fi
        chroot_exec -u root usermod -g "${USER_NAME}" -aG aid_inet,aid_net_raw "${USER_NAME}" || return 1
    fi
    # set password for user
    echo "${USER_NAME}:${USER_PASSWORD}" | chroot_exec -u root chpasswd || return 1
    # set permissions
    chroot_exec -u root chown -R "${USER_NAME}:${USER_NAME}" "$(user_home "${USER_NAME}")" || return 1
    return 0
}

do_help()
{
cat <<EOF
   --user-name="${USER_NAME}"
     Username that will be created in the container.

   --user-password="${USER_PASSWORD}"
     Password will be assigned to the specified user.

EOF
}
