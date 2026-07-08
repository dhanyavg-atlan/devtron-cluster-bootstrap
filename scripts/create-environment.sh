#!/bin/sh
# Step 2 — create one Devtron environment per chart, each pinned to that chart's
# namespace. Env name = <cluster>-<alias> (<=16 chars, Devtron's limit); the env's
# namespace is the chart's full namespace (see lib/chart-namespaces.sh).
# Needs: curl + jq  (alpine + apk add --no-cache curl jq).
set -eu

: "${CLUSTER_NAME:?set CLUSTER_NAME}"
: "${DEVTRON_HOST:?set DEVTRON_HOST}"
: "${DEVTRON_API_TOKEN:?set DEVTRON_API_TOKEN (from a Devtron Secret)}"

command -v jq >/dev/null 2>&1 || apk add --no-cache curl jq >/dev/null
. /work/scripts/lib/chart-namespaces.sh

API="https://${DEVTRON_HOST}/orchestrator"; H="token: ${DEVTRON_API_TOKEN}"
CG_ID="${CHART_GROUP_ID:-2}"

CID="$(curl -sS -H "$H" "$API/cluster" | jq -r --arg n "$CLUSTER_NAME" '.result[] | select(.cluster_name==$n) | .id')"
[ -n "$CID" ] && [ "$CID" != "null" ] || { echo "cluster $CLUSTER_NAME not registered yet"; exit 1; }

tmp="$(mktemp)"
curl -sS -H "$H" "$API/chart-group/$CG_ID" | jq -r '.result.chartGroupEntries[].chartMetaData.chartName' > "$tmp"

while read -r chart; do
  [ -n "$chart" ] || continue
  ns="$(chart_namespace "$chart")"
  envname="${CLUSTER_NAME}-$(chart_env_alias "$chart")"
  body="$(jq -n --arg e "$envname" --argjson c "$CID" --arg ns "$ns" \
    '{environment_name:$e, cluster_id:$c, namespace:$ns, active:true, default:false}')"
  resp="$(curl -sS -w '\n%{http_code}' -X POST "$API/env" -H "$H" -H "Content-Type: application/json" -d "$body")"
  code="$(echo "$resp" | tail -n1)"
  case "$code" in
    2*) echo "env $envname ready (ns=$ns, cluster=$CID)" ;;
    *)  echo "$resp" | grep -qi "already exist" \
          && echo "env $envname exists, continuing" \
          || { echo "$resp" | sed '$d'; echo "env $envname FAILED (HTTP $code)"; exit 1; } ;;
  esac
done < "$tmp"
rm -f "$tmp"
