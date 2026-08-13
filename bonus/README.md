# Bonus — Local GitLab + Argo CD

A self-hosted GitLab instance running inside the same K3d cluster created by
[Part 3](../p3/README.md), plus a second, independent Argo CD Application
(`playground-gitlab`) that deploys the `playground` app from that in-cluster
GitLab instead of GitHub. Part 3's own `playground` Application, `dev`
namespace and GitHub source are left untouched, so both are deployed and
demoable at the same time.

Full repository context: [../README.md](../README.md).

## 1. Start the stack

Part 3 must already be up (its cluster and Argo CD install are reused):

```bash
cd p3 && make install && make up
cd ../bonus
make install   # sanity-checks that p3's tools/cluster are present
make up        # deploys GitLab, seeds the repo, wires up the Application
```

First boot of GitLab can take **5-15 minutes**. `make up` prints, at the end:

```text
==> GitLab root password: <password>
==> GitLab account: maagosti / <password>
==> Browse GitLab with: kubectl -n gitlab port-forward svc/gitlab 8929:80
```

Copy those down.

## 2. Test that everything is working, step by step

**a. GitLab pod and storage are healthy**

```bash
kubectl -n gitlab get pods,pvc
```

The `gitlab` pod should be `Running` and its PVC `Bound`.

**b. The Argo CD repository Secret was created**

```bash
kubectl -n argocd get secret gitlab-repo
```

**c. The `playground-gitlab` Application is synced and healthy**

```bash
kubectl -n argocd get application playground-gitlab
```

`SYNC STATUS` must read `Synced` and `HEALTH STATUS` must read `Healthy`.

**d. The app pod is up in the `dev-gitlab` namespace**

```bash
kubectl -n dev-gitlab get pods
```

Or run c/d together:

```bash
make verify
```

**e. The app answers on its own port**

Its Service is `ClusterIP` (Part 3's own `playground` already holds host port
8888 on this single-node cluster), so reach it through a port-forward:

```bash
make port-forward &
curl http://localhost:8890/
# {"status":"ok", "message": "v1"}
```

**f. Browse GitLab itself**

```bash
make gitlab-ui
```

Then open `http://localhost:8929/` and log in either as:

- `root` / the GitLab root password printed by `make up`, or
- `maagosti` / the account password printed by `make up`.

Under `maagosti`'s namespace you should find the `playground` project,
containing `manifests/deployment.yaml` — the file Argo CD is syncing from.

**g. Open the Argo CD dashboard**

Argo CD isn't exposed on the host by default — port-forward it first (same
Argo CD instance as Part 3, reused by the bonus):

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

Then open:

```
https://localhost:8080
```

(Browsers will warn about the self-signed certificate — accept it to
continue.) Log in with username `admin` and Part 3's admin password. If you
lost it:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

In the UI you should now see **two** Application tiles: `playground`
(GitHub-backed, from Part 3) and `playground-gitlab` (GitLab-backed, from the
bonus), both `Synced` / `Healthy`. Clicking into `playground-gitlab` shows the
`Deployment`, `Service` and `Pod` it manages in the `dev-gitlab` namespace.

## 3. Other useful commands

```bash
make status        # GitLab's pods/PVC + everything in dev-gitlab
make port-forward   # reach the bonus app at http://localhost:8890/
make gitlab-ui      # browse GitLab itself at http://localhost:8929/
make destroy         # removes only the bonus's namespaces/Application/secret
```

To change the deployed version, edit and push `manifests/deployment.yaml`
inside the GitLab-hosted `playground` project (e.g. via
`git clone http://maagosti:<token>@localhost:8929/maagosti/playground.git`);
Argo CD's automated sync picks it up the same way it does for Part 3.
