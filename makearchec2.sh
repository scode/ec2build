#!/bin/bash
# 2010 Copyright Yejun Yang (yejunx AT gmail DOT com)
# Creative Commons Attribution-Noncommercial-Share Alike 3.0 United States License.
# http://creativecommons.org/licenses/by-nc-sa/3.0/us/

if [[ `uname -m` == i686 ]]; then
  ARCH=i686
  EC2_ARCH=i386
else
  ARCH=x86_64
  EC2_ARCH=x86_64
fi

ROOT=/tmp/arch_$ARCH
EBSDEVICE=/dev/xvdg
NEWROOT=/mnt/newroot

fdisk ${EBSDEVICE} <<EOF
n
p


+100M
n
p



w
EOF

mkfs.ext3 ${EBSDEVICE}1
mkfs.btrfs ${EBSDEVICE}2
mkdir ${NEWROOT}
mount -o compress ${EBSDEVICE}2 ${NEWROOT}
chmod 755 ${NEWROOT}
mkdir ${NEWROOT}/boot
mount ${EBSDEVICE}1 ${NEWROOT}/boot
btrfs subvolume create ${NEWROOT}/home
btrfs subvolume create ${NEWROOT}/etc
btrfs subvolume create ${NEWROOT}/srv
btrfs subvolume create ${NEWROOT}/var
btrfs subvolume create ${NEWROOT}/opt
btrfs subvolume create ${NEWROOT}/usr

PACKS="filesystem pacman sed coreutils ca-certificates groff \
        less which procps logrotate syslog-ng net-tools initscripts psmisc nano vi \
        iputils tar sudo mailx openssh kernel26-ec2 kernel26-ec2-headers \
        wget curl screen bash-completion ca-certificates kernel26-ec2 \
	kernel26-ec2-headers ec2-metadata btrfs-progs-git zsh ec2arch vim vimpager \
	vim-colorsamplerpack cpio dnsutils base-devel devtools srcpac abs \
	lesspipe ssmtp iproute2"

cat <<EOF > pacman.conf
[options]
HoldPkg     = pacman glibc
SyncFirst   = pacman
Architecture = $ARCH
[ec2]
Server = file:///root/repo
[core]
Include = /etc/pacman.d/mirrorlist
[extra]
Include = /etc/pacman.d/mirrorlist
[community]
Include = /etc/pacman.d/mirrorlist
EOF

LC_ALL=C mkarchroot -C pacman.conf $ROOT $PACKS

mv $ROOT/etc/pacman.d/mirrorlist $ROOT/etc/pacman.d/mirrorlist.pacorig
cat <<EOF >$ROOT/etc/pacman.d/mirrorlist
Server = http://mirrors.kernel.org/archlinux/\$repo/os/\$arch
Server = ftp://ftp.archlinux.org/\$repo/os/\$arch
EOF

chmod 666 $ROOT/dev/null
mknod -m 666 $ROOT/dev/random c 1 8
mknod -m 666 $ROOT/dev/urandom c 1 9
mkdir -m 755 $ROOT/dev/pts
mkdir -m 1777 $ROOT/dev/shm

mv $ROOT/etc/rc.conf $ROOT/etc/rc.conf.pacorig
cat <<EOF >$ROOT/etc/rc.conf
LOCALE="en_US.UTF-8"
TIMEZONE="UTC"
MOD_AUTOLOAD="no"
USECOLOR="yes"
USELVM="no"
DAEMONS=(syslog-ng sshd crond ec2)
EOF

mv $ROOT/etc/inittab $ROOT/etc/inittab.pacorig
cat <<EOF >$ROOT/etc/inittab
id:3:initdefault:
rc::sysinit:/etc/rc.sysinit
rs:S1:wait:/etc/rc.single
rm:2345:wait:/etc/rc.multi
rh:06:wait:/etc/rc.shutdown
su:S:wait:/sbin/sulogin -p
ca::ctrlaltdel:/sbin/shutdown -t3 -r now
# This will enable the system log.
c0:12345:respawn:/sbin/agetty 38400 hvc0 linux
EOF

mv $ROOT/etc/hosts.deny $ROOT/etc/hosts.deny.pacorig
cat <<EOF >$ROOT/etc/hosts.deny
#
# /etc/hosts.deny
#
# End of file
EOF

mkdir -p $ROOT/boot/boot/grub
cat <<EOF >$ROOT/boot/boot/grub/menu.lst
default 0
timeout 1

title  Arch Linux
	root   (hd0,0)
	kernel /vmlinuz26-ec2 root=/dev/xvda2 console=hvc0 ip=dhcp spinlock=tickless ro
EOF

cd $ROOT/boot
ln -s boot/grub .
cd ../..

sed -i.pacorig -e 's/#PasswordAuthentication yes/PasswordAuthentication no/' \
    -e 's/#UseDNS yes/UseDNS no/' $ROOT/etc/ssh/sshd_config

sed -i.pacorig -e 's/^# include/include/' \
    -e 's/# set \(nowrap\|softwrap\)/set \1/' $ROOT/etc/nanorc

cp $ROOT/etc/skel/.bash* $ROOT/root
cp $ROOT/etc/skel/.screenrc $ROOT/root
mv $ROOT/etc/fstab $ROOT/etc/fstab.pacorig

cat <<EOF >$ROOT/etc/fstab
$(blkid -c /dev/null -s UUID -o export ${EBSDEVICE}2) /     auto    defaults,compress,relatime 0 1
$(blkid -c /dev/null -s UUID -o export ${EBSDEVICE}1) /boot auto    defaults,noauto,relatime 0 0
/dev/xvdb /tmp  auto    defaults,relatime 0 0
/dev/xvda3 swap  swap   defaults 0 0
none      /proc proc    nodev,noexec,nosuid 0 0
none /dev/pts devpts defaults 0 0
none /dev/shm tmpfs nodev,nosuid 0 0
EOF

mv $ROOT/etc/makepkg.conf $ROOT/etc/makepkg.conf.pacorig
cp /etc/makepkg.conf $ROOT/etc/

mkdir $ROOT/opt/{sources,packages,srcpackages}
chmod 1777 $ROOT/opt/{sources,packages,srcpackages}

echo "%wheel ALL=(ALL) NOPASSWD: ALL" >> $ROOT/etc/sudoers
sed -i 's/bash/zsh/' $ROOT/etc/passwd
#curl -o $ROOT/root/.zshrc  "https://github.com/MrElendig/dotfiles-alice/raw/master/.zshrc"
#curl -o $ROOT/root/.vimrc "https://github.com/MrElendig/dotfiles-alice/raw/master/.vimrc"

mv $ROOT/etc/resolv.conf $ROOT/etc/resolv.conf.pacorig
echo "nameserver 172.16.0.23" > $ROOT/etc/resolv.conf

touch $ROOT/root/firstboot
cp -a /root/repo $ROOT/root/
cp -a /var/cache/pacman/pkg/. $ROOT/var/cache/pacman/pkg/

cd $ROOT
find . -depth -print | cpio -pdmv --sparse $NEWROOT
umount ${NEWROOT}/boot
umount ${NEWROOT}
