FROM quay.io/fedora/fedora-silverblue:43

ADD ./tuxedo.repo /etc/yum.repos.d/tuxedo.repo

RUN --mount=type=cache,dst=/var/cache/dnf \
    --mount=type=cache,dst=/var/cache/libdnf5 \
	dnf install -y https://zfsonlinux.github.io/fedora/zfs-release-3-0$(rpm --eval "%{dist}").noarch.rpm \
	&& dnf install -y kernel-devel-$(rpm -q kernel | cut -d- -f2-) zfs zfs-dkms zfs-dracut \
	&& dkms install -k $(rpm -q kernel | cut -d- -f2-) zfs/$(rpm -q --queryformat '%{VERSION}' zfs-dkms) \
	&& dracut -f --add-drivers "zfs" --verbose --regenerate-all
	
RUN --mount=type=cache,dst=/var/cache/dnf \
    --mount=type=cache,dst=/var/cache/libdnf5 \
	dnf install -y tuxedo-drivers --setopt=tsflags=noscripts \
	&& dkms install -k $(rpm -q kernel | cut -d- -f2-) tuxedo-drivers/$(rpm -q --queryformat '%{VERSION}' tuxedo-drivers)
RUN ostree container commit
