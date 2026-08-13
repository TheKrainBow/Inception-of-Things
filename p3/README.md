# Part 3 — K3d + Argo CD

A K3d (K3s-in-Docker) cluster with Argo CD continuously deploying the
`playground` app from the public
[TheKrainBow/maagosti-iot](https://github.com/TheKrainBow/maagosti-iot) GitHub
repository into a `dev` namespace.

Full repository context: [../README.md](../README.md).

## 1. Start the stack

```bash
cd p3
make install   # docker, k3d, kubectl, argocd CLI (skips what's already present)
make up        # creates the k3d cluster, installs Argo CD, applies the Application
```

`make up` prints the Argo CD admin password at the end, e.g.:

```text
==> Argo CD admin password: <password>
==> Port-forward the UI with: kubectl -n argocd port-forward svc/argocd-server 8080:443
```

Copy that password down (or re-fetch it any time, see step 3).

## 2. Test that everything is working, step by step

**a. Cluster is up and using the right context**

```bash
k3d cluster list
kubectl config current-context
# k3d-maagosti-iot
```

**b. Argo CD components are healthy**

```bash
kubectl -n argocd get pods
```

All pods should be `Running`/`Completed` with no restarts climbing.

**c. The `playground` Application is synced and healthy**

```bash
kubectl -n argocd get application playground
```

`SYNC STATUS` must read `Synced` and `HEALTH STATUS` must read `Healthy`.

**d. The app pod is actually up in the `dev` namespace**

```bash
kubectl -n dev get pods
```

**e. The app answers through the K3d load balancer**

```bash
curl http://localhost:8888/
# {"status":"ok", "message": "v1"}
```

Or run everything in c/e together:

```bash
make verify
```

**f. Open the Argo CD dashboard**

Argo CD isn't exposed on the host by default — port-forward it first:

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

Then open:

```
https://localhost:8080
```

(Browsers will warn about the self-signed certificate — accept it to continue.)
Log in with username `admin` and the password printed by `make up`. If you lost it:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

In the UI, the `playground` Application tile should show `Synced` / `Healthy`,
and clicking into it shows the `Deployment`, `Service` and `Pod` it manages in
the `dev` namespace.

You can also drive the same checks from the Argo CD CLI once port-forwarded:

```bash
argocd login localhost:8080 --username admin --password '<password>' --insecure
argocd app get playground
```

## 3. Other useful commands

```bash
make status    # Argo CD applications + everything in the dev namespace
make destroy   # deletes the maagosti-iot k3d cluster
```

To change the deployed version, edit `manifests/deployment.yaml` in the GitHub
repo (e.g. swap the image tag from `wil42/playground:v1` to `:v2`), push, and
Argo CD's automated sync (`prune: true`, `selfHeal: true`) picks it up on its
own — re-run `make verify` a little later and the `message` field flips to
`v2`.
