#!/bin/bash
set -euxo pipefail

DISK=/dev/sda
POOL=rpool

dnf install -y sgdisk

# Partition disk
sgdisk --zap-all $DISK
sgdisk -n1:0:+1G -t1:EF00 -c1:EFI $DISK
sgdisk -n2:0:+4G -t2:8300 -c2:BOOT $DISK
sgdisk -n3:0:0 -t3:BF00 -c3:ZFS $DISK
partprobe $DISK

# Format EFI/boot
mkfs.vfat -F32 ${DISK}1
mkfs.ext4 ${DISK}2

# Install ZFS
dnf install -y https://zfsonlinux.org/fedora/zfs-release-2-8$(rpm --eval "%{dist}").noarch.rpm
dnf install -y --allowerasing kernel-devel-$(uname -r) zfs zfs-dkms

# Create ZFS pool
zpool create -f \
    -o ashift=12 \
    -o autotrim=on \
    -O acltype=posixacl \
    -O compression=zstd \
    -O dnodesize=auto \
    -O normalization=formD \
    -O relatime=on \
    -O xattr=sa \
    -O mountpoint=none \
    -R /mnt \
    $POOL ${DISK}3

# Create datasets
zfs create -o mountpoint=none $POOL/ROOT
zfs create -o mountpoint=/ -o canmount=noauto $POOL/ROOT/silverblue
zfs create -o mountpoint=/var $POOL/var
for i in home opt srv mnt roothome usrlocal
do
    zfs create "$POOL/var/$i"
done


# Mount ZFS root
zpool set bootfs=$POOL/ROOT/silverblue $POOL
zfs mount $POOL/ROOT/silverblue
zfs mount -a

# Mount boot/EFI
mkdir -p /mnt/boot
mount ${DISK}2 /mnt/boot
mkdir -p /mnt/boot/efi
mount ${DISK}1 /mnt/boot/efi

# Bootstrap ostree
dnf install -y ostree rpm-ostree

ostree admin init-fs /mnt
ostree admin os-init --sysroot=/mnt fedora
ostree remote add --repo=/mnt/ostree/repo fedora https://d2uk5hbyrobdzx.cloudfront.net/ --no-gpg-verify

# Pull and deploy Silverblue
ostree pull --repo=/mnt/ostree/repo fedora:fedora/42/x86_64/silverblue
ostree admin deploy --os=fedora --osname=fedora --sysroot=/mnt fedora:fedora/42/x86_64/silverblue

# Get deployment path
DEPLOY_PATH=$(ls -d /mnt/ostree/deploy/fedora/deploy/*.0)

read

# Setup ostree symlinks and directories
mkdir -p $DEPLOY_PATH/sysroot
ln -s /sysroot/ostree $DEPLOY_PATH/ostree

# Create FHS symlinks for ostree
ln -sfn /var/home $DEPLOY_PATH/home
ln -sfn /var/opt $DEPLOY_PATH/opt
ln -sfn /var/srv $DEPLOY_PATH/srv
ln -sfn /var/roothome $DEPLOY_PATH/root
ln -sfn /var/usrlocal $DEPLOY_PATH/usr/local
ln -sfn /var/mnt $DEPLOY_PATH/mnt
ln -sfn /sysroot/tmp $DEPLOY_PATH/tmp

# Create systemd-tmpfiles config
mkdir -p $DEPLOY_PATH/usr/lib/tmpfiles.d
cat > $DEPLOY_PATH/usr/lib/tmpfiles.d/ostree-var.conf <<EOF
d /var/log/journal 0755 root root -
L /var/home - - - - ../sysroot/home
d /var/opt 0755 root root -
d /var/srv 0755 root root -
d /var/roothome 0700 root root -
d /var/usrlocal 0755 root root -
d /var/usrlocal/bin 0755 root root -
d /var/usrlocal/etc 0755 root root -
d /var/usrlocal/games 0755 root root -
d /var/usrlocal/include 0755 root root -
d /var/usrlocal/lib 0755 root root -
d /var/usrlocal/man 0755 root root -
d /var/usrlocal/sbin 0755 root root -
d /var/usrlocal/share 0755 root root -
d /var/usrlocal/src 0755 root root -
d /var/mnt 0755 root root -
d /run/media 0755 root root -
EOF

# Create initial /var structure
mkdir -p /mnt/var/{home,opt,srv,roothome,usrlocal,mnt,log/journal}

# Mount binds for chroot
mount --bind /dev /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys

# Configure fstab
cat > /mnt/etc/fstab <<EOF
$POOL/ROOT/silverblue / zfs defaults,x-systemd.requires=zfs-import.target 0 0
UUID=$(blkid -s UUID -o value ${DISK}p2) /boot ext4 defaults 0 0
UUID=$(blkid -s UUID -o value ${DISK}p1) /boot/efi vfat defaults 0 0
EOF

# Install ZFS in deployment
chroot $DEPLOY_PATH <<CHROOT
rpm-ostree install https://zfsonlinux.org/fedora/zfs-release-2-8.fc42.noarch.rpm
rpm-ostree install zfs zfs-dkms
echo 'zfs' > /etc/modules-load.d/zfs.conf
dracut -f --add-drivers "zfs" --kver \$(uname -r)
CHROOT

# Configure ostree-prepare-root
mkdir -p $DEPLOY_PATH/usr/lib/ostree
cat > $DEPLOY_PATH/usr/lib/ostree/prepare-root.conf <<EOF
[root]
transient = false
EOF

# Bootloader
chroot $DEPLOY_PATH <<CHROOT
grub2-mkconfig -o /boot/grub2/grub.cfg
grub2-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Fedora
echo 'GRUB_CMDLINE_LINUX="root=ZFS=$POOL/ROOT/silverblue ostree=/ostree/boot.1/fedora/\$(cat /ostree/deploy/fedora/deploy/*.0.origin | grep refspec | cut -d= -f2)/0"' >> /etc/default/grub
grub2-mkconfig -o /boot/grub2/grub.cfg
CHROOT

# Cleanup
umount -R /mnt
zpool export $POOL