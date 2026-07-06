# devtron-cluster-bootstrap

Bootstrap scripts for the Devtron **`cluster-bootstrap`** Job (generic — works for any cluster).

Devtron mounts this repo at `/work` in each job step (`mountCodeToContainer: true`). Each
Devtron step is a **thin launcher** — the real logic lives here, so it is version-controlled,
reviewable, and every job run is traceable to a commit hash.

```
Devtron step 1  ->  sh /work/scripts/register-cluster.sh
Devtron step 2  ->  sh /work/scripts/create-environment.sh
Devtron step 3  ->  sh /work/scripts/install-chart-group.sh
```

> The cluster itself is **not** created here — that is the OpenTofu / bootstrap flow's job.
> These scripts assume the (private) cluster already exists and only wire it into Devtron and
> install the bootstrap platform charts.

## Flow

| # | Script | Does | API |
|---|--------|------|-----|
| 1 | `register-cluster.sh` | reach the private cluster via Connect Gateway, mint a `cd-user` SA + token, read the private endpoint + CA, register into Devtron | `POST /orchestrator/cluster` |
| 2 | `create-environment.sh` | create the Devtron environment (cluster + namespace) | `POST /orchestrator/env` |
| 3 | `install-chart-group.sh` | deploy the `onboarding-group` chart group (flux2 + external-secrets) into the environment | `GET /orchestrator/chart-group/{id}` + `POST /orchestrator/app-store/deployment/application/install` |

## Inputs (env vars — set as Devtron task input vars / **Secrets**, never hardcode)

| Var | Used by | Notes |
|-----|---------|-------|
| `CLUSTER_NAME` | all | target cluster / fleet-membership name (also the Devtron `cluster_name`) |
| `CLUSTER_LOCATION` | 1 | e.g. `us-central1` |
| `GCP_PROJECT` | 1 | project holding the cluster |
| `DEVTRON_HOST` | all | e.g. `devtron-public.atlan.engineering` |
| `DEVTRON_API_TOKEN` | all | **from a Devtron Secret** — the only long-lived secret |
| `TARGET_NAMESPACE` | 2,3 | default `control` |
| `CHART_GROUP_ID` | 3 | default `2` (`onboarding-group`) |
| `TEAM_ID` | 3 | default `7` (`infra`) |
| `ESO_VALUES_YAML` | 3 | optional values override for external-secrets (e.g. WIF SA annotation) |

## Container images (per step)

- **step 1** (`register-cluster`) needs `gcloud` + `kubectl` + `jq` + `curl` → use a
  `google/cloud-sdk` image (kubectl via `gcloud components install kubectl` or `apk add kubectl`).
- **steps 2 & 3** need only `curl` + `jq` → `alpine` + `apk add --no-cache curl jq`.

## Auth

- **GCP:** the job runs as Workload Identity `devtron-ci/ci-runner` → GSA (keyless, no SA key).
  The GSA needs Connect-Gateway + `container.clusters.get` on the target project.
- **Devtron:** `DEVTRON_API_TOKEN` from a Devtron Secret. Auth header is `token:` (not Bearer).
</content>
