FROM quay.io/fedora/fedora-silverblue:42 AS ref

RUN rpm -q kernel | cut -d- -f2- > /tmp/kernel-version

FROM quay.io/fedora/fedora:42 AS builder

RUN --mount=type=cache,dst=/var/cache/dnf \
    --mount=type=cache,dst=/var/cache/libdnf5 \
        dnf install -y gpg autoconf automake dkms git jq libtool ncompress python-cffi rpm-build
COPY --from=ref /tmp/kernel-version /tmp/kernel-version
RUN --mount=type=cache,dst=/var/cache/dnf \
    --mount=type=cache,dst=/var/cache/libdnf5 \
        dnf install -y kernel-$(cat /tmp/kernel-version)

COPY ./ublue-os_akmods/build_files/zfs/build-kmod-zfs.sh /tmp/

ENV KERNEL_NAME=kernel
RUN --mount=type=cache,dst=/var/cache/dnf \
    --mount=type=cache,dst=/var/cache/libdnf5 \
        /tmp/build-kmod-zfs.sh


FROM quay.io/fedora/fedora-silverblue:42

COPY --from=builder /var/cache/rpms/kmods/zfs/*.rpm /var/cache/rpms/kmods/zfs/other/*.rpm /tmp/akmod-zfs/

RUN rpm-ostree install /tmp/akmod-zfs/*.rpm && ostree container commit