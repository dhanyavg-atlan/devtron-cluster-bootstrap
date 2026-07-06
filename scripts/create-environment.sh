#!/bin/sh
# Step 2 — create the Devtron environment (cluster + namespace) for the registered cluster.
# Needs: curl + jq  (alpine + apk add --no-cache curl jq).
set -eu

: "${CLUSTER_NAME:?set CLUSTER_NAME}"
: "${DEVTRON_HOST:?set DEVTRON_HOST}"
: "${DEVTRON_API_TOKEN:?set DEVTRON_API_TOKEN (from a Devtron Secret)}"

command -v jq >/dev/null 2>&1 || apk add --no-cache curl jq >/dev/null

API="https://${DEVTRON_HOST}/orchestrator"; H="token: ${DEVTRON_API_TOKEN}"
NS="${TARGET_NAMESPACE:-control}"
ENVNAME="${CLUSTER_NAME}-${NS}"

CID="$(curl -sS -H "$H" "$API/cluster" | jq -r --arg n "$CLUSTER_NAME" '.result[] | select(.cluster_name==$n) | .id')"
[ -n "$CID" ] && [ "$CID" != "null" ] || { echo "cluster $CLUSTER_NAME not registered yet"; exit 1; }

echo ">> creating environment ${ENVNAME} on cluster ${CLUSTER_NAME} (id ${CID})"
BODY="$(jq -n --arg e "$ENVNAME" --argjson c "$CID" --arg ns "$NS" \
  '{environment_name:$e, cluster_id:$c, namespace:$ns, active:true, default:false}')"
RESP="$(curl -sS -w '\n%{http_code}' -X POST "$API/env" \
  -H "$H" -H "Content-Type: application/json" -d "$BODY")"
CODE="$(echo "$RESP" | tail -n1)"
echo "$RESP" | sed '$d'
case "$CODE" in
  2*) echo "environment $ENVNAME ready (cluster $CID)" ;;
  *)  echo "$RESP" | grep -qi "already exist" \
        && echo "environment exists, continuing" \
        || { echo "env create FAILED (HTTP $CODE)"; exit 1; } ;;
esac
