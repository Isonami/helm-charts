# openthread-border-router

Helm chart for the official [OpenThread Border Router (OTBR)](https://openthread.io/guides/border-router) container. It runs one OTBR instance in a StatefulSet, persists Thread state, and exposes the web UI and REST API through a Kubernetes Service.

## Prerequisites

- Kubernetes 1.23+
- Helm 3
- A Linux node with an OpenThread RCP, normally attached at `/dev/ttyACM0`
- `/dev/net/tun` on that node
- A container runtime/security policy that permits `NET_ADMIN` and the required character devices
- Host IPv4/IPv6 forwarding and router-advertisement settings configured for the infrastructure interface

OTBR controls host routes, interfaces, and firewall rules. It is a hardware-bound, node-level service rather than a portable application workload.

## Prepare the host

Run the upstream setup script on the node that will host OTBR. The infrastructure interface passed here must match `config.infraInterface` in the chart:

```console
curl -sSL https://raw.githubusercontent.com/openthread/ot-br-posix/refs/heads/main/etc/docker/border-router/setup-host \
  | INFRA_IF_NAME=eth0 bash
```

The script enables IPv4/IPv6 forwarding and configures IPv6 router-advertisement handling. Review it before running it and arrange for these settings to persist on the node.

Label the node so the StatefulSet always returns to the node holding the RCP:

```console
kubectl label node my-thread-node hardware.example.com/thread-rcp=true
```

```yaml
nodeSelector:
  hardware.example.com/thread-rcp: "true"
```

## Install

```console
helm upgrade --install otbr ./openthread-border-router \
  --set nodeSelector.hardware\.example\.com/thread-rcp=true
```

The defaults use host networking, `/dev/ttyACM0`, `/dev/net/tun`, `eth0`, and a UART baud rate of `1000000`. Adjust these values for the target node.

```yaml
config:
  infraInterface: enp1s0
  rcp:
    baudrate: 460800
    device:
      hostPath: /dev/ttyUSB0
      containerPath: /dev/ttyUSB0
```

`OT_INFRA_IF` is not only a host-setup input: OTBR uses it for Border Routing, TREL, forwarding, and NAT64 rules. It must be the actual adjacent Ethernet or Wi-Fi interface on the node.

## Networking and access

Host networking is enabled by default because Thread routing, IPv6 multicast, mDNS, and TREL require direct access to the node network namespace. It can be disabled when a specialized CNI provides equivalent functionality:

```yaml
hostNetwork: false
```

The Service exposes:

- Web UI: TCP 8080
- REST API: TCP 8081

For local access:

```console
kubectl port-forward service/otbr-openthread-border-router 8080:8080 8081:8081
```

Then open `http://127.0.0.1:8080/`. The chart sets both `OT_WEB_LISTEN_ADDR` and `OT_REST_LISTEN_ADDR` from the pod IP through Kubernetes' Downward API; the official image defaults both to loopback, which would make a Kubernetes Service unable to reach them.

> **Security:** OTBR's web UI and REST API do not authenticate clients. Restrict Service and host-network access with firewalls, network controls, or an authenticating reverse proxy. Do not publish either endpoint directly to the internet. With host networking, ports 8080 and 8081 are also bound on the selected node.

Disable the Service if only host-network access is needed:

```yaml
service:
  enabled: false
```

## RCP and device access

The default Spinel URL is generated from `config.rcp.device.containerPath` and `config.rcp.baudrate`:

```text
spinel+hdlc+uart:///dev/ttyACM0?uart-baudrate=1000000
```

The USB device mount is optional and its host and container paths are independently configurable. For a network-attached RCP, disable the mount and provide the complete URL:

```yaml
config:
  rcp:
    url: spinel+hdlc+uart+tcp://192.0.2.10:6638
    device:
      enabled: false
```

A URL is required when the device mount is disabled. Network RCP links may be less reliable than the direct UART/SPI connection expected by OTBR.

### Akri device discovery

For an RCP allocated by [Akri](https://docs.akri.sh/), enable the optional startup wrapper:

```yaml
config:
  rcp:
    akriDiscovery:
      enabled: true
```

Akri must expose the allocated device to the container and inject one or more `UDEV_DEVNODE_*` environment variables. The bundled `akri-discovery.sh` checks those variables in lexical name order, selects the first value matching `/dev/tty*`, and exports a Spinel URL such as:

```text
OT_RCP_DEVICE=spinel+hdlc+uart:///dev/ttyACM0?uart-baudrate=1000000
```

The baud rate comes from `config.rcp.baudrate`. Enabling Akri discovery suppresses the chart's regular RCP hostPath mount and static `OT_RCP_DEVICE`; `config.rcp.url` is ignored. Startup fails with a clear error when no matching `UDEV_DEVNODE_*` value exists. The TUN mount remains independently controlled by `config.tunDevice`.

The wrapper is packaged as `scripts/akri-discovery.sh`, mounted read-only from a ConfigMap, and then executes the image's normal `/init` entrypoint.

The TUN mount can also be changed or disabled through `config.tunDevice`, although normal Border Router operation requires it.

## Security context

Pod-level and container-level settings are configured independently through `podSecurityContext` and `containerSecurityContext`.

The container runs as root with `NET_ADMIN`, matching the upstream requirement to create interfaces and modify routing/firewall state. `containerSecurityContext.privileged` defaults to `false` as the narrower starting point:

```yaml
containerSecurityContext:
  privileged: false
```

Kubernetes has no portable equivalent of Docker's `--device`. Depending on the container runtime, cgroup policy, and admission controls, a hostPath device mount plus `NET_ADMIN` may still be blocked. If logs show permission errors opening the RCP/TUN device or managing networking, enable privileged mode after reviewing the security impact:

```console
helm upgrade otbr ./openthread-border-router \
  --reuse-values \
  --set containerSecurityContext.privileged=true
```

Privileged mode grants broad host access. Pin OTBR to a trusted node and restrict who can modify the release.

The following pod sysctls are included as a commented example in `values.yaml`:

```yaml
hostNetwork: false
podSecurityContext:
  sysctls:
    - name: net/ipv6/conf/all/forwarding
      value: "1"
    - name: net/ipv4/ip_forward
      value: "1"
    - name: net/ipv6/conf/net1/accept_ra
      value: "2"
    - name: net/ipv6/conf/net1/accept_ra_rt_info_max_plen
      value: "64"
```

Kubernetes does not allow `net.*` pod sysctls together with `hostNetwork: true`, so they are intentionally commented while host networking remains enabled by default. With host networking, configure equivalent settings on the node as described in [Prepare the host](#prepare-the-host). With pod networking, ensure the cluster allows these unsafe sysctls and that `net1` is the intended interface.

### Kernel modules

A privileged init container loads the host kernel modules required by OTBR's firewall setup before the main container starts:

- `ip_set`
- `xt_set`
- `xt_pkttype`
- `nf_tables`
- `nft_compat`

It mounts the node's `/lib/modules` directory read-only and runs `modprobe` for each configured module. Configure or disable it through `kernelModules`:

```yaml
kernelModules:
  enabled: true
  hostPath: /lib/modules
  modules:
    - ip_set
    - xt_set
    - xt_pkttype
    - nf_tables
    - nft_compat
```

Disable the loader when modules are already managed by the node operating system or privileged init containers are prohibited. Additional entries in `extraInitContainers` run after the module loader.

## Persistence

A `1Gi` `ReadWriteOnce` PVC is created by default and mounted at `/data`. OTBR stores Thread settings below `/data/thread`.

Use an existing claim:

```yaml
persistence:
  existingClaim: otbr-data
```

For disposable testing:

```yaml
persistence:
  enabled: false
  emptyDir:
    sizeLimit: 1Gi
```

Back up the PVC before replacing the RCP, changing network credentials, or performing major upgrades. The StatefulSet is fixed at one replica because one RCP and one persisted Thread state must not be driven concurrently.

## Image and upgrades

The image defaults to `openthread/border-router:latest`, matching the upstream Docker guide. For reproducible production upgrades, set an immutable digest:

```yaml
image:
  digest: sha256:...
```

A digest takes precedence over `image.tag`. Review upstream release changes, back up the PVC, then upgrade the release. StatefulSet rolling updates stop the sole old pod before the replacement can use the same RCP and `ReadWriteOnce` volume.

## Configuration

| Key | Default | Description |
| --- | --- | --- |
| `image.repository` | `openthread/border-router` | Official container repository |
| `image.tag` | `""` | Image tag; empty uses `Chart.appVersion` (`latest`) |
| `image.digest` | `""` | Optional immutable image digest |
| `hostNetwork` | `true` | Use the node network namespace |
| `config.infraInterface` | `eth0` | Adjacent infrastructure interface |
| `config.threadInterface` | `wpan0` | Thread interface created by OTBR |
| `config.logLevel` | `7` | OTBR numeric log level |
| `config.rcp.url` | `""` | Explicit Spinel URL; overrides generated UART URL |
| `config.rcp.baudrate` | `1000000` | Baud rate used in the generated URL |
| `config.rcp.device.enabled` | `true` | Mount a local USB/UART RCP device |
| `config.rcp.device.hostPath` | `/dev/ttyACM0` | RCP path on the node |
| `config.rcp.device.containerPath` | `/dev/ttyACM0` | RCP path inside the container |
| `config.rcp.akriDiscovery.enabled` | `false` | Discover the first `/dev/tty*` from `UDEV_DEVNODE_*` at startup |
| `config.rcp.akriDiscovery.mountPath` | `/opt/otbr` | Read-only directory containing `akri-discovery.sh` |
| `config.tunDevice.enabled` | `true` | Mount the TUN device |
| `config.tunDevice.hostPath` | `/dev/net/tun` | TUN path on the node |
| `service.enabled` | `true` | Create the web/REST Service |
| `service.web.port` | `8080` | Web listener and Service port |
| `service.rest.port` | `8081` | REST listener and Service port |
| `persistence.enabled` | `true` | Use persistent storage instead of `emptyDir` |
| `persistence.existingClaim` | `""` | Existing PVC name |
| `persistence.size` | `1Gi` | New PVC request size |
| `podSecurityContext` | RuntimeDefault seccomp | Pod security settings; optional non-host-network sysctls are commented in `values.yaml` |
| `containerSecurityContext.privileged` | `false` | Run the OTBR container privileged when required by the runtime |
| `kernelModules.enabled` | `true` | Run the privileged kernel-module loader init container |
| `kernelModules.hostPath` | `/lib/modules` | Node kernel-module directory mounted read-only |
| `kernelModules.modules` | OTBR firewall modules | Modules loaded with `modprobe` before OTBR starts |
| `extraEnv`, `envFrom` | `[]` | Additional environment sources |
| `extraInitContainers` | `[]` | Additional init containers rendered after the module loader |
| `extraVolumes`, `extraVolumeMounts` | `[]` | Additional pod storage |
| `nodeSelector`, `affinity`, `tolerations` | empty | Pin OTBR to its hardware node |
| `resources` | `{}` | Container requests and limits |

Chart-managed `OT_*` entries cannot be duplicated in `extraEnv`; use their corresponding structured values. `envFrom` remains available for unrelated advanced image settings.

See [`values.yaml`](values.yaml) for all metadata, probe, storage, scheduling, and test-image options.

## Verify and troubleshoot

```console
kubectl get pod -l app.kubernetes.io/instance=otbr -o wide
kubectl logs otbr-openthread-border-router-0
helm test otbr
```

Successful logs show the RCP protocol/version exchange, creation of `wpan0`, and startup of `otbr-agent` and `otbr-web`. Common failures are an incorrect infrastructure interface, absent device path, unsupported RCP baud rate, missing host sysctls, device-cgroup denial, or another process already using ports 8080/8081.
