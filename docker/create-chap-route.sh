#!/bin/sh
# Register a DHIS2 Route that reverse-proxies DHIS2 -> chap-core.
#
# The DHIS2 Modelling App talks to chap-core through the DHIS2 Routes API rather
# than reaching chap directly, so chap never has to be exposed publicly. This
# one-shot waits for the DHIS2 API to come up, then ensures a wildcard route with
# code "chap" points at the internal chap service.
#
# It is idempotent AND self-correcting: the climate demo dumps ship a pre-made
# "chap" route aimed at an external CHAP server, so we don't just skip when a route
# exists -- we repoint it at our local chap unless it already matches.
#
# Notes:
#   - The target URL MUST end in /** (a DHIS2 "wildcard route").
#   - chap-core has no auth, so the route has no auth block.
#   - dhis.conf sets `route.remote_servers_allowed = http://*`, which is what lets
#     DHIS2 v42 accept an http:// (non-https) route target.
set -eu

: "${DHIS2_BASE_URL:?}"
: "${DHIS2_ADMIN_USER:?}"
: "${DHIS2_ADMIN_PASSWORD:?}"
: "${CHAP_ROUTE_URL:?}"

# Stable, predetermined UID for the chap route, so a fresh install always gets the
# same id instead of a random server-assigned one. Generated with the DHIS2 CLI:
#   dhis2 dev uid
# Override CHAP_ROUTE_UID to use a different one. (Only applies when CREATING the
# route; if the demo dump already shipped a "chap" route we reuse its existing id.)
CHAP_ROUTE_UID="${CHAP_ROUTE_UID:-TkdmmuSCGPA}"

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

# Is there already a route with code "chap"? Grab its id and current url.
EXISTING=$(curl -s -u "$AUTH" "${API}/routes.json?filter=code:eq:chap&fields=id,url")
ROUTE_ID=$(echo "$EXISTING" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -1)
ROUTE_URL=$(echo "$EXISTING" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p' | head -1)

if [ -n "$ROUTE_ID" ]; then
  if [ "$ROUTE_URL" = "$CHAP_ROUTE_URL" ]; then
    echo "Route 'chap' already points at ${CHAP_ROUTE_URL} (id ${ROUTE_ID}); nothing to do."
    exit 0
  fi
  echo "Repointing existing 'chap' route (id ${ROUTE_ID}) from ${ROUTE_URL} -> ${CHAP_ROUTE_URL}"
  METHOD=PUT
  URL="${API}/routes/${ROUTE_ID}"
  # PUT targets the existing id via the URL path; don't send an id in the body.
  PAYLOAD="{\"name\":\"chap\",\"code\":\"chap\",\"url\":\"${CHAP_ROUTE_URL}\"}"
else
  echo "Creating chap route -> ${CHAP_ROUTE_URL} (id ${CHAP_ROUTE_UID})"
  METHOD=POST
  URL="${API}/routes"
  # Create with the predetermined UID so the id is stable across fresh installs.
  PAYLOAD="{\"id\":\"${CHAP_ROUTE_UID}\",\"name\":\"chap\",\"code\":\"chap\",\"url\":\"${CHAP_ROUTE_URL}\"}"
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
