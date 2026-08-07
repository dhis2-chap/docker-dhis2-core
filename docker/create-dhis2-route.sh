#!/bin/sh
# Register a DHIS2 Route that reverse-proxies DHIS2 -> an internal service.
#
# The workflow is generic so the same one-shot can register a route for chap-core,
# OCS, or any other local service. It waits for the DHIS2 API to come up, then
# ensures a wildcard route with the requested code points at the requested URL.
#
# It is idempotent AND self-correcting: if a route with the same code already
# exists and points somewhere else, we repoint it to the requested target.
#
# Notes:
#   - The target URL MUST end in /** (a DHIS2 "wildcard route").
#   - Services like chap-core or OCS have no auth, so the route has no auth block.
#   - dhis.conf sets `route.remote_servers_allowed = http://*`, which is what lets
#     DHIS2 v42 accept an http:// (non-https) route target.
set -eu

: "${DHIS2_BASE_URL:?}"
: "${DHIS2_ADMIN_USER:?}"
: "${DHIS2_ADMIN_PASSWORD:?}"

ROUTE_CODE="${ROUTE_CODE:-${DHIS2_ROUTE_CODE:-chap}}"
ROUTE_NAME="${ROUTE_NAME:-${DHIS2_ROUTE_NAME:-${ROUTE_CODE}}}"
ROUTE_URL="${ROUTE_URL:-${DHIS2_ROUTE_URL:-${CHAP_ROUTE_URL:-}}}"
ROUTE_UID="${ROUTE_UID:-${DHIS2_ROUTE_UID:-${CHAP_ROUTE_UID:-}}}"

[ -n "$ROUTE_URL" ] || { echo "ROUTE_URL (or DHIS2_ROUTE_URL/CHAP_ROUTE_URL) is required" >&2; exit 1; }

# Stable, predetermined UID for a route when requested, so a fresh install always
# gets the same id instead of a random server-assigned one. Generated with the
# DHIS2 CLI: dhis2 dev uid. Only applies when creating a route; if the demo dump
# already shipped a route we reuse its existing id.
: "${ROUTE_UID:=${DHIS2_ROUTE_UID:-${CHAP_ROUTE_UID:-}}}"
if [ -z "$ROUTE_UID" ]; then
  ROUTE_UID="TkdmmuSCGPA"
fi

apk add --no-cache curl >/dev/null

AUTH="${DHIS2_ADMIN_USER}:${DHIS2_ADMIN_PASSWORD}"
API="${DHIS2_BASE_URL%/}/api"

# Wait for the DHIS2 API to be reachable and authenticating. DHIS2 boot can take
# several minutes on first start (it builds analytics, runs flyway, etc.).
echo "Waiting for DHIS2 API at ${API} ..."
i=0
until [ "$(curl -s -o /dev/null -w '%{http_code}' -u "$AUTH" "${API}/system/info.json")" = "200" ]; do
  i=$((i + 1))
  if [ "$i" -ge 600 ]; then
    echo "DHIS2 API did not become ready in time" >&2
    exit 1
  fi
  sleep 2
done
echo "DHIS2 API is up."

# Is there already a route with the requested code? Grab its id and current url.
EXISTING=$(curl -s -u "$AUTH" "${API}/routes.json?filter=code:eq:${ROUTE_CODE}&fields=id,url")
ROUTE_ID=$(echo "$EXISTING" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -1)
ROUTE_URL_CURRENT=$(echo "$EXISTING" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p' | head -1)

if [ -n "$ROUTE_ID" ]; then
  if [ "$ROUTE_URL_CURRENT" = "$ROUTE_URL" ]; then
    echo "Route '${ROUTE_CODE}' already points at ${ROUTE_URL} (id ${ROUTE_ID}); nothing to do."
    exit 0
  fi
  echo "Repointing existing '${ROUTE_CODE}' route (id ${ROUTE_ID}) from ${ROUTE_URL_CURRENT} -> ${ROUTE_URL}"
  METHOD=PUT
  URL="${API}/routes/${ROUTE_ID}"
  # PUT targets the existing id via the URL path; don't send an id in the body.
  PAYLOAD="{\"name\":\"${ROUTE_NAME}\",\"code\":\"${ROUTE_CODE}\",\"url\":\"${ROUTE_URL}\"}"
else
  echo "Creating ${ROUTE_CODE} route -> ${ROUTE_URL} (id ${ROUTE_UID})"
  METHOD=POST
  URL="${API}/routes"
  # Create with the predetermined UID so the id is stable across fresh installs.
  PAYLOAD="{\"id\":\"${ROUTE_UID}\",\"name\":\"${ROUTE_NAME}\",\"code\":\"${ROUTE_CODE}\",\"url\":\"${ROUTE_URL}\"}"
fi

RESPONSE=$(curl -s -w '\n%{http_code}' -u "$AUTH" \
  -X "$METHOD" "$URL" \
  -H 'Content-Type: application/json' \
  -d "$PAYLOAD")

STATUS=$(printf '%s' "$RESPONSE" | tail -n1)
BODY=$(printf '%s' "$RESPONSE" | sed '$d')

case "$STATUS" in
  2*)
    echo "Route ${METHOD} succeeded (HTTP ${STATUS})."
    ;;
  *)
    echo "Failed to ${METHOD} route (HTTP ${STATUS}):" >&2
    echo "$BODY" >&2
    exit 1
    ;;
esac
