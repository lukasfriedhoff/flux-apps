# MinIO client, built from nixpkgs.
#
# MinIO withdrew public distribution of mc in 2025: quay.io/minio/mc and
# docker.io/minio/mc now return 401 for every tag, and the dl.min.io binaries
# return 410 Gone. That broke every bucket-bootstrap job here at once. nixpkgs
# still packages it from source, so we build our own and push to Harbor.
#
# Not replaceable by rclone or the aws CLI: two of the jobs use `mc admin user`
# and `mc admin policy`, which are MinIO's admin API, not S3.
FROM nixos/nix:2.31.2 AS build

# nixpkgs pin. Bump this (and MC_VERSION below) to upgrade.
ARG NIXPKGS_REF=nixos-unstable
RUN nix \
      --extra-experimental-features 'nix-command flakes' \
      --option filter-syscalls false \
      build "github:NixOS/nixpkgs/${NIXPKGS_REF}#minio-client" --out-link /tmp/mc

# Copy the runtime closure: the binary is dynamically linked against glibc in
# the nix store, so the bare executable is useless on its own.
SHELL ["/bin/sh", "-o", "pipefail", "-c"]
RUN mkdir -p /output/nix/store \
 && nix --extra-experimental-features 'nix-command' path-info -r /tmp/mc \
      | xargs -I{} cp -a {} /output/nix/store/ \
 && mkdir -p /output/bin \
 && cp -aL /tmp/mc/bin/mc /output/bin/mc

# alpine, not scratch: the bootstrap Jobs all run `/bin/sh -ceu` scripts.
FROM alpine:3.22

# hadolint ignore=DL3018  # alpine patch releases rename the pin; unpinned is deliberate
RUN apk add --no-cache ca-certificates
COPY --from=build /output/nix/store /nix/store
COPY --from=build /output/bin/mc /usr/bin/mc

# mc writes its config here; the Jobs run as non-root in some namespaces.
ENV MC_CONFIG_DIR=/tmp/.mc
RUN mc --version

ENTRYPOINT []
CMD ["/bin/sh"]
