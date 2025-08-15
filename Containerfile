FROM quay.io/fedora/fedora-silverblue:42

RUN --mount=type=cache,dst=/var/cache/dnf \
    --mount=type=cache,dst=/var/cache/libdnf5 \
	dnf install -y https://zfsonlinux.org/fedora/zfs-release-2-8$(rpm --eval "%{dist}").noarch.rpm \
	&& dnf install -y kernel-devel-$(rpm -q kernel | cut -d- -f2-) zfs zfs-dkms zfs-dracut \
	&& depmod -a $(rpm -q kernel | cut -d- -f2-) \
	&& ostree container commit
