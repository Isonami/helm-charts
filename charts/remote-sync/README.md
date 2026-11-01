# Remote Sync Helm chart

A standalone chart based on the sibling Kustomize configuration, using a
Deployment with a `Recreate` strategy to avoid overlapping pods during upgrades.
It does not replace or participate in the repository's Kustomize aggregates.

## Prerequisites

- Traefik and its `IngressRoute` CRD (or set `ingressRoute.enabled=false`).
- A `remote-sync-env` Secret containing `session_secret`, `oidc_client_secret`,
  and `REDIS_URL` (which may contain Redis credentials).
- A `remote-sync-ssh` Secret containing `knownhosts`, `remote_sync_ls`, and
  `remote_sync_rsync`.
- The trust-manager `ca-bundle` ConfigMap with key `trust-bundle.pem` in the
  release namespace (or set `caBundle.enabled=false`).
- The replicated TLS Secret `star-srv-nl-isona-me` in the release namespace.
- By default, the pre-provisioned PV `storage-data-remote-sync` and storage class
  `local-storage`. Override `persistence.volumeName` and `storageClass` for
  dynamic provisioning, or set `persistence.existingClaim` to reuse a PVC.

## New installation

Prepare the ignored Secret inputs using the `.example` files in
`../bootstrap/secrets/`, then apply the existing bootstrap:

```sh
kubectl apply -k apps/remote-sync/bootstrap
helm lint apps/remote-sync/chart
helm upgrade --install remote-sync apps/remote-sync/chart \
  --namespace remote-sync --wait
```

Do not also apply the Kustomize app package for the same installation.
Namespaces and credentials are deliberately not managed by this chart.
For another namespace, provision all prerequisites there separately. The chart
can create the TLS replication stub with `ingressRoute.createTlsSecret=true`;
leave this disabled when the bootstrap already owns the Secret.

## Existing Kustomize installation

Helm cannot automatically take ownership of existing resources. Back up data
and plan a maintenance window. Stop and remove the original StatefulSet before
installing the chart's Deployment; Helm will not remove it automatically.

Keep the `storage-data` PVC and install with
`--set persistence.existingClaim=storage-data`. Remove the old StatefulSet,
Service, and IngressRoute before installing Helm, but do not delete the PVC,
bootstrap Secrets, or namespace. Remove the app from the Kustomize aggregate
before future reconciliation, or Kustomize will recreate the old resources.
The chart does not perform these migration steps automatically.

## Optional MQTT integration

Add any of these keys to the external `remote-sync-env` Secret to inject them
as environment variables: `MQTT_BROKER`, `MQTT_TOPIC`, `MQTT_USERNAME`, and
`MQTT_PASSWORD`. They are omitted by default; the bootstrap example includes
commented entries to enable as needed. Keep credentials in the Secret, not Helm
values. Reapply bootstrap and restart the Deployment after changing them.

## Kubernetes API access

The Deployment uses a dedicated ServiceAccount with an API token mounted for
in-cluster authentication. Its namespace-scoped Role permits only `get` on
`pods` and `create` on `batch/jobs`. The Downward API supplies `POD_NAME` and
`POD_NAMESPACE` so the application can fetch its own Pod specification. These
environment names are reserved; do not override them in `env`.

RBAC cannot dynamically scope a Role to the current generated Pod name: the
account can get any Pod by name in the release namespace. It cannot list/watch
Pods or read Secret/ConfigMap contents. Reading a Pod returns references to
those resources, not their contents. Job creation does not grant Job monitoring,
update, or deletion permissions.

Creating Jobs is a powerful permission: Job templates can mount namespace
Secrets/PVCs and select other ServiceAccounts. Use a dedicated namespace and
admission policies if job templates are not fully trusted. This Role alone
cannot enforce allowed images, mounts, or ServiceAccounts.

Set `serviceAccount.create=false` and `serviceAccount.name` to use an existing
account. Set `rbac.create=false` when permissions are provisioned externally.

## Configuration

See `values.yaml` for all options. Defaults preserve the current hostnames,
OIDC settings, remote endpoint, storage binding, and image version. Override
these for other environments. Keep secret values out of values files; supply
them through the external Secrets. Configure `REDIS_URL` in the `remote-sync-env`
Secret (the key must be uppercase); it is injected through `envFrom`. Do not set
`env.REDIS_URL`, which would override the Secret value and expose credentials in
Helm values and the Deployment. `image.tag` defaults to `Chart.appVersion`.

The chart-created PVC has `helm.sh/resource-policy: keep` to preserve data on
uninstall; removing retained PVCs is a separate manual operation. The default
PVC name and PV binding are intended for a single installation; use distinct
claims and storage bindings for additional releases.

The CA file uses `subPath` and SSH/credential changes do not automatically
trigger a rollout. Restart after updating these dependencies:

```sh
kubectl rollout restart deployment/remote-sync -n remote-sync
```

Render without installing:

```sh
helm template remote-sync apps/remote-sync/chart --namespace remote-sync
```
