# Linux Deploy CLI

Copyright (C) 2015-2018 Anton Skshidlevsky, GPLv3

Приложение с интерфейсом для командной строки, предназначенное для автоматизации процесса установки, конфигурирования и запуска GNU/Linux дистрибутивов внутри контейнера chroot. Приложение может работать как в обычных десктопных Linux-дистрибутивах, так и на мобильных платформах, основанных на ядре Linux, при условии соблюдения необходимых зависимостей (все зависимости могут быть собраны статически). Приложения из Linux-дистрибутива запускаются в chroot окружении, работают параллельно с основной системой и сопоставимы с ней по скорости. Поскольку работа Linux Deploy базируется на системном вызове ядра Linux, то в роли "гостевых" систем могут выступать только дистрибутивы Linux.

Приложение может работать в двух режимах: с правами суперпользователя (chroot) и без них (proot). В обычном режиме доступны все поддерживаемые типы установки: установка в файл, на раздел диска (логический диск), в POSIX совместимую директорию и в оперативную память (tmpfs). В режиме fakeroot доступна установка только в директорию, а также появляется ряд ограничений:
* все пользователи внутри контейнера имеют полный доступ ко всей файловой системе контейнера, а владельцем всех файлов и каталогов является текущий пользователь;
* нет доступа к привилегированным операциям с системой, например, не работает ping, ulimit и т.п.;
* приложения могут работать только с номерами сетевых портов выше 1024;
* если приложение в своей работе использует системный вызов chroot, то его необходимо запускать через специальную утилиту fakechroot, например fakechroot /usr/sbin/sshd -p 2222.

Приложение поддерживает автоматическую установку (базовой системы) и начальную настройку дистрибутивов Debian, Ubuntu, Kali Linux, Arch Linux, Fedora, CentOS, Gentoo, openSUSE и Slackware. Установка Linux-дистрибутива осуществляется по сети с официальных зеркал в интернете. Также поддерживается импорт любой другой системы из заранее подготовленного rootfs-ахрива в формате tar.gz, tar.bz2 или tar.xz. Приложение позволяет подключаться к консоли установленной системы (контейнеру), а также запускать и останавливать приложения внутри контейнера (есть поддержка различных систем инициализации и собственных сценариев автозапуска). Каждый вариант установки сохраняется в отдельный конфигурационный файл, который отвечает за настройку каждого контейнера. При необходимости, контейнеры можно запускать параллельно. Можно экспортировать конфигурацию и сам контейнер как rootfs-архив для последующего развертывания этого контейнера без повторной установки и настройки.

Для расширения возможностей приложения реализована модульная архитектура, каждый модуль здесь назван компонентом. Компоненты пишутся на Bash-совместимом языке сценариев Ash, каждый компонент представляет собой директорию с двумя основными файлами deploy.conf и deploy.sh. Реализация компонента сводится к написанию обработчиков для следующих действий: установка, настройка, запуск, остановка и вызов справки. Компоненты могут зависеть от других компонентов, есть защита от циклических зависимостей. В компоненте можно указать совместимость с конкретными версиями дистрибутивов, чтобы ограничить область его применения.

*TODO: please, translate this text.*

Dependencies:
* [Linux](http://kernel.org)
* [BusyBox](https://github.com/meefik/busybox) or Bash and GNU utils
* [QEMU](http://qemu.org), [qemu-user-static](https://packages.debian.org/stable/qemu-user-static) for architecture emulation
* [binfmt_misc](https://en.wikipedia.org/wiki/Binfmt_misc) module for architecture emulation without PRoot
* [PRoot](https://github.com/meefik/PRoot) for work without superuser permissions

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
   deploy [...] [-n NAME] [NAME ...] - install the distribution and included components
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
   sync URL - synchronize with the operating environment with server
   status [NAME ...] - display the status of the container and components
   help [NAME ...] - show this help or help of components

```

Help for the parameters of the main components:
```
   --distrib="debian"
     The code name of Linux distribution, which will be installed. Supported "debian", "ubuntu", "kalilinux", "fedora", "centos", "archlinux", "gentoo", "opensuse", "slackware".

   --target-type="file"
     The container deployment type, can specify "file", "directory", "partition", "ram" or "custom".

   --target-path="/path/to/debian_x86.img"
     Installation path depends on the type of deployment.

   --disk-size="2000"
     Image file size when selected type of deployment "file". Zero means the automatic selection of the image size.

   --fs-type="auto"
     File system that will be created inside a image file or on a partition. Supported "ext2", "ext3", "ext4" or "auto".

   --arch="i386"
     Architecture of Linux distribution, supported "armel", "armhf", "arm64", "i386" and "amd64".

   --suite="jessie"
     Version of Linux distribution, supported versions "wheezy", "jessie" and "stretch" (also can be used "stable", "testing" and "unstable").

   --source-path="http://ftp.debian.org/debian/"
     Installation source, can specify address of the repository or path to the rootfs archive.

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

   --locale="en_US.UTF-8"
     Localization, e.g. "ru_RU.UTF-8".

   --user-name="android"
     Username that will be created in the container.

   --user-password="changeme"
     Password will be assigned to the specified user.

   --privileged-users="root messagebus"
     A list of users separated by a space to be added to Android groups.

```

#### Source code
Source code: <https://github.com/meefik/linuxdeploy-cli>.

#### Donations
<http://meefik.github.io/donate>
