#!/bin/sh
# Generate the DHIS2 analytics tables after a fresh dump load.
#
# A freshly restored dump has raw data values but NO populated analytics_* tables,
# so anything that reads analytics (the Data Visualizer, the Climate app, and the
# CHAP Modelling App) sees nothing until this job runs. This one-shot kicks off the
# analytics export and polls the task to completion, then exits.
#
# Adapted from ~/dev/dhis2-docker (compose.yml `analytics-trigger`).
set -eu

: "${DHIS2_BASE_URL:?}"
: "${DHIS2_ADMIN_USER:?}"
: "${DHIS2_ADMIN_PASSWORD:?}"

apk add --no-cache curl >/dev/null

AUTH="${DHIS2_ADMIN_USER}:${DHIS2_ADMIN_PASSWORD}"
API="${DHIS2_BASE_URL%/}/api"

# web's healthcheck only proves the login page is up; give the API a moment more.
echo "Waiting for DHIS2 API at ${API} ..."
i=0
until [ "$(curl -s -o /dev/null -w '%{http_code}' -u "$AUTH" "${API}/system/info.json")" = "200" ]; do
  i=$((i + 1))
  [ "$i" -ge 300 ] && { echo "DHIS2 API not ready in time" >&2; exit 1; }
  sleep 2
done

echo "Triggering analytics table generation ..."
RESPONSE=$(curl -s -u "$AUTH" -X POST "${API}/resourceTables/analytics")
echo "$RESPONSE"
TASK_ID=$(echo "$RESPONSE" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -1)
if [ -z "$TASK_ID" ]; then
  echo "Failed to parse analytics task id from response!" >&2
  exit 1
fi

echo "Polling analytics task ${TASK_ID} ..."
while true; do
  sleep 10
  STATUS=$(curl -s -u "$AUTH" "${API}/system/tasks/ANALYTICS_TABLE/${TASK_ID}")
  if echo "$STATUS" | grep -q '"completed":true'; then
    break
  fi
  if echo "$STATUS" | grep -q '"level":"ERROR"'; then
    echo "Analytics failed!" >&2
    echo "$STATUS" >&2
    exit 1
  fi
  echo "Still running ..."
done
echo "Analytics tables completed successfully."
