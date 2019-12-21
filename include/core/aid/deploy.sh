#!/bin/sh
# Linux Deploy Component
# (c) Anton Skshidlevsky <meefik@gmail.com>, GPLv3

do_configure()
{
    msg ":: Configuring ${COMPONENT} ... "
    # set min uid and gid
    local login_defs
    login_defs="${CHROOT_DIR}/etc/login.defs"
    if [ ! -e "${login_defs}" ]; then
        touch "${login_defs}"
    fi
    if ! $(grep -q '^ *UID_MIN' "${login_defs}"); then
        echo "UID_MIN 5000" >>"${login_defs}"
        sed -i 's|^[#]\?UID_MIN.*|UID_MIN 5000|' "${login_defs}"
    fi
    if ! $(grep -q '^ *GID_MIN' "${login_defs}"); then
        echo "GID_MIN 5000" >>"${login_defs}"
        sed -i 's|^[#]\?GID_MIN.*|GID_MIN 5000|' "${login_defs}"
    fi
    # add android groups
    if [ -n "${PRIVILEGED_USERS}" ]; then
        local aid
        for aid in $(cat "${COMPONENT_DIR}/android_groups")
        do
            local xname=$(echo ${aid} | awk -F: '{print $1}')
            local xid=$(echo ${aid} | awk -F: '{print $2}')
            sed -i "s|^${xname}:.*|${xname}:x:${xid}:|" "${CHROOT_DIR}/etc/group"
            if ! $(grep -q "^${xname}:" "${CHROOT_DIR}/etc/group"); then
                echo "${xname}:x:${xid}:" >> "${CHROOT_DIR}/etc/group"
            fi
            if ! $(grep -q "^${xname}:" "${CHROOT_DIR}/etc/passwd"); then
                echo "${xname}:x:${xid}:${xid}::/:/bin/false" >> "${CHROOT_DIR}/etc/passwd"
            fi
        done
        local usr
        for usr in ${PRIVILEGED_USERS}
        do
            local uid=${usr%%:*}
            local gid=${usr##*:}
            sed -i "s|^\(${gid}:.*:[^:]+\)$|\1,${uid}|" "${CHROOT_DIR}/etc/group"
            sed -i "s|^\(${gid}:.*:\)$|\1${uid}|" "${CHROOT_DIR}/etc/group"
        done
    fi
    return 0
}

do_help()
{
cat <<EOF
   --privileged-users="${PRIVILEGED_USERS}"
     A list of users in a format UID:GID separated by a space to be added UID to GID.

EOF
}
