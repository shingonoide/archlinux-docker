#!/usr/bin/env bash

##
# Generate a minimal filesystem for archlinux and load it into the local
# docker as "archlinux"
# requires root

set -e
# set -x

hash pacstrap &>/dev/null || {
	echo "Could not find pacstrap. Run pacman -S arch-install-scripts"
	exit 1
}

hash expect &>/dev/null || {
	echo "Could not find expect. Run pacman -S expect"
	exit 1
}

function exit_cleanup () {
	echo -e "\nStarting cleanup"
	sleep 2
	umount --recursive $ROOTFS || /bin/true
	sleep 3
	rm -rf $ROOTFS || echo "Can't cleanup $ROOTFS"
	echo -e "Clean.\n"
}

function pre_image_cleanup (){
	rm -f "$ROOTFS/etc/pacman.d/gnupg/S.gpg-agent" || :
}

ROOTFS=$(mktemp -d ${TMPDIR:-/var/tmp}/rootfs-archlinux-XXXXXXXXXX)
trap exit_cleanup EXIT
chmod 755 $ROOTFS

PKGBSTRAP_BUSYBOX=(
	busybox-coreutils
	busybox-iputils
	busybox-findutils
	procps-ng-nosystemd
	sed
	gzip
	pacman
	texinfo-fake
	# gmp
	# mpfr
	# libunistring
	# haveged
)
PKGBSTRAP=(
	busybox-coreutils
	# coreutils-static
	busybox-iputils
	busybox-findutils
	procps-ng-nosystemd
	sed
	gzip
	pacman
	texinfo-fake
	haveged
	no-certificates
	# gmp
	# mpfr
	# libunistring
)
PKGBSTRAP=(
	texinfo-fake
	# no-certificates
	procps-ng-nosystemd
	pacman
	sed
	gzip
	# coreutils
	busybox-coreutils
	busybox-util-linux
	busybox-iputils
	busybox-findutils
	haveged
	ca-certificates
	# gmp
	# mpfr
	# libunistring
)
# packages to ignore for space savings
PKGIGNORE=(
  cryptsetup
  device-mapper
  dhcpcd
  iproute2
  jfsutils
  linux
  lvm2
  man-db
  man-pages
  mdadm
  nano
  netctl
  openresolv
  pciutils
  pcmciautils
  reiserfsprogs
  s-nail
  systemd-sysvcompat
  usbutils
  vi
  xfsprogs
	util-linux
	systemd
	procps-ng
	texinfo
	# pambase
	# pam
	# shadow
	# inetutils
	# iputils
	sysfsutils
	# libtasn1
	# p11-kit
	# ca-certificates-utils
	# ca-certificates-mozilla
	# ca-certificates-cacert
	# ca-certificates
	# coreutils
	findutils
)
# pacman
# openssl
# perl
IFS=','
PKGIGNORE="${PKGIGNORE[*]}"
unset IFS

PKGBSTRAP="${PKGBSTRAP[*]}"

LOCAL_REPO=/home/ruiandrada/Repo/Docker/archlinux-repository
# mkdir -p $ROOTFS/tmp/tmprepo
# cp -va $LOCAL_REPO $ROOTFS/tmp/tmprepo


LC_ALL=C expect <<EOF
	set send_slow {1 .1}
	proc send {ignore arg} {
		sleep .1
		exp_send -s -- \$arg
	}
	set timeout 300

	spawn pacstrap -C ./mkimage-arch-pacman.conf -c -d -G -M -i $ROOTFS $PKGBSTRAP --ignore $PKGIGNORE
	expect {
		-exact "anyway? \[Y/n\] " { send -- "n\r"; exp_continue }
		-exact "(default=all): " { send -- "\r"; exp_continue }
		-exact "installation? \[Y/n\]" { send -- "y\r"; exp_continue }
	}
EOF

# arch-chroot $ROOTFS /bin/sh -c 'pacman -U --noconfirm /tmp/tmprepo/busybox-coreutils*'
arch-chroot $ROOTFS /bin/sh -c 'echo -e "PATH:$PATH"'
arch-chroot $ROOTFS /bin/sh -c 'rm -r /usr/share/man/*'
arch-chroot $ROOTFS /bin/sh -c 'haveged -w 1024; pacman-key --init; pkill haveged; pacman -Rs --noconfirm haveged; pacman-key --populate archlinux; pkill gpg-agent'
arch-chroot $ROOTFS /bin/sh -c 'ln -s /usr/share/zoneinfo/UTC /etc/localtime'
echo 'en_US.UTF-8 UTF-8' > $ROOTFS/etc/locale.gen
arch-chroot $ROOTFS locale-gen

## Pacman mirror setup
arch-chroot $ROOTFS /bin/sh -c 'echo "Server = https://mirrors.kernel.org/archlinux/\$repo/os/\$arch" > /etc/pacman.d/mirrorlist'
# arch-chroot $ROOTFS /bin/sh -c "echo -n 'Preparing mirrorlist...' \
# 	&& cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup \
# 	&& sed -i 's/^#Server/Server/' /etc/pacman.d/mirrorlist.backup \
# 	&& rankmirrors -n 10 /etc/pacman.d/mirrorlist.backup > /etc/pacman.d/mirrorlist \
# 	&& echo 'Done.'
# "

# udev doesn't work in containers, rebuild /dev
DEV=$ROOTFS/dev
rm -rf $DEV
mkdir -p $DEV
mknod -m 666 $DEV/null c 1 3
mknod -m 666 $DEV/zero c 1 5
mknod -m 666 $DEV/random c 1 8
mknod -m 666 $DEV/urandom c 1 9
mkdir -m 755 $DEV/pts
mkdir -m 1777 $DEV/shm
mknod -m 666 $DEV/tty c 5 0
mknod -m 600 $DEV/console c 5 1
mknod -m 666 $DEV/tty0 c 4 0
mknod -m 666 $DEV/full c 1 7
mknod -m 600 $DEV/initctl p
mknod -m 666 $DEV/ptmx c 5 2
ln -sf /proc/self/fd $DEV/fd

ARCH=$3
IMAGE="${2:-archlinux}"
IMAGE_ARCH="${IMAGE}${ARCH:+-}${ARCH}"
TAG_RELEASE="`date -u '+%Y%m%d%H%M'`"
IMAGE_TAG="${IMAGE_ARCH}${TAG_RELEASE+:}${TAG_RELEASE}"

echo -n "Starting to build image $IMAGE_TAG id: "
pre_image_cleanup \
	&& tar --numeric-owner --xattrs --acls -C $ROOTFS -c . \
	| docker import - $IMAGE_TAG \
	&& [ "$1" == "latest" ] && docker tag -f $IMAGE_TAG $IMAGE:latest
docker run --rm $IMAGE_TAG pacman --version && echo "$IMAGE_TAG successfully built."
# var_cleanup
