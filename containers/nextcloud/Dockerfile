# Nextcloud with smbclient baked in.
#
# The official image ships no SMB support; installing it at pod start via a
# hook lost to the fresh-pod egress blackout on 2026-09-21 (a full rollout
# came up without smbclient and the broken SMB mounts taxed every request
# with StorageNotAvailable). Baking it in removes the runtime apt dependency
# entirely.
#
# Upgrade pipeline (each step is automated; humans only merge PRs):
#   1. Renovate bumps the FROM tag below (its PR runs verify-nextcloud-apps,
#      which checks every app pinned in apps/nextcloud/helm-release.yaml
#      against the appstore compat matrix for the NEW Nextcloud version).
#   2. Merging that PR triggers build-nextcloud-image: it builds and pushes
#      harbor.h4xx.io/library/nextcloud:<same tag>, then auto-opens a PR
#      bumping the image tag in apps/nextcloud/helm-release.yaml.
#   3. Merging the auto-PR rolls it out via flux; the seed-custom-apps init
#      container and verify-custom-apps re-validate every app pin in-cluster.
# Never bump the helm values tag before the Harbor tag exists (step 2).
FROM docker.io/library/nextcloud:35.0.2-apache

# DL3008: the base tag is the pin; smbclient point versions rotate out of
# the debian archive and would break rebuilds.
# hadolint ignore=DL3008
RUN apt-get update \
 && apt-get install -y --no-install-recommends smbclient \
 && rm -rf /var/lib/apt/lists/*
