FROM quay.io/fedora/fedora-silverblue:42 AS ref

RUN rpm -q kernel | cut -d- -f2- > /tmp/kernel-version

FROM quay.io/fedora/fedora:42 AS builder

RUN --mount=type=cache,dst=/var/cache/dnf \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=bind,from=ref,source=/tmp/kernel-version,target=/tmp/kernel-version \
        dnf install -y \
            gpg autoconf automake dkms git jq libtool ncompress python-cffi rpm-build kernel-$(cat /tmp/kernel-version)

COPY ./ublue-os_akmods/build_files/zfs/build-kmod-zfs.sh /tmp/

ENV KERNEL_NAME=kernel
RUN --mount=type=cache,dst=/var/cache/dnf \
    --mount=type=cache,dst=/var/cache/libdnf5 \
        /tmp/build-kmod-zfs.sh

FROM quay.io/fedora/fedora:42 AS installer

RUN --mount=type=cache,dst=/var/cache/dnf \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=bind,from=builder,source=/var/cache/rpms/kmods/zfs,target=/tmp/kmods-zfs \
    --mount=type=bind,from=ref,source=/tmp/kernel-version,target=/tmp/kernel-version \
    dnf install -y /tmp/kmods-zfs/*.rpm /tmp/kmods-zfs/other/*.rpm && \
        depmod $(cat /tmp/kernel-version)

FROM quay.io/fedora/fedora-silverblue:42

RUN --mount=type=cache,dst=/var/cache/dnf \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=bind,from=builder,source=/var/cache/rpms/kmods/zfs,target=/tmp/kmods-zfs \
    rpm-ostree install -y /tmp/kmods-zfs/*.rpm /tmp/kmods-zfs/other/*.rpm

COPY --from=installer /usr/lib/modules /usr/lib/modules

RUN ostree container commit