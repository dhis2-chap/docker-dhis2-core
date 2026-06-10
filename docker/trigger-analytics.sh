#!/bin/sh
# Generate the DHIS2 analytics tables after a fresh dump load.
#
# A freshly restored dump has raw data values but NO populated analytics_* tables,
# so anything that reads analytics (the Data Visualizer, the Climate app, and the
# CHAP Modelling App) sees nothing until this job runs. This one-shot starts the
# analytics export and waits for it to finish, then exits.
set -eu

# Opt out of analytics generation entirely (faster startup, but no analytics_*
# data for the Data Visualizer / Climate app / CHAP). Default on.
if [ "${DHIS2_ANALYTICS:-1}" = "0" ]; then
  echo "DHIS2_ANALYTICS=0 — skipping analytics table generation."
  exit 0
fi

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

# Returns the id of an ANALYTICS_TABLE job in the given status, or empty.
job_in_status() {
  curl -s -u "$AUTH" "${API}/jobConfigurations.json?paging=false&fields=id,jobStatus&filter=jobType:eq:ANALYTICS_TABLE&filter=jobStatus:eq:$1" \
    | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -1
}

# DHIS2 runs only one analytics job at a time. If one is already RUNNING (e.g. the
# scheduler picked one up on boot), watch THAT one — starting another just queues a
# job that never runs, and its notifier stays empty forever (this was the hang).
TASK_ID=$(job_in_status RUNNING)
if [ -n "$TASK_ID" ]; then
  echo "Analytics already running (job ${TASK_ID}); waiting for it to finish ..."
else
  echo "Triggering analytics table generation ..."
  RESPONSE=$(curl -s -u "$AUTH" -X POST "${API}/resourceTables/analytics")
  TASK_ID=$(echo "$RESPONSE" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -1)
  if [ -z "$TASK_ID" ]; then
    echo "Failed to start analytics (could not parse job id):" >&2
    echo "$RESPONSE" >&2
    exit 1
  fi
fi

# Wait for completion. Primary signal is the per-job notifier's "completed":true
# (exactly what the data-administration UI watches). Fallback: the job's own
# lastExecutedStatus flips to COMPLETED — covers an empty/missed notifier. Bounded
# by wall-clock so nothing can loop forever; the demo finishes in well under 1 min.
START=$(date +%s)
while :; do
  sleep 5
  elapsed=$(( $(date +%s) - START ))

  STATUS=$(curl -s -u "$AUTH" "${API}/system/tasks/ANALYTICS_TABLE/${TASK_ID}")
  if echo "$STATUS" | grep -q '"completed":true'; then
    echo "Analytics tables completed successfully (took ${elapsed}s)."
    exit 0
  fi
  if echo "$STATUS" | grep -q '"level":"ERROR"'; then
    echo "Analytics failed after ${elapsed}s!" >&2
    echo "$STATUS" >&2
    exit 1
  fi

  # Authoritative fallback via job status (does not depend on the notifier).
  JOB=$(curl -s -u "$AUTH" "${API}/jobConfigurations.json?fields=jobStatus,lastExecutedStatus&filter=jobType:eq:ANALYTICS_TABLE&filter=id:eq:${TASK_ID}")
  case "$JOB" in
    *'"lastExecutedStatus":"COMPLETED"'*)
      echo "Analytics tables completed (job status) — took ${elapsed}s."
      exit 0 ;;
    *'"lastExecutedStatus":"FAILED"'*)
      echo "Analytics failed after ${elapsed}s (job status FAILED)." >&2
      exit 1 ;;
  esac

  if [ "$elapsed" -ge 3600 ]; then
    echo "Analytics did not complete within ${elapsed}s (job ${TASK_ID})." >&2
    exit 1
  fi
  echo "  building analytics tables — ${elapsed}s elapsed ..."
done
