#!/bin/sh
# Linux Deploy Component
# (c) Anton Skshidlevsky <meefik@gmail.com>, GPLv3

do_start()
{
    if [ -n "${POWER_TRIGGER}" ]; then
        msg ":: Starting ${COMPONENT} ... "
        chroot_exec -u root "${POWER_TRIGGER} start"
    fi
    return 0
}

do_stop()
{
    if [ -n "${POWER_TRIGGER}" ]; then
        msg ":: Stopping ${COMPONENT} ... "
        chroot_exec -u root "${POWER_TRIGGER} stop"
    fi
    return 0
}

do_help()
{
cat <<EOF
   --power-trigger="${POWER_TRIGGER}"
     Path to a script inside the container to process power changes.

EOF
}
