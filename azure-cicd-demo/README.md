# Azure CI/CD Demo — Python + AKS + ACR + GitHub Actions + Argo CD

A working reference implementation of:

```
GitHub (push/tag) → GitHub Actions CI → ACR (build + Trivy scan)
                                            │
                       ┌────────────────────┴────────────────────┐
                       ▼                                         ▼
            CD: direct Helm deploy                    CD: GitOps promotion
            to STAGING (on every merge to main)        to PRODUCTION (on git tag v*)
            CI holds short-lived AKS creds             CI only edits a YAML file in Git —
            via OIDC, runs `helm upgrade`               it never touches the cluster
                                                          │
                                                          ▼
                                                Argo CD (running inside AKS)
                                                watches the repo, applies the
                                                change itself, self-heals drift
```

Staging uses **direct deploy** so you get fast feedback on every merge.
Production uses **GitOps** so no CI system ever holds production cluster
credentials — the cluster pulls its own changes.

## Repo layout

```
app/                      FastAPI sample service + Dockerfile + tests
terraform/                Azure infra: resource group, AKS, ACR, Key Vault
helm/myapp/               One chart, reused for staging and production
.github/workflows/
  ci.yml                  lint → test → build → scan → push to ACR
  cd-staging.yml           helm upgrade --install, direct, OIDC creds
  cd-production-gitops.yml only commits a values file — no cluster access
gitops/
  production/values-production.yaml   the file Argo CD watches
  argocd-application-production.yaml  the Application CRD, applied once
scripts/
  setup-oidc.sh           one-time: GitHub <-> Azure trust, no secrets
  bootstrap-argocd.sh     one-time: installs Argo CD + CSI driver on AKS
```

## Setup order (do these once, in order)

### 1. Provision Azure infra
```bash
cd terraform
terraform init
terraform apply
```
Note the outputs — you'll need `acr_login_server`, `aks_cluster_name`,
`resource_group_name`, and `workload_identity_client_id` for the next steps.

### 2. Wire GitHub → Azure trust (OIDC, no secrets)
```bash
cd scripts
./setup-oidc.sh <acr_name_from_terraform_output> <resource_group_name>
```
This prints values to add as **GitHub Actions variables** (not secrets —
that's intentional, none of them are sensitive on their own):
`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `ACR_NAME`,
`AKS_RESOURCE_GROUP`, `AKS_CLUSTER_NAME`, `WORKLOAD_IDENTITY_CLIENT_ID`,
`ACR_LOGIN_SERVER`.

Add them under **Repo Settings → Secrets and variables → Actions → Variables**.

### 3. Install Argo CD on the cluster
```bash
az aks get-credentials --resource-group <rg> --name <aks_cluster_name>
cd scripts
./bootstrap-argocd.sh
```
This also applies `gitops/argocd-application-production.yaml`, so Argo CD
immediately starts watching `gitops/production/values-production.yaml`.

### 4. Set the production GitOps file's real values once
Edit `gitops/production/values-production.yaml` and fill in `image.repository`
and `workloadIdentity.clientId` with your real ACR/Terraform values, commit,
push. From here on, CI only ever touches the `tag` line.

### 5. Set up GitHub Actions Environments
In repo settings, create `staging` and `production` environments.
On `production`, add a **required reviewer** — this is your manual approval
gate before anything reaches prod.

## How a change actually flows through this, end to end

1. Open a PR → `ci.yml` runs lint + tests (no image push yet — PRs don't get pushed images).
2. Merge to `main` → `ci.yml` builds the image, scans it with Trivy (fails the
   build on critical/high CVEs), pushes to ACR tagged with the short git SHA.
3. `cd-staging.yml` fires automatically right after → `helm upgrade --install`
   into the `staging` namespace using that exact image tag → smoke test hits `/healthz`.
4. When you're confident, cut a release: `git tag v1.2.0 && git push --tags`.
5. `cd-production-gitops.yml` runs — it does **not** deploy anything. It just
   edits `gitops/production/values-production.yaml` to point at the new image
   tag and commits that change. The `production` environment's required
   reviewer has to approve this job before it runs.
6. Argo CD (already running inside AKS, no external access needed) notices
   the Git change on its next sync, diffs it against the live cluster state,
   and applies it. `selfHeal: true` means if anyone manually `kubectl edit`s
   something in `production` later, Argo CD reverts it back to match Git.

## Why it's built this way

- **OIDC instead of stored Azure credentials** — GitHub presents a signed,
  short-lived token at workflow runtime; Azure trusts it based on the
  federated credential's `subject` (e.g. "this exact repo, this exact
  branch"). There's no `AZURE_CLIENT_SECRET` sitting in GitHub Secrets that
  could leak or need rotation.
- **One Helm chart, environment-specific values files** — staging and
  production are never different code paths, only different config. This is
  the "build once, promote everywhere" principle from earlier in our
  conversation, made concrete.
- **GitOps for production specifically** — limits the blast radius of a
  compromised CI pipeline to staging only. Nothing outside the cluster ever
  holds production kubeconfig.
- **Workload Identity for pod → Key Vault access** — pods authenticate to
  Azure using a federated Kubernetes service account token, not a mounted
  secret file.
- **Trivy gate in CI** — an artifact with a known critical CVE never reaches
  ACR's pushed state, mirroring how JFrog Xray gates work in Artifactory-based
  pipelines.

## Tightening this further for real production use

- Split `gitops/production` into a **separate repository** with its own
  access controls — the version here keeps it in the same repo for
  simplicity, but separating app source from deploy state is the more
  rigorous pattern.
- Scope the GitHub OIDC service principal's AKS role down to a
  **Kubernetes RoleBinding limited to the `staging` namespace**, rather than
  relying solely on the Azure-level role assignment.
- Add `terraform` remote state (an Azure Storage Account backend — see the
  commented block in `providers.tf`) so infra changes go through PR review too.
- Add branch protection requiring the `lint-test` job to pass before merge.
