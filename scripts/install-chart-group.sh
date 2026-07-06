#!/bin/sh
# Step 3 — install the onboarding chart group (flux2 + external-secrets) into the environment.
# Iterates the chart group's entries and installs each via the app-store install API.
# Needs: curl + jq  (alpine + apk add --no-cache curl jq).
set -eu

: "${CLUSTER_NAME:?set CLUSTER_NAME}"
: "${DEVTRON_HOST:?set DEVTRON_HOST}"
: "${DEVTRON_API_TOKEN:?set DEVTRON_API_TOKEN (from a Devtron Secret)}"

command -v jq >/dev/null 2>&1 || apk add --no-cache curl jq >/dev/null

API="https://${DEVTRON_HOST}/orchestrator"; H="token: ${DEVTRON_API_TOKEN}"
CG_ID="${CHART_GROUP_ID:-2}"          # onboarding-group
NS="${TARGET_NAMESPACE:-control}"
ENVNAME="${CLUSTER_NAME}-${NS}"
TEAM_ID="${TEAM_ID:-7}"               # infra

CID="$(curl -sS -H "$H" "$API/cluster" | jq -r --arg n "$CLUSTER_NAME" '.result[] | select(.cluster_name==$n) | .id')"
EID="$(curl -sS -H "$H" "$API/env"     | jq -r --arg e "$ENVNAME"     '.result[] | select(.environment_name==$e) | .id')"
[ -n "$EID" ] && [ "$EID" != "null" ] || { echo "environment $ENVNAME missing (run step 2 first)"; exit 1; }

echo ">> installing chart-group ${CG_ID} into ${ENVNAME} (cluster ${CID}, env ${EID})"
curl -sS -H "$H" "$API/chart-group/$CG_ID" | jq -c '.result.chartGroupEntries[]' | while read -r entry; do
  AVID="$(echo "$entry" | jq -r '.appStoreApplicationVersionId')"
  CNAME="$(echo "$entry" | jq -r '.chartMetaData.chartName')"
  VALS=""
  [ "$CNAME" = "external-secrets" ] && VALS="${ESO_VALUES_YAML:-}"   # e.g. WIF SA annotation
  BODY="$(jq -n --argjson av "$AVID" --argjson eid "$EID" --argjson cid "$CID" \
    --argjson tid "$TEAM_ID" --arg ns "$NS" --arg app "${CLUSTER_NAME}-${CNAME}" --arg v "$VALS" \
    '{appStoreVersion:$av, environmentId:$eid, clusterId:$cid, teamId:$tid, namespace:$ns,
      appName:$app, valuesOverrideYaml:$v, referenceValueId:$av, referenceValueKind:"DEFAULT"}')"
  RESP="$(curl -sS -w '\n%{http_code}' -X POST "$API/app-store/deployment/application/install" \
    -H "$H" -H "Content-Type: application/json" -d "$BODY")"
  echo "install ${CNAME} (version-id ${AVID}) -> HTTP $(echo "$RESP" | tail -n1)"
done
echo "chart-group install dispatched"
