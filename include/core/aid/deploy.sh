#!/bin/sh
# Linux Deploy Component
# (c) Anton Skshidlevsky <meefik@gmail.com>, GPLv3

do_configure()
{
    msg ":: Configuring ${COMPONENT} ... "
    local login_defs
    login_defs="${CHROOT_DIR}/etc/login.defs"
    if [ ! -e "${login_defs}" ]; then
        touch "${login_defs}"
    fi
    local setting key value
    for setting in UID_MIN:5000 UID_MAX:9996 GID_MIN:5000 GID_MAX:9996
    do
        key=${setting%%:*}
        value=${setting#*:}
        if grep -q "^[[:space:]]*${key}[[:space:]]" "${login_defs}"; then
            sed -i "s|^[[:space:]]*${key}[[:space:]].*|${key} ${value}|" "${login_defs}"
        else
            echo "${key} ${value}" >>"${login_defs}"
        fi
    done
    local xname xid existing_gid
    while IFS=: read -r xname xid
    do
        [ -n "${xname}" ] || continue
        case "${xname}" in
            *_start|*_end|aid_overflowuid|aid_user_offset) continue ;;
        esac
        existing_gid=$(awk -F: -v group="${xname}" '$1 == group { print $3; exit }' "${CHROOT_DIR}/etc/group")
        if [ -n "${existing_gid}" ] && [ "${existing_gid}" != "${xid}" ]; then
            case "${xname}" in
                aid_inet|aid_net_raw)
                    echo "Group ${xname} has GID ${existing_gid}; expected Android GID ${xid}."
                    return 1
                ;;
                *) continue ;;
            esac
        fi
        if awk -F: -v gid="${xid}" -v group="${xname}" '$3 == gid && $1 != group { found = 1 } END { exit !found }' "${CHROOT_DIR}/etc/group"; then
            case "${xname}" in
                aid_inet|aid_net_raw)
                    echo "GID ${xid} is already assigned to a different group; cannot create ${xname}."
                    return 1
                ;;
            esac
        fi
    done < "${COMPONENT_DIR}/android_groups"
    while IFS=: read -r xname xid
    do
        [ -n "${xname}" ] || continue
        case "${xname}" in
            *_start|*_end|aid_overflowuid|aid_user_offset) continue ;;
        esac
        existing_gid=$(awk -F: -v group="${xname}" '$1 == group { print $3; exit }' "${CHROOT_DIR}/etc/group")
        if [ -z "${existing_gid}" ] && ! awk -F: -v gid="${xid}" '$3 == gid { found = 1 } END { exit !found }' "${CHROOT_DIR}/etc/group"; then
            echo "${xname}:x:${xid}:" >> "${CHROOT_DIR}/etc/group"
            existing_gid=${xid}
        fi
        if [ "${existing_gid}" = "${xid}" ] && ! awk -F: -v user="${xname}" '$1 == user { found = 1 } END { exit !found }' "${CHROOT_DIR}/etc/passwd" && ! awk -F: -v uid="${xid}" '$3 == uid { found = 1 } END { exit !found }' "${CHROOT_DIR}/etc/passwd"; then
            echo "${xname}:x:${xid}:${xid}::/:/bin/false" >> "${CHROOT_DIR}/etc/passwd"
        fi
    done < "${COMPONENT_DIR}/android_groups"
    local entry username group_name group_tmp
    for entry in ${PRIVILEGED_USERS}
    do
        username=${entry%%:*}
        group_name=${entry#*:}
        if [ "${username}" = "${entry}" ] || [ -z "${username}" ] || [ -z "${group_name}" ]; then
            echo "Invalid privileged user entry: ${entry}. Use username:group."
            return 1
        fi
        existing_gid=$(awk -F: -v group="${group_name}" '$1 == group { print $3; exit }' "${CHROOT_DIR}/etc/group")
        if [ -z "${existing_gid}" ]; then
            echo "Privileged group ${group_name} does not exist."
            return 1
        fi
        xid=$(awk -F: -v group="${group_name}" '$1 == group { print $2; exit }' "${COMPONENT_DIR}/android_groups")
        if [ -n "${xid}" ] && [ "${existing_gid}" != "${xid}" ]; then
            echo "Group ${group_name} has GID ${existing_gid}; expected Android GID ${xid}."
            return 1
        fi
        group_tmp="${CHROOT_DIR}/etc/group.tmp"
        cp -p "${CHROOT_DIR}/etc/group" "${group_tmp}" || return 1
        if ! awk -F: -v group="${group_name}" -v user="${username}" '
            BEGIN { OFS = ":" }
            $1 == group {
                matched_group = 1
                count = split($4, members, ",")
                for (i = 1; i <= count; i++) {
                    if (members[i] == user) member_found = 1
                }
                if (!member_found) $4 = $4 == "" ? user : $4 "," user
            }
            { print }
            END { exit !matched_group }
        ' "${CHROOT_DIR}/etc/group" > "${group_tmp}"; then
            rm -f "${group_tmp}"
            echo "Unable to add ${username} to ${group_name}."
            return 1
        fi
        mv "${group_tmp}" "${CHROOT_DIR}/etc/group"
    done
    return 0
}

do_help()
{
cat <<EOF
   --privileged-users="${PRIVILEGED_USERS}"
     A list of users in a format USER:GROUP separated by a space.

EOF
}
