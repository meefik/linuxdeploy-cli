#!/bin/sh

set -eu

CHROOT_DIR=/
COMPONENT_DIR=/workspace/include/core/aid
export COMPONENT=core/aid
export PRIVILEGED_USERS="android:aid_inet android:aid_media_rw"
export USER_NAME=android
export USER_PASSWORD=test-password

fail()
{
    printf '%s\n' "$1" >&2
    exit 1
}

assert_value()
{
    expected=$1
    actual=$2
    label=$3
    [ "${actual}" = "${expected}" ] || fail "${label}: expected ${expected}, got ${actual}"
}

msg()
{
    :
}

chroot_exec()
{
    [ "$1" = -u ] && shift 2
    "$@"
}

user_home()
{
    awk -F: -v user="$1" '$1 == user { print $6; exit }' "${CHROOT_DIR}/etc/passwd"
}

cli_root=$(mktemp -d)
mkdir -p "${cli_root}/config" "${cli_root}/tmp"
cp /workspace/cli.sh "${cli_root}/cli.sh"
cp -R /workspace/include "${cli_root}/include"
printf 'CONFIG_DIR="%s/config"\nINCLUDE_DIR="%s/include"\nTEMP_DIR="%s/tmp"\nCHROOT_DIR="/"\nMETHOD="chroot"\n' "${cli_root}" "${cli_root}" "${cli_root}" > "${cli_root}/cli.conf"
printf '%s\n' 'USER_NAME="android"' 'USER_PASSWORD="test-password"' 'PRIVILEGED_USERS=""' 'INCLUDE="core/profile"' > "${cli_root}/config/default.conf"
ENV_DIR="${cli_root}" bash "${cli_root}/cli.sh" -p default deploy -c core/profile
rm -rf "${cli_root}"

assert_value 5000 "$(awk -F: '$1 == "android" { print $3 }' /etc/passwd)" "new account UID"
assert_value 3003 "$(awk -F: '$1 == "aid_inet" { print $3 }' /etc/group)" "aid_inet GID"
assert_value 3004 "$(awk -F: '$1 == "aid_net_raw" { print $3 }' /etc/group)" "aid_net_raw GID"
assert_value 1023 "$(awk -F: '$1 == "aid_media_rw" { print $3 }' /etc/group)" "aid_media_rw GID"
assert_value 3005 "$(awk -F: '$1 == "aid_net_admin" { print $3 }' /etc/group)" "aid_net_admin GID"
assert_value android "$(awk -F: '$1 == "aid_inet" { print $4 }' /etc/group)" "configured network group membership"
assert_value android "$(awk -F: '$1 == "aid_net_raw" { print $4 }' /etc/group)" "configured raw network group membership"
assert_value '' "$(awk -F: '$1 == "aid_media_rw" { print $4 }' /etc/group)" "empty privileged-users setting"
assert_value 5000 "$(awk '$1 == "UID_MIN" { print $2 }' /etc/login.defs)" "UID_MIN"
assert_value 9996 "$(awk '$1 == "UID_MAX" { print $2 }' /etc/login.defs)" "UID_MAX"
assert_value 5000 "$(awk -F: '$1 == "android" { print $3 }' /etc/group)" "new account GID"
resolved_groups=" $(id -Gn android) "
case "${resolved_groups}" in *" aid_inet "*) ;; *) fail "account group resolution is missing aid_inet" ;; esac
case "${resolved_groups}" in *" aid_net_raw "*) ;; *) fail "account group resolution is missing aid_net_raw" ;; esac

export PRIVILEGED_USERS="android:aid_inet android:aid_media_rw"
# shellcheck disable=SC1091
. "${COMPONENT_DIR}/deploy.sh"
export COMPONENT=core/aid
do_configure
assert_value android "$(awk -F: '$1 == "aid_media_rw" { print $4 }' /etc/group)" "configured privileged group membership"
group_before=$(cat /etc/group)
passwd_before=$(cat /etc/passwd)
# shellcheck disable=SC1091
. /workspace/include/core/profile/deploy.sh
export COMPONENT=core/profile
do_configure
assert_value "${group_before}" "$(cat /etc/group)" "repeat group setup"
assert_value "${passwd_before}" "$(cat /etc/passwd)" "repeat account setup"

groupadd legacy
useradd -m -g legacy legacy
USER_NAME=legacy
do_configure
case ",$(awk -F: '$1 == "aid_inet" { print $4 }' /etc/group)," in
    *,legacy,*) ;;
    *) fail "reconfigured existing account is missing aid_inet membership" ;;
esac
case ",$(awk -F: '$1 == "aid_net_raw" { print $4 }' /etc/group)," in
    *,legacy,*) ;;
    *) fail "reconfigured existing account is missing aid_net_raw membership" ;;
esac

export USER_NAME=root
do_configure
assert_value 0 "$(awk -F: '$1 == "root" { print $3 }' /etc/passwd)" "root UID"

collision_root=$(mktemp -d)
mkdir -p "${collision_root}/etc"
cp /etc/passwd /etc/login.defs "${collision_root}/etc/"
printf 'occupied:x:3003:\n' >> "${collision_root}/etc/group"
cp "${collision_root}/etc/group" "${collision_root}/etc/group.base"
CHROOT_DIR=${collision_root}
COMPONENT_DIR=/workspace/include/core/aid
COMPONENT=core/aid
# shellcheck disable=SC1091
. "${COMPONENT_DIR}/deploy.sh"
if do_configure; then
    rm -rf "${collision_root}"
    fail "AID setup accepted a GID collision"
fi
cmp "${collision_root}/etc/group" "${collision_root}/etc/group.base" || fail "GID collision modified group data"
rm -rf "${collision_root}"

collision_root=$(mktemp -d)
mkdir -p "${collision_root}/etc"
printf 'root:x:0:0:root:/root:/bin/sh\n' > "${collision_root}/etc/passwd"
printf 'uid_collision:x:3003:3003::/:/bin/false\n' >> "${collision_root}/etc/passwd"
printf 'root:x:0:\noccupied:x:1000:\n' > "${collision_root}/etc/group"
cp /etc/login.defs "${collision_root}/etc/login.defs"
CHROOT_DIR=${collision_root}
# shellcheck disable=SC1091
. "${COMPONENT_DIR}/deploy.sh"
if ! do_configure; then
    rm -rf "${collision_root}"
    fail "AID setup rejected an unrelated Android GID collision"
fi
assert_value occupied "$(awk -F: '$3 == 1000 { print $1; exit }' "${collision_root}/etc/group")" "unrelated GID collision"
assert_value aid_inet "$(awk -F: '$3 == 3003 { print $1; exit }' "${collision_root}/etc/group")" "network GID despite unrelated collision"
assert_value uid_collision "$(awk -F: '$3 == 3003 { print $1; exit }' "${collision_root}/etc/passwd")" "unrelated Android UID collision"
rm -rf "${collision_root}"

printf '%s\n' 'AID component integration checks passed.'
