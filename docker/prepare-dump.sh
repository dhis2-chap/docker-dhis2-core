#!/bin/sh
# Download the DHIS2 demo SQL dump and prepare it for loading into a FRESH database.
#
# The published dumps are `pg_dump --clean` WITHOUT `--if-exists`, so they open with a
# block of DROP / ALTER TABLE ... DROP CONSTRAINT statements that assume the schema
# already exists. The postgres image runs init scripts with `psql -v ON_ERROR_STOP=1`,
# so the first statement referencing a missing object aborts the entire restore.
#
# Retrofit `--if-exists` semantics so the clean block is a no-op on an empty database:
#   - ALTER TABLE [ONLY] ...   -> ALTER TABLE IF EXISTS [ONLY] ...  (also covers the
#                                 DROP CONSTRAINT lines: if the table is missing the
#                                 whole statement is skipped)
#   - DROP <object> ...        -> DROP <object> IF EXISTS ...
#   - DROP EXTENSION ...       -> deleted. The base postgis image already installs
#                                 postgis (+ topology + tiger_geocoder); dropping it
#                                 fails on the dependency, and the dump re-creates what
#                                 it needs via CREATE EXTENSION IF NOT EXISTS.
#
# All substitutions are anchored to the start of the line, so COPY data rows (which
# begin with column values, not SQL keywords) are left untouched.
set -eu

DUMP_FILE=dump.sql.gz
RAW_TMP=raw.sql.gz.part
OUT_TMP=dump.sql.gz.part

if [ -f "$DUMP_FILE" ]; then
  echo "$DUMP_FILE already exists, skipping download"
  exit 0
fi

# Download to a temp file and verify it is a complete, valid gzip BEFORE doing anything
# else. A truncated/empty download must never become the cached dump.
echo "Downloading dump from $DHIS2_DB_DUMP_URL"
rm -f "$RAW_TMP" "$OUT_TMP"
wget -O "$RAW_TMP" "$DHIS2_DB_DUMP_URL"
gzip -t "$RAW_TMP"

echo "Transforming dump"
gunzip -c "$RAW_TMP" \
  | sed -E '
      s/^ALTER TABLE (ONLY )?/ALTER TABLE IF EXISTS \1/
      s/^DROP (TABLE|INDEX|SEQUENCE|FUNCTION|VIEW|MATERIALIZED VIEW|TYPE|DOMAIN|AGGREGATE|TRIGGER|SCHEMA) /DROP \1 IF EXISTS /
      /^DROP EXTENSION /d
    ' \
  | gzip > "$OUT_TMP"

# Verify the transformed output, then publish atomically.
gzip -t "$OUT_TMP"
mv "$OUT_TMP" "$DUMP_FILE"
rm -f "$RAW_TMP"
echo "Wrote $DUMP_FILE ($(wc -c < "$DUMP_FILE") bytes)"
