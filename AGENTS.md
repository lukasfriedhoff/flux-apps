# Flux-Apps Repo Agent Notes

- this repo should not contain any cluster specific config, only apps, versions and sane defaults.
- helm values should be merged from sane defaults in this repo with cluster specific config via flux-cluster repo config maps/secrets
- always use conventional commits
- storage decisions:
  - prefer Ceph RBD for stateful single-writer workloads (db, cache, app data) for performance/latency.
  - prefer CephFS for shared RWX data that must be accessed by multiple pods (e.g., Nextcloud user data, scale-out file shares).
  - local-path is only for dev/test or truly ephemeral data.
  - scaling Nextcloud beyond 1 replica requires shared writable storage for data (and ideally config/custom_apps), so CephFS or object storage is needed.
- while integrating new apps, always focus on scalability by default
- never use bitnami charts or images
- avoid deprecated charts
- maintain `examples/apps/<app>/` for every app:
  - `base-config.defaults.yaml` lists app substitution keys with sane defaults.
  - `flux-cluster-kustomization.yaml` shows how the app is wired from a cluster repo.
- when app placeholders (`${...}`) change, update the matching `examples/apps/<app>/base-config.defaults.yaml` in the same commit.
- examples must stay cluster-agnostic (no secret values, no per-cluster overrides).
