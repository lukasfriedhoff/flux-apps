# Flux Apps Examples

This folder documents the default integration contract between `flux-apps` and a `flux-cluster` repository.

## Goal
- Keep app manifests in `flux-apps/apps/*` cluster-agnostic.
- Keep sane default substitutions in cluster `base/base-config.yaml`.
- Keep cluster-specific deltas only in overlay patches (for example `overlays/<cluster>/cluster-patch.yaml`).

## Per-app examples
Each app has:
- `examples/apps/<app>/base-config.defaults.yaml`: app-specific keys expected in `base-config` with sane defaults.
- `examples/apps/<app>/flux-cluster-kustomization.yaml`: a Flux Kustomization example for cluster integration.

## How to integrate an app into a flux-cluster repo
1. Copy or adapt `examples/apps/<app>/flux-cluster-kustomization.yaml` into your cluster repo under `base/kustomizations/infra/`.
2. Ensure the app Kustomization has:
   - `sourceRef.name: flux-apps`
   - `spec.path: ./apps/<app>`
   - `postBuild.substituteFrom` pointing to `ConfigMap/base-config`.
3. Merge the keys from `examples/apps/<app>/base-config.defaults.yaml` into `base/base-config.yaml`.
4. Only override keys that differ per cluster in `overlays/<cluster>/cluster-patch.yaml`.

## Notes
- Secret material must stay in `flux-cluster` overlays (typically encrypted with SOPS).
- If an app adds/removes `${...}` substitutions, update this `examples/` folder in the same change.
