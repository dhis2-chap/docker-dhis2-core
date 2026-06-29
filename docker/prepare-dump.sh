#!/bin/sh
# Download the DHIS2 demo SQL dump and prepare it for loading into a FRESH database.
#
# Some published dumps are `pg_dump --clean` WITHOUT `--if-exists`, so they open with a
# block of DROP / ALTER TABLE ... DROP CONSTRAINT statements that assume the schema
# already exists. The postgres image runs init scripts with `psql -v ON_ERROR_STOP=1`,
# so the first statement referencing a missing object aborts the entire restore.
#
# Retrofit `--if-exists` semantics so the clean block is a no-op on an empty database.
# The substitutions are idempotent: dumps that ALREADY carry `--if-exists` (e.g. the
# newer climate dumps) are normalized rather than doubled — `ALTER TABLE IF EXISTS ...`
# must not become `ALTER TABLE IF EXISTS IF EXISTS ...` (a syntax error).
#   - ALTER TABLE [IF EXISTS] [ONLY] ... -> ALTER TABLE IF EXISTS [ONLY] ...  (also
#                                 covers the DROP CONSTRAINT lines: if the table is
#                                 missing the whole statement is skipped)
#   - DROP <object> [IF EXISTS] ...      -> DROP <object> IF EXISTS ...
#   - DROP EXTENSION ...        -> deleted. The base postgis image already installs
#                                 postgis (+ topology + tiger_geocoder); dropping it
#                                 fails on the dependency, and the dump re-creates what
#                                 it needs via CREATE EXTENSION IF NOT EXISTS.
#   - DROP SCHEMA ...           -> deleted, and CREATE SCHEMA -> CREATE SCHEMA IF NOT
#                                 EXISTS. Same reason: the spatial extensions live in
#                                 the topology/tiger/tiger_data schemas the base image
#                                 already created, so `DROP SCHEMA topology` fails on
#                                 the dependent extension objects (and the matching
#                                 CREATE SCHEMA would then collide with the existing one).
#
# All substitutions are anchored to the start of the line, so COPY data rows (which
# begin with column values, not SQL keywords) are left untouched.
set -eu

DUMP_FILE=dump.sql.gz
RAW_TMP=raw.sql.gz.part
OUT_TMP=dump.sql.gz.part
# A host-supplied dump can be bind-mounted here (see compose.yml: DHIS2_DB_DUMP_FILE).
# When unset the mount defaults to /dev/null, which fails the gzip test below, so we
# fall back to downloading DHIS2_DB_DUMP_URL.
LOCAL_SRC=/opt/src/dump.sql.gz

if [ -f "$DUMP_FILE" ]; then
  echo "$DUMP_FILE already exists, skipping download"
  exit 0
fi

# Source the dump into a temp file and verify it is a complete, valid gzip BEFORE doing
# anything else. A truncated/empty download (or a bogus local file) must never become the
# cached dump. Prefer a bind-mounted local file; otherwise download DHIS2_DB_DUMP_URL.
rm -f "$RAW_TMP" "$OUT_TMP"
if [ -f "$LOCAL_SRC" ] && gzip -t "$LOCAL_SRC" 2>/dev/null; then
  echo "Using local dump $LOCAL_SRC"
  cp "$LOCAL_SRC" "$RAW_TMP"
else
  echo "Downloading dump from $DHIS2_DB_DUMP_URL"
  wget -O "$RAW_TMP" "$DHIS2_DB_DUMP_URL"
  gzip -t "$RAW_TMP"
fi

echo "Transforming dump"
gunzip -c "$RAW_TMP" \
  | sed -E '
      s/^ALTER TABLE (IF EXISTS )?(ONLY )?/ALTER TABLE IF EXISTS \2/
      s/^DROP (TABLE|INDEX|SEQUENCE|FUNCTION|VIEW|MATERIALIZED VIEW|TYPE|DOMAIN|AGGREGATE|TRIGGER) (IF EXISTS )?/DROP \1 IF EXISTS /
      /^DROP EXTENSION /d
      /^DROP SCHEMA /d
      s/^CREATE SCHEMA (IF NOT EXISTS )?/CREATE SCHEMA IF NOT EXISTS /
    ' \
  | gzip > "$OUT_TMP"

# Verify the transformed output, then publish atomically.
gzip -t "$OUT_TMP"
mv "$OUT_TMP" "$DUMP_FILE"
rm -f "$RAW_TMP"
echo "Wrote $DUMP_FILE ($(wc -c < "$DUMP_FILE") bytes)"
