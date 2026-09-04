# matterjs-server

Helm chart for [Matter.js Server](https://github.com/matter-js/matterjs-server), a Matter controller server exposing a Python Matter Server-compatible WebSocket API and web dashboard.

## Prerequisites

- Kubernetes 1.23+
- Helm 3
- A Linux node meeting the upstream [Matter and Thread OS requirements](https://github.com/matter-js/matterjs-server/blob/main/docs/os_requirements.md)
- A CNI/network setup suitable for Matter multicast traffic, or `hostNetwork=true` (recommended upstream)

## Install

```console
helm install matterjs-server ./charts/matterjs-server
```

The default installation deliberately uses pod networking. This makes the Service reachable inside the cluster, but Matter/mDNS discovery generally needs host networking:

```console
helm upgrade --install matterjs-server ./charts/matterjs-server \
  --set hostNetwork=true
```

With host networking enabled, the server reserves TCP port `5580` on the pod's node. Schedule it onto an appropriate node with `nodeSelector` or affinity when needed.

## Access

The dashboard and WebSocket API share the configured port:

- Dashboard: `http://<address>:5580/`
- WebSocket API: `ws://<address>:5580/ws`
- Health: `http://<address>:5580/health`

For local access through the default ClusterIP Service:

```console
kubectl port-forward service/matterjs-server 5580:5580
```

> **Security:** Matter.js Server has no built-in authentication and binds to all interfaces by default. Restrict Service/host network access with firewall or network policy controls, set `config.LISTEN_ADDRESS` where appropriate, or use an authenticating reverse proxy. Do not expose it directly to the internet.

## Persistence

A `1Gi` `ReadWriteOnce` PVC is created by default and mounted at `/data`. The pod runs as UID/GID `1000`, with `fsGroup: 1000` so supported volume drivers make the data directory writable.

Use an existing claim:

```yaml
persistence:
  existingClaim: matterjs-data
```

For disposable testing only:

```yaml
persistence:
  enabled: false
  emptyDir:
    sizeLimit: 1Gi
```

Back up the PVC before application upgrades or migration from Python Matter Server. A normal StatefulSet update leaves the PVC intact; uninstalling the Helm release deletes a chart-created PVC unless your cluster/storage retention process protects it.

The workload is intentionally fixed at one replica. Running multiple controllers against one Matter fabric is not a supported high-availability strategy.

## Configuration

`PORT` and `STORAGE_PATH` are generated from `service.port` and `persistence.mountPath`. Other server options are supplied through the `config` map using the exact upstream environment names. Null values are omitted; `false` and `0` are emitted.

```yaml
config:
  LOG_LEVEL: debug
  PRIMARY_INTERFACE: eth0
  ENABLE_TIME_SYNC: true
  NODE_OPTIONS: --max-old-space-size=512
  MATTER_DCL_PRODUCTIONURL: https://on-ledger.dcl.example
```

Supported server variables include `LISTEN_ADDRESS`, `LOG_LEVEL`, `LOG_FILE`, `PRIMARY_INTERFACE`, `ENABLE_TEST_NET_DCL`, `DISABLE_DCL_SEED`, `BLE_PROXY`, `DISABLE_OTA`, `OTA_PROVIDER_DIR`, `OTA_UPLOAD_MAX_IN_FLIGHT`, `OTA_UPLOAD_MAX_SIZE_MB`, `DISABLE_DASHBOARD`, `PRODUCTION_MODE`, `VENDOR_ID`, `FABRIC_ID`, `DEFAULT_FABRIC_LABEL`, `DISABLE_THREAD_DIAGNOSTICS`, `ENABLE_TIME_SYNC`, and arbitrary advanced `MATTER_*` variables. `TZ` and `NODE_OPTIONS` configure the container runtime. See the upstream [Docker](https://github.com/matter-js/matterjs-server/blob/main/docs/docker.md) and [CLI](https://github.com/matter-js/matterjs-server/blob/main/docs/cli.md) documentation for semantics.

Use `extraEnv` for `valueFrom` entries and `envFrom` for complete Secrets/ConfigMaps. CLI `args` may also be supplied; CLI options override corresponding environment variables.

### Health probes

All probes execute the image's `/usr/local/bin/healthcheck.sh` against `/health`. The default startup probe allows up to 15 minutes, matching the upstream container health check. The script cannot resolve an interface name in `LISTEN_ADDRESS`; when setting that variable, use a literal address reachable inside the pod or override the probe definitions.

## Bluetooth via D-Bus

The recommended host BLE integration is disabled by default. It mounts the host BlueZ D-Bus directory read-only and configures the unprivileged D-Bus backend:

```yaml
bluetooth:
  enabled: true
  adapter: 0
  hostPath: /run/dbus
```

The selected node must run BlueZ with the adapter powered. Rootless/user-namespace runtimes may need UID mapping so container UID `1000` can authenticate to host D-Bus. The chart does not enable the discouraged privileged raw-HCI workaround.

## Image versioning

`image.tag` defaults to `Chart.appVersion`, currently `1.4.0`. Set `image.tag` to choose another release, or set `image.digest` (for example `sha256:...`) to pin immutable content; a digest takes precedence over the tag.

## Values

| Key | Default | Description |
| --- | --- | --- |
| `image.repository` | `ghcr.io/matter-js/matterjs-server` | Container repository |
| `image.tag` | `""` | Image tag; empty uses `appVersion` |
| `image.digest` | `""` | Optional immutable image digest |
| `hostNetwork` | `false` | Give the pod direct host networking |
| `dnsPolicy` | derived | Explicit DNS policy override |
| `service.enabled` | `true` | Create the API/dashboard Service |
| `service.type` | `ClusterIP` | Service type |
| `service.port` | `5580` | Server and Service TCP port |
| `persistence.enabled` | `true` | Use persistent storage instead of `emptyDir` |
| `persistence.existingClaim` | `""` | Existing PVC name |
| `persistence.size` | `1Gi` | New PVC request size |
| `persistence.storageClass` | `""` | StorageClass; `-` disables dynamic class selection |
| `persistence.mountPath` | `/data` | Data path and generated `STORAGE_PATH` |
| `config` | see `values.yaml` | Matter.js environment-variable map |
| `extraEnv`, `envFrom`, `args` | `[]` | Advanced process configuration |
| `bluetooth.enabled` | `false` | Enable host BlueZ D-Bus BLE backend |
| `serviceAccount.create` | `true` | Create a dedicated ServiceAccount |
| `podSecurityContext` | UID/GID/fsGroup `1000` | Pod security settings |
| `securityContext` | hardened + `NET_RAW` | Container security settings; `NET_RAW` supports ping |
| `probes` | enabled | Startup/readiness/liveness exec probes |
| `resources` | `{}` | Container requests and limits |
| `extraVolumes`, `extraVolumeMounts` | `[]` | Additional pod storage |
| `nodeSelector`, `affinity`, `tolerations` | empty | Pod scheduling controls |
| `topologySpreadConstraints` | `[]` | Pod topology spread rules |
| `priorityClassName` | `""` | Pod priority class |
| `terminationGracePeriodSeconds` | `30` | Graceful shutdown window |

See [`values.yaml`](values.yaml) for the complete defaults and metadata options.

## Test

```console
helm test matterjs-server
```

The test calls `/health` through the chart Service.
