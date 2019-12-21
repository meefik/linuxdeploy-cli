# Linux Deploy CLI

Copyright (C) 2015-2019 Anton Skshidlevsky, GPLv3

A command line application for installing and running GNU/Linux distributions in the chroot environment.

### Dependencies

- [Linux](http://kernel.org)
- [BusyBox](https://github.com/meefik/busybox) or Bash and GNU utils
- [QEMU](http://qemu.org), [qemu-user-static](https://packages.debian.org/stable/qemu-user-static) for architecture emulation
- [binfmt_misc](https://en.wikipedia.org/wiki/Binfmt_misc) module for architecture emulation without PRoot
- [PRoot](https://github.com/meefik/PRoot) for work without superuser permissions

### Usage

Main help:

```
USAGE:
   cli.sh [OPTIONS] COMMAND ...

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
   umount - unmount the container
   start [-m] [NAME ...] - start all included or only specified components
      -m - mount the container before start
   stop [-u] [NAME ...] - stop all included or only specified components
      -u - unmount the container after stop
   status [NAME ...] - display the status of the container and components
   help [NAME ...] - show this help or help of components

```

Help for the parameters of the main components:

```
   --distrib="debian"
     The code name of Linux distribution, which will be installed. Supported "debian", "ubuntu", "kali", "fedora", "centos", "archlinux", "slackware", "apline".

   --target-type="file"
     The container deployment type, can specify "file", "directory", "partition", "ram" or "custom".

   --target-path="/path/to/debian_x86.img"
     Installation path depends on the type of deployment.

   --disk-size="2000"
     Image file size when selected type of deployment "file". Zero means the automatic selection of the image size.

   --fs-type="ext4"
     File system that will be created inside a image file or on a partition. Supported "ext2", "ext3" or "ext4"

   --arch="i386"
     Architecture of Linux distribution, supported "armel", "armhf", "arm64", "i386" and "amd64".

   --suite="stretch"
     Version of Linux distribution, supported versions "jessie", "stretch" and "buster" (also can be used "stable", "testing", "unstable" or "oldstable").

   --source-path="http://ftp.debian.org/debian/"
     Installation source, can specify address of the repository or path to the rootfs archive.

   --extra-packages=""
     List of optional installation packages, separated by spaces.

   --method="chroot"
     Containerization method "chroot" or "proot".

   --chroot-dir="/mnt"
     Mount directory of the container for containerization method "chroot".

   --emulator="qemu-i386-static"
     Specify which to use the emulator, by default QEMU.

   --mounts="/path/to/source:/path/to/target"
     Mounts resources to the container as "SOURCE:TARGET" separated by a space.

   --dns="auto"
     IP-address of DNS server, can specify multiple addresses separated by a space.

   --net-trigger=""
     Path to a script inside the container to process changes the network.

   --locale="C"
     Localization, e.g. "en_US.UTF-8".

   --user-name="android"
     Username that will be created in the container.

   --user-password="changeme"
     Password will be assigned to the specified user.

   --privileged-users="android:aid_inet android:aid_media_rw"
     A list of users in a format UID:GID separated by a space to be added UID to GID.

```

### Links

- Source code: https://github.com/meefik/linuxdeploy-cli
- Donations: https://meefik.github.io/donate
