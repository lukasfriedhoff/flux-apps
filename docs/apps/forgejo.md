# Forgejo

Forgejo provides a self-hosted Git forge and package registry. This app deploys Forgejo with a CNPG PostgreSQL database, persistent repository data, HTTPS ingress, and a bootstrapped local admin account.

## Access

- Testing URL: `https://git-testing.h4xx.io`
- Admin user: `lukasf`
- Admin password:

  ```sh
  kubectl -n forgejo get secret forgejo-admin -o jsonpath='{.data.password}' | base64 -d; echo
  ```

Open registration is disabled and anonymous browsing is hidden. Create additional users from the admin UI or via Forgejo CLI/API.

## Git repositories

Create a repository in the Forgejo UI, then use HTTPS remotes:

```sh
git remote add forgejo https://git-testing.h4xx.io/lukasf/example.git
git push forgejo main
```

For automation, create a Forgejo access token under `User settings -> Applications`. Use that token as the HTTPS password for Git clients and CI jobs.

SSH is enabled inside the Forgejo pod, but the reusable app exposes only the HTTPS ingress by default. Add a Traefik TCP route, LoadBalancer, or NodePort before relying on `git@...` clone URLs.

## Container registry

Forgejo packages are enabled. Use a user or organization package namespace:

```sh
export FORGEJO_TOKEN='<token-with-package-write>'
echo "$FORGEJO_TOKEN" | docker login git-testing.h4xx.io -u lukasf --password-stdin
docker build -t git-testing.h4xx.io/lukasf/example:dev .
docker push git-testing.h4xx.io/lukasf/example:dev
docker pull git-testing.h4xx.io/lukasf/example:dev
```

For Kubernetes pulls, create an image pull secret in the consuming namespace:

```sh
kubectl create secret docker-registry forgejo-registry \
  --docker-server=git-testing.h4xx.io \
  --docker-username=lukasf \
  --docker-password="$FORGEJO_TOKEN" \
  --docker-email=lukasf@h4xx.io
```

Then reference it from workloads:

```yaml
imagePullSecrets:
  - name: forgejo-registry
```

## Other packages

Forgejo also supports package registries such as generic packages, npm, PyPI, NuGet, Maven, Cargo, and OCI/container images.

Examples:

```sh
# Generic package
curl --user lukasf:"$FORGEJO_TOKEN" \
  --upload-file ./artifact.tar.gz \
  https://git-testing.h4xx.io/api/packages/lukasf/generic/example/1.0.0/artifact.tar.gz

# PyPI
python -m twine upload \
  --repository-url https://git-testing.h4xx.io/api/packages/lukasf/pypi \
  -u lukasf \
  -p "$FORGEJO_TOKEN" \
  dist/*
```

## GitOps knobs

Cluster overlays should override only environment-specific values:

- `forgejo_suspend`: enable or disable the app.
- `forgejo_data_storage_class_name` / `forgejo_data_size`: repository and package data PVC.
- `forgejo_postgres_storage_class_name` / `forgejo_postgres_size`: database PVC.
- `forgejo_image`: pinned Forgejo version.
- `forgejo_admin_secret_name`: secret containing `username`, `password`, and `email`.

The ingress intentionally does not use Authelia forward-auth because Git and package clients need non-browser API access. Forgejo handles authentication itself, with registration disabled and anonymous browsing hidden.
