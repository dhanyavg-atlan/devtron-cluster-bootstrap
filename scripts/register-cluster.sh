#!/bin/sh
# Step 1 — register the (already-existing, private) cluster into Devtron.
#
# Reaches the private cluster over Connect Gateway using the job's WIF identity,
# mints a cd-user ServiceAccount + token, reads the private endpoint + CA, then
# POSTs to Devtron. The cluster is NOT created here (that is the OpenTofu flow).
#
# Needs: gcloud + kubectl + jq + curl  (use a google/cloud-sdk image for this step).
set -eu

: "${CLUSTER_NAME:?set CLUSTER_NAME (fleet membership / cluster name)}"
: "${CLUSTER_LOCATION:?set CLUSTER_LOCATION, e.g. us-central1}"
: "${GCP_PROJECT:?set GCP_PROJECT (project holding the cluster)}"
: "${DEVTRON_HOST:?set DEVTRON_HOST}"
: "${DEVTRON_API_TOKEN:?set DEVTRON_API_TOKEN (from a Devtron Secret)}"

API="https://${DEVTRON_HOST}/orchestrator"
# Isolate kubeconfig — never touch a shared/current-context kubeconfig.
KUBECONFIG="$(mktemp)"; export KUBECONFIG

# Ensure kubectl + GKE auth plugin + jq. cloud-sdk:slim DISABLES `gcloud components`,
# so install via apt (the Google Cloud SDK apt repo is preconfigured in the image).
if ! command -v kubectl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  apt-get update -qq >/dev/null 2>&1
  apt-get install -y -qq kubectl google-cloud-cli-gke-gcloud-auth-plugin jq >/dev/null 2>&1
fi

echo ">> reaching ${CLUSTER_NAME} via Connect Gateway"
gcloud container fleet memberships get-credentials "$CLUSTER_NAME" \
  --location "$CLUSTER_LOCATION" --project "$GCP_PROJECT"

echo ">> minting cd-user ServiceAccount (idempotent)"
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cd-user
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cd-user-crb
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: cd-user
  namespace: kube-system
---
apiVersion: v1
kind: Secret
metadata:
  name: cd-user-token
  namespace: kube-system
  annotations:
    kubernetes.io/service-account.name: cd-user
type: kubernetes.io/service-account-token
EOF

echo ">> waiting for token to populate"
TOKEN=""; i=0
while [ -z "$TOKEN" ] && [ "$i" -lt 30 ]; do
  TOKEN="$(kubectl -n kube-system get secret cd-user-token -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || true)"
  [ -z "$TOKEN" ] && { sleep 2; i=$((i + 1)); }
done
[ -n "$TOKEN" ] || { echo "cd-user token did not populate"; exit 1; }

echo ">> reading private endpoint + CA"
DESC() { gcloud container clusters describe "$CLUSTER_NAME" \
  --location "$CLUSTER_LOCATION" --project "$GCP_PROJECT" --format="value($1)"; }
EP="$(DESC 'privateClusterConfig.privateEndpoint')"
CA_PEM="$(DESC 'masterAuth.clusterCaCertificate' | base64 -d)"   # GKE gives base64(PEM); Devtron wants PEM
[ -n "$EP" ] || { echo "no private endpoint on $CLUSTER_NAME"; exit 1; }
SERVER="https://${EP}"

echo ">> registering ${CLUSTER_NAME} (${SERVER}) into Devtron"
BODY="$(jq -n --arg n "$CLUSTER_NAME" --arg url "$SERVER" --arg tok "$TOKEN" --arg ca "$CA_PEM" \
  '{cluster_name:$n, server_url:$url, config:{bearer_token:$tok, cert_auth_data:$ca}}')"
RESP="$(curl -sS -w '\n%{http_code}' -X POST "$API/cluster" \
  -H "token: $DEVTRON_API_TOKEN" -H "Content-Type: application/json" -d "$BODY")"
CODE="$(echo "$RESP" | tail -n1)"
echo "$RESP" | sed '$d'
case "$CODE" in
  2*) echo "registered $CLUSTER_NAME into Devtron" ;;
  *)  echo "$RESP" | grep -qi "already exist" \
        && echo "cluster already registered, continuing" \
        || { echo "register FAILED (HTTP $CODE)"; exit 1; } ;;
esac
