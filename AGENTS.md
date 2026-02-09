# Flux-Apps Repo Agent Notes

- this repo should not contain any cluster specific config, only apps, versions and sane defaults.
- helm values should be merged from sane defaults in this repo with cluster specific config via flux-cluster repo config maps/secrets
- always use conventional commits