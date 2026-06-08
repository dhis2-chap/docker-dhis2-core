#!/bin/sh
# Download the DHIS2 demo SQL dump and prepare it for loading into a FRESH database.
#
# The published dumps are `pg_dump --clean` WITHOUT `--if-exists`, so they open with a
# block of DROP / ALTER TABLE ... DROP CONSTRAINT statements that assume the schema
# already exists. The postgres image runs init scripts with `psql -v ON_ERROR_STOP=1`,
# so the first statement referencing a missing object aborts the entire restore.
#
# Retrofit `--if-exists` semantics so the clean block is a no-op on an empty database:
#   - ALTER TABLE [ONLY] ...      -> ALTER TABLE IF EXISTS [ONLY] ...
#   - DROP <object> ...           -> DROP <object> IF EXISTS ...
#   - ... DROP CONSTRAINT <name>  -> ... DROP CONSTRAINT IF EXISTS <name>
#   - DROP EXTENSION ...          -> deleted entirely. The base postgis image already
#     installs postgis (+ topology + tiger_geocoder); dropping it fails on the
#     dependency, and the dump re-creates what it needs via CREATE EXTENSION IF NOT EXISTS.
set -eu

DUMP_FILE=dump.sql.gz

if [ -f "$DUMP_FILE" ]; then
  echo "$DUMP_FILE already exists, skipping download"
  exit 0
fi

echo "Downloading and transforming dump from $DHIS2_DB_DUMP_URL"
wget -O - "$DHIS2_DB_DUMP_URL" \
  | gunzip \
  | sed -E '
      s/DROP CONSTRAINT ([a-zA-Z0-9_]+);/DROP CONSTRAINT IF EXISTS \1;/g
      s/^ALTER TABLE (ONLY )?/ALTER TABLE IF EXISTS \1/
      s/^DROP (TABLE|INDEX|SEQUENCE|FUNCTION|VIEW|MATERIALIZED VIEW|TYPE|DOMAIN|AGGREGATE|TRIGGER|SCHEMA) /DROP \1 IF EXISTS /
      /^DROP EXTENSION /d
    ' \
  | gzip > "$DUMP_FILE"
echo "Wrote $DUMP_FILE"
