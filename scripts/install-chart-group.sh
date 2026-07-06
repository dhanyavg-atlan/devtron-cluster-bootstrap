#!/bin/sh
# Step 3 — install each chart in the group into ITS OWN namespace/environment.
# A chart group is not bound to one environment; each chart is a separate install.
# flux2 -> flux-system, external-secrets -> external-secrets (see lib/chart-namespaces.sh).
# Needs: curl + jq  (alpine + apk add --no-cache curl jq).
set -eu

: "${CLUSTER_NAME:?set CLUSTER_NAME}"
: "${DEVTRON_HOST:?set DEVTRON_HOST}"
: "${DEVTRON_API_TOKEN:?set DEVTRON_API_TOKEN (from a Devtron Secret)}"

command -v jq >/dev/null 2>&1 || apk add --no-cache curl jq >/dev/null
. /work/scripts/lib/chart-namespaces.sh

API="https://${DEVTRON_HOST}/orchestrator"; H="token: ${DEVTRON_API_TOKEN}"
CG_ID="${CHART_GROUP_ID:-2}"; TEAM_ID="${TEAM_ID:-7}"

CID="$(curl -sS -H "$H" "$API/cluster" | jq -r --arg n "$CLUSTER_NAME" '.result[] | select(.cluster_name==$n) | .id')"
[ -n "$CID" ] && [ "$CID" != "null" ] || { echo "cluster $CLUSTER_NAME not registered yet"; exit 1; }

tmp="$(mktemp)"
curl -sS -H "$H" "$API/chart-group/$CG_ID" | jq -c '.result.chartGroupEntries[]' > "$tmp"

while read -r entry; do
  [ -n "$entry" ] || continue
  avid="$(echo "$entry" | jq -r '.appStoreApplicationVersionId')"
  cname="$(echo "$entry" | jq -r '.chartMetaData.chartName')"
  ns="$(chart_namespace "$cname")"
  envname="${CLUSTER_NAME}-${ns}"

  eid="$(curl -sS -H "$H" "$API/env" | jq -r --arg e "$envname" '.result[] | select(.environment_name==$e) | .id')"
  [ -n "$eid" ] && [ "$eid" != "null" ] || { echo "env $envname missing (run create-environment first)"; exit 1; }

  vals=""; [ "$cname" = "external-secrets" ] && vals="${ESO_VALUES_YAML:-}"   # e.g. WIF SA annotation
  body="$(jq -n --argjson av "$avid" --argjson eid "$eid" --argjson cid "$CID" --argjson tid "$TEAM_ID" \
    --arg ns "$ns" --arg app "${CLUSTER_NAME}-${cname}" --arg v "$vals" \
    '{appStoreVersion:$av, environmentId:$eid, clusterId:$cid, teamId:$tid, namespace:$ns,
      appName:$app, valuesOverrideYaml:$v, referenceValueId:$av, referenceValueKind:"DEFAULT"}')"
  resp="$(curl -sS -w '\n%{http_code}' -X POST "$API/app-store/deployment/application/install" \
    -H "$H" -H "Content-Type: application/json" -d "$body")"
  echo "install $cname -> ns=$ns env=$envname HTTP $(echo "$resp" | tail -n1)"
done < "$tmp"
rm -f "$tmp"
echo "chart-group install dispatched (per-chart namespaces)"
