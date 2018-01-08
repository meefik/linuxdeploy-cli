#!/bin/sh
# Linux Deploy Component
# (c) Anton Skshidlevsky <meefik@gmail.com>, GPLv3

[ -n "${PULSE_HOST}" ] || PULSE_HOST="127.0.0.1"
[ -n "${PULSE_PORT}" ] || PULSE_PORT="4712"

do_configure()
{
    msg ":: Configuring ${COMPONENT} ... "
    if [ -e "${CHROOT_DIR}/etc/profile.d/" ]; then
        printf "PULSE_SERVER=${PULSE_HOST}:${PULSE_PORT}\nexport PULSE_SERVER\n" > "${CHROOT_DIR}/etc/profile.d/pulse.sh"
    fi
    echo "pcm.!default { type pulse }" > "${CHROOT_DIR}/etc/asound.conf"
    echo "ctl.!default { type pulse }" >> "${CHROOT_DIR}/etc/asound.conf"
    echo "pcm.pulse { type pulse }" >> "${CHROOT_DIR}/etc/asound.conf"
    echo "ctl.pulse { type pulse }" >> "${CHROOT_DIR}/etc/asound.conf"
    return 0
}

do_help()
{
cat <<EOF
   --pulse-host="${PULSE_HOST}"
     Host of PulseAudio server, default 127.0.0.1.

   --pulse-port="${PULSE_PORT}"
    Port of PulseAudio server, default 4712.

EOF
}
