# Nextcloud with smbclient baked in.
#
# The official image ships no SMB support; installing it at pod start via a
# hook lost to the fresh-pod egress blackout on 2026-09-21 (a full rollout
# came up without smbclient and the broken SMB mounts taxed every request
# with StorageNotAvailable). Baking it in removes the runtime apt dependency
# entirely.
#
# Renovate bumps the FROM tag; the build workflow derives the pushed image
# tag from it (harbor.h4xx.io/library/nextcloud:<same tag>). Merge order on
# upstream bumps: this Dockerfile PR FIRST (builds the new tag), then the
# helm values PR in apps/nextcloud that points at it.
FROM docker.io/library/nextcloud:34.0.4-apache

# DL3008: the base tag is the pin; smbclient point versions rotate out of
# the debian archive and would break rebuilds.
# hadolint ignore=DL3008
RUN apt-get update \
 && apt-get install -y --no-install-recommends smbclient \
 && rm -rf /var/lib/apt/lists/*
