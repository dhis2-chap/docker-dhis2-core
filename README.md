# docker-dhis2-core

A simple Docker Compose setup for DHIS2 Core `2.42.4` with a PostGIS-backed PostgreSQL database.

Repository: https://github.com/dhis2-chap/docker-dhis2-core

## Prerequisites

- Docker installed
- Docker Compose available as `docker compose` or `docker-compose`
- Environment variables set:
  - `DB_USERNAME`
  - `DB_PASSWORD`

Optional:
- `DB_NAME` (defaults to `dhis`)
- `DB_HOSTNAME` (defaults to `db`)
- `DHIS2_DB_DUMP_URL` (defaults to the Laos 2.42 climate demo database)

## .env setup

Copy the provided .env.example file into `.env` in the repository root:

```bash
cp .env.example .env
```

You can leave the example values as-is or update them as desired.

Docker Compose automatically loads `.env` from the project directory.

## Start services

From the repository root:

```bash
docker compose up -d
```

This starts:

- `db` - PostGIS database service
- `db-dump` - one-shot service that downloads and prepares the database dump
- `web` - DHIS2 application

Then open DHIS2 at:

```text
http://127.0.0.1:8080
```

## Stop services

To stop the running services without removing containers:

```bash
docker compose stop
```

To stop and remove containers, networks, and default volumes created by Compose:

```bash
docker compose down
```

## Clear data and reset

The database dump and any temporary state are stored in the named volume `db-dump`.

To remove that volume and force a fresh database download/initialization on the next startup:

```bash
docker compose down -v
```

If you want to remove only the named volume manually:

```bash
docker volume rm docker-dhis2-core_db-dump
```

> Note: The exact named volume may vary depending on your Compose project name. Use `docker volume ls` to confirm.

## Notes

- The `web` service is bound to `127.0.0.1:8080` for local-only access.
- The `db` service exposes PostgreSQL on `127.0.0.1:5432`.
- The `db-dump` service downloads and patches the dump file into the named volume only once; deleting the volume forces it to re-download.
