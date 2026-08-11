# Inception-of-Things: Parts 1 and 2

This repository implements the first two mandatory parts of the IoT subject:

- `p1`: two Vagrant machines, one K3s server and one K3s agent.
- `p2`: one Vagrant machine, three web applications, three replicas for app 2, and host-based routing through Traefik Ingress.

The default login is `tmoragli`, so the required VM hostnames are `tmoragliS` and `tmoragliSW`. Kubernetes object names must be lowercase DNS names, so the corresponding node names shown by `kubectl` are `tmoraglis` and `tmoraglisw`.

```bash
make LOGIN=yourlogin up
```

## Prerequisites

Install these on the host computer:

- Vagrant
- VirtualBox
- GNU Make (optional; every command can also be run directly)
- `curl` for the Part 2 host-side checks

Quick checks:

```bash
vagrant --version
VBoxManage --version
make --version
```

The VMs use the current stable LTS box `bento/ubuntu-26.04`. HashiCorp recommends Bento for modern community base boxes. Override it without editing the repository if your evaluation environment mandates another compatible box:

```bash
IOT_BOX=bento/ubuntu-24.04 make up
```

## Important: run one part at a time

Parts 1 and 2 both require a VM named `<login>S` at `192.168.56.110`. They are separate Vagrant environments and cannot coexist under the same VirtualBox VM name. Destroy Part 1 before launching Part 2.

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

## Repository layout

```text
.
├── Makefile
├── README.md
├── CRASH_COURSE.md
├── p1
│   ├── Makefile
│   ├── Vagrantfile
│   └── scripts
│       ├── install-agent.sh
│       └── install-server.sh
└── p2
	├── Makefile
	├── Vagrantfile
	├── confs
	│   └── apps.yaml
	└── scripts
		├── deploy-apps.sh
		└── install-k3s.sh
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

Detailed explanations and defense questions are in [CRASH_COURSE.md](CRASH_COURSE.md).

## Primary documentation

- [K3s quick start](https://docs.k3s.io/quick-start)
- [K3s configuration](https://docs.k3s.io/installation/configuration)
- [Vagrant multi-machine environments](https://developer.hashicorp.com/vagrant/docs/multi-machine)
- [Kubernetes Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Kubernetes Services](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Kubernetes Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
