# Inception-of-Things

This repository implements all three mandatory parts of the IoT subject, plus the bonus:

- `p1`: two Vagrant machines, one K3s server and one K3s agent.
- `p2`: one Vagrant machine, three web applications, three replicas for app 2, and host-based routing through Traefik Ingress.
- `p3`: a K3d cluster (no Vagrant) with Argo CD continuously deploying an app from a public GitHub repository into a `dev` namespace.
- `bonus`: a local GitLab instance running inside the `p3` cluster, with a second Argo CD Application that deploys the same kind of app from that GitLab instance instead of GitHub.

The default login is `tmoragli`, so the required VM hostnames are `tmoragliS` and `tmoragliSW`. Kubernetes object names must be lowercase DNS names, so the corresponding node names shown by `kubectl` are `tmoraglis` and `tmoraglisw`.

```bash
make LOGIN=yourlogin up
```

## Prerequisites

Install these on the host computer:

- Vagrant and VirtualBox, for Parts 1 and 2
- Docker, K3d, kubectl and the Argo CD CLI, for Part 3 and the bonus
- GNU Make (optional; every command can also be run directly)
- `curl` for the Part 2 host-side checks and the Part 3/bonus smoke tests
- `jq`, `git` and `openssl`, for the bonus's GitLab bootstrap script

`./install_dependencies.sh` installs all of the above on a Debian/Ubuntu host in one
pass (safe to re-run). `p3/scripts/install.sh` installs only the Part 3/bonus subset
and is what the `make install` targets below call.

Quick checks:

```bash
vagrant --version
VBoxManage --version
docker --version
k3d --version
kubectl version --client
argocd version --client
make --version
```

The VMs use the current stable LTS box `bento/ubuntu-26.04`. HashiCorp recommends Bento for modern community base boxes. Override it without editing the repository if your evaluation environment mandates another compatible box:

```bash
IOT_BOX=bento/ubuntu-24.04 make up
```

## Important: run one part at a time

Parts 1 and 2 both require a VM named `<login>S` at `192.168.56.110`. They are separate Vagrant environments and cannot coexist under the same VirtualBox VM name. Destroy Part 1 before launching Part 2.

Part 3 and the bonus do not use Vagrant at all — they run K3d (K3s in Docker) directly on the host, so they don't conflict with Parts 1/2 and can be left running alongside them. The bonus is layered on top of the same K3d cluster that Part 3 creates, so bring Part 3 up first.

## Part 1

Launch the two-node cluster:

```bash
cd p1
make up
make verify
```

Expected nodes:

```text
NAME      STATUS   ROLES                  INTERNAL-IP
tmoraglis    Ready    control-plane,master   192.168.56.110
tmoraglisw   Ready    <none>                 192.168.56.111
```

Useful commands:

```bash
make status
make ssh-server
make ssh-worker
make verify
```

Inside the server VM:

```bash
hostname
ip -brief address
kubectl get nodes -o wide
kubectl get pods -A
systemctl status k3s
```

Inside the worker VM:

```bash
hostname
ip -brief address
systemctl status k3s-agent
```

Passwordless SSH is provided by Vagrant's generated SSH key. `config.ssh.insert_key = true` replaces the well-known insecure box key with a machine-specific key on first boot.

When finished:

```bash
make destroy
```

Part 1 generates a random K3s join token in `p1/.vagrant/k3s-token`. That state is ignored by Git and reused when individual machines are provisioned separately.

## Part 2

After destroying Part 1, launch the single-node application cluster:

```bash
cd ../p2
make up
make resources
make verify
```

`make up` already performs three in-VM HTTP smoke tests. `make verify` repeats the checks from the host:

```bash
curl -H 'Host: app1.com' http://192.168.56.110/
curl -H 'Host: app2.com' http://192.168.56.110/
curl -H 'Host: unknown.example' http://192.168.56.110/
```

The results must be app 1, app 2, and app 3 respectively. App 3 is the Ingress `defaultBackend`, so it handles every host that is not `app1.com` or `app2.com`.

For browser testing, add these entries to the host computer's hosts file:

```text
192.168.56.110 app1.com
192.168.56.110 app2.com
```

Then open `http://app1.com`, `http://app2.com`, or `http://192.168.56.110`. The raw IP selects app 3 because its HTTP host does not match either named rule.

Commands to show during the defense:

```bash
vagrant ssh tmoragliS
kubectl get nodes -o wide
kubectl get deployments
kubectl get pods -o wide
kubectl get services
kubectl get ingress
kubectl describe ingress applications
kubectl get endpointslices
curl -H 'Host: app1.com' http://192.168.56.110/
curl -H 'Host: app2.com' http://192.168.56.110/
curl -H 'Host: anything' http://192.168.56.110/
```

The deployment table must show desired/current/ready replica counts of `1/1/1` for app 1, `3/3/3` for app 2, and `1/1/1` for app 3.

## Part 3

Part 3 swaps Vagrant/VirtualBox for K3d (K3s running as Docker containers) and adds
Argo CD on top for GitOps-style continuous deployment. It creates:

- a single-node K3d cluster named `maagosti-iot`, with its load balancer port `8888`
  mapped to the host,
- an `argocd` namespace running Argo CD,
- a `dev` namespace holding the `playground` Application, which Argo CD keeps
  synced from the `manifests` path of the public
  [TheKrainBow/maagosti-iot](https://github.com/TheKrainBow/maagosti-iot) GitHub
  repository.

Bring it up:

```bash
cd p3
make install   # docker, k3d, kubectl, argocd CLI (skips what's already present)
make up        # creates the cluster, installs Argo CD, applies the Application
make verify
```

`make verify` checks that the `playground` Application reports `Synced` and curls the
app through the K3d load balancer:

```bash
kubectl -n argocd get application playground
curl http://localhost:8888/
# {"status":"ok", "message": "v1"}
```

Other useful commands:

```bash
make status    # Argo CD applications + everything in the dev namespace
make destroy   # deletes the maagosti-iot K3d cluster
```

To change the deployed version, edit `manifests/deployment.yaml` in the GitHub repo
(e.g. swap the image tag from `wil42/playground:v1` to `:v2`), push, and Argo CD's
automated sync (`prune: true`, `selfHeal: true`) picks it up on its own — re-run
`make verify` a little later and the `message` field flips to `v2`.

## Bonus: local GitLab

The bonus adds a self-hosted GitLab instance inside the same K3d cluster from Part 3,
and a second, independent Argo CD Application that deploys from that GitLab instead
of GitHub. Part 3's own `playground` Application, `dev` namespace and GitHub source
are left untouched, so both are deployed and demoable at the same time. It creates:

- a `gitlab` namespace running `gitlab/gitlab-ce:latest` (trimmed down — registry,
  Pages, mail and KAS disabled, Puma/Sidekiq scaled down — so it fits a small lab
  instead of GitLab's usual 4+ vCPU host),
- a non-root GitLab account (`maagosti`) that owns a `playground` project seeded
  with its own `manifests/deployment.yaml` (not cloned from GitHub),
- a `gitlab-repo` Argo CD repository Secret pointing at that in-cluster GitLab,
- a `dev-gitlab` namespace holding the `playground-gitlab` Application, synced from
  that GitLab project instead of GitHub.

Bring it up (after Part 3 is already up):

```bash
cd ../bonus
make install   # sanity-checks that p3's tools/cluster are present
make up        # deploys GitLab, seeds the repo, wires up the Application
make verify
```

`make up` prints the GitLab root password, the generated `maagosti` account password,
and the `playground-gitlab` Application's sync status once it settles. First boot of
GitLab can take 5-15 minutes.

Other useful commands:

```bash
make status        # GitLab's pods/PVC + everything in dev-gitlab
make port-forward  # reach the bonus app at http://localhost:8890/
make gitlab-ui     # browse GitLab itself at http://localhost:8929/
make destroy       # removes only the bonus's namespaces/Application/secret
```

Because the app in `dev-gitlab` uses a `ClusterIP` Service (Part 3's own
`playground` already holds host port 8888 on this single-node cluster), reach it
with `make port-forward` rather than a direct curl:

```bash
make port-forward &
curl http://localhost:8890/
```

To change the deployed version, edit and push `manifests/deployment.yaml` inside the
GitLab-hosted `playground` project (e.g. via `git clone
http://maagosti:<token>@localhost:8929/maagosti/playground.git`); Argo CD's automated
sync picks it up the same way it does for Part 3.

## Repository layout

```text
.
├── Makefile
├── README.md
├── CRASH_COURSE.md
├── install_dependencies.sh
├── p1
│   ├── Makefile
│   ├── Vagrantfile
│   └── scripts
│       ├── install-agent.sh
│       └── install-server.sh
├── p2
│   ├── Makefile
│   ├── Vagrantfile
│   ├── confs
│   │   └── apps.yaml
│   └── scripts
│       ├── deploy-apps.sh
│       └── install-k3s.sh
├── p3
│   ├── Makefile
│   ├── confs
│   │   └── application.yaml
│   └── scripts
│       ├── bootstrap.sh
│       └── install.sh
└── bonus
	├── Makefile
	├── confs
	│   ├── application.yaml
	│   ├── deployment.yaml
	│   ├── gitlab.yaml
	│   └── namespace.yaml
	└── scripts
		├── bootstrap.sh
		└── install.sh
```

## Resource overrides

The defaults favor the subject's low-resource constraint:

- Part 1 server: 1 CPU, 1024 MB
- Part 1 agent: 1 CPU, 768 MB
- Part 2 server: 1 CPU, 1536 MB

Override them if the local machine has enough RAM and provisioning is slow:

```bash
IOT_SERVER_CPUS=2 IOT_SERVER_MEMORY=2048 make up
```

For Part 1, the agent has separate variables:

```bash
IOT_AGENT_CPUS=1 IOT_AGENT_MEMORY=1024 make up
```

## Reprovisioning and cleanup

Re-run provisioning after changing scripts or manifests:

```bash
vagrant provision
```

Apply only a changed Part 2 manifest from inside its VM:

```bash
kubectl apply -f /tmp/iot-apps.yaml
```

Vagrant uploads the repository files during provisioning; the project deliberately disables the default `/vagrant` shared folder to avoid Guest Additions version problems.

Stop without deleting:

```bash
make halt
```

Delete the VMs and disks:

```bash
make destroy
```

Part 3/bonus scripts are also safe to re-run: `install.sh` skips any tool that is
already present, and `bootstrap.sh` reuses the existing `maagosti-iot` K3d cluster
instead of recreating it. To force a resync without waiting for Argo CD's poll
interval:

```bash
argocd app sync playground          # or playground-gitlab for the bonus
```

## Troubleshooting shortcut

Debug from the outside inward:

1. `vagrant status`
2. `vagrant ssh <machine>`
3. `ip -brief address`
4. `systemctl status k3s` or `k3s-agent`
5. `kubectl get nodes`
6. `kubectl get pods -A`
7. `kubectl get service,endpointslice,ingress`
8. `curl -v -H 'Host: app1.com' http://192.168.56.110/`

For Part 3 and the bonus:

1. `k3d cluster list` / `docker ps` — is the cluster actually up?
2. `kubectl config current-context` — should be `k3d-maagosti-iot`
3. `kubectl -n argocd get pods` — Argo CD components healthy?
4. `kubectl -n argocd get application playground -o yaml` (or `playground-gitlab`)
   — check `status.sync` and `status.conditions` for the real error
5. `kubectl -n dev get pods` / `kubectl -n dev-gitlab get pods`
6. For the bonus, `kubectl -n gitlab get pods` and `kubectl -n gitlab logs deploy/gitlab`
   if GitLab itself never becomes ready

Detailed explanations and defense questions are in [CRASH_COURSE.md](CRASH_COURSE.md).

## Primary documentation

- [K3s quick start](https://docs.k3s.io/quick-start)
- [K3s configuration](https://docs.k3s.io/installation/configuration)
- [K3d documentation](https://k3d.io/)
- [Vagrant multi-machine environments](https://developer.hashicorp.com/vagrant/docs/multi-machine)
- [Kubernetes Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Kubernetes Services](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Kubernetes Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Argo CD documentation](https://argo-cd.readthedocs.io/)
- [GitLab Helm/Omnibus configuration](https://docs.gitlab.com/omnibus/settings/configuration.html)
