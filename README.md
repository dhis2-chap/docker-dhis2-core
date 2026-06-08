# docker-dhis2-core

A simple Docker Compose setup for DHIS2 Core `2.42.5` with a PostGIS-backed PostgreSQL database.

Optionally, it can also bring up a [chap-core](https://github.com/dhis2-chap/chap-core)
`v2.0.0` server (plus a chapkit model) wired to DHIS2 through a DHIS2 Route — see
[Running with chap-core](#running-with-chap-core).

Repository: https://github.com/dhis2-chap/docker-dhis2-core

## Prerequisites

- Docker installed
- Docker Compose v2.20+ (the `docker compose` plugin; the chap overlay uses the
  `include` directive, which legacy `docker-compose` does not support)
- `make` (optional, but the documented commands use it)

## .env setup (optional)

Every value has a working default baked into the compose files, so the stack runs
without a `.env`. Create one only to change credentials or published ports — copy the
template and edit:

```bash
cp .env.example .env
```

Docker Compose automatically loads `.env` from the project directory.

## Start services

From the repository root (runs in the foreground — `Ctrl+C` to stop):

```bash
make start            # DHIS2 only
# equivalent to: docker compose up   (add -d to detach)
```

This starts the DHIS2-only stack (`compose.yml`):

- `web` - DHIS2 application (published on `127.0.0.1:8080`)
- `db` - PostGIS database (published on `127.0.0.1:15432` for psql/DBeaver)
- `db-dump` - one-shot: downloads and prepares the database dump, then exits
- `analytics-trigger` - one-shot: after DHIS2 is healthy, generates the `analytics_*`
  tables (needed by the Data Visualizer, Climate app, and CHAP), then exits

First startup takes a few minutes: the dump loads, DHIS2 migrates and boots, then
`analytics-trigger` populates analytics before exiting. Then open DHIS2 at:

```text
http://127.0.0.1:8080
```

> Default credentials: `admin` / `district`.

To also run chap-core alongside DHIS2, see [Running with chap-core](#running-with-chap-core).

### Ports & databases (DBeaver / psql)

Three things are published on the host, all bound to `127.0.0.1` and all
env-overridable. chap-core, EWARS, and redis stay internal — DHIS2 reaches chap over
the Compose network via the `chap` route.

| Var | Service | Use | Default |
|-----|---------|-----|---------|
| `DHIS2_PORT` | DHIS2 web | UI / API | `8080` |
| `DHIS2_DB_PORT` | DHIS2 PostGIS | browse DHIS2 data with psql/DBeaver | `15432` |
| `CHAP_DB_PORT` | chap Postgres | browse chap data with psql/DBeaver (chap stack) | `15433` |

Connect a SQL client after `make start-chap`:

| | Host | Port | Database | User | Password |
|-|------|------|----------|------|----------|
| DHIS2 | `127.0.0.1` | `15432` | `dhis` | `dhis` | `dhis` |
| chap | `127.0.0.1` | `15433` | `chap_core` | `chap` | `chap` |

```bash
psql -h 127.0.0.1 -p 15432 -U dhis dhis      # DHIS2 data
psql -h 127.0.0.1 -p 15433 -U chap chap_core # chap data
```

The DB ports default to the `15xxx` range to avoid clashing with a local postgres on
`5432`. Running several stacks? Give each its own `.env` with distinct ports. To let
another machine connect (e.g. during a demo), drop the `127.0.0.1:` prefix on that
service's `ports:` in the compose file.

```bash
DHIS2_PORT=8081 make start-chap   # move DHIS2 off 8080 to coexist with another stack
```

## Stop and reset

The start targets run in the foreground, so **`Ctrl+C` stops** the stack (containers
remain and resume on the next `make start`).

For a full reset — remove containers, networks, and volumes (forces a fresh dump load
and analytics run next time):

```bash
make clean
# equivalent to: docker compose -f compose.chap.yml down -v
```

## Running with chap-core

`compose.chap.yml` is an overlay that `include`s the DHIS2 stack above and adds a
[chap-core](https://github.com/dhis2-chap/chap-core) `v2.0.0` server, its worker /
broker / database, a [chapkit](https://github.com/dhis2-chap/chap-core) model
(EWARS), and a one-shot that creates the DHIS2 Route connecting the two.

Bring up everything (DHIS2 + chap-core), foreground (`Ctrl+C` to stop):

```bash
make start-chap
# equivalent to: docker compose -f compose.chap.yml up   (add -d to detach)
```

This adds, on top of the DHIS2 services:

- `chap` - chap-core REST API (internal; reached by DHIS2 at `http://chap:8000`)
- `chap-worker` - Celery worker that runs the models (INLA/R baked in)
- `chap-redis` - broker (internal)
- `chap-postgres` - chap database (published on `127.0.0.1:15433` for psql/DBeaver)
- `chap-ewars` - EWARS chapkit model; self-registers with chap on startup (internal)
- `chap-route-init` - one-shot that wires up the DHIS2 → chap route, then exits

### How DHIS2 talks to chap

All access to chap-core goes **through DHIS2**, via a DHIS2 [Route](https://docs.dhis2.org/en/develop/using-the-api/dhis-core-version-242/route.html)
(a built-in reverse proxy) with code `chap` pointing at `http://chap:8000/**`. chap-core
itself has **no authentication**, so it is never published to the host — DHIS2 is the
only entry point, and it enforces auth.

`chap-route-init` sets this up automatically once DHIS2 is healthy. It is
self-correcting: the climate demo dumps ship a `chap` route aimed at an external CHAP
server, so the one-shot **repoints** it at the local chap rather than leaving the stale
target in place. Verify the route proxies through:

```bash
curl -u admin:district http://127.0.0.1:8080/api/routes/chap/run/health
# -> {"status":"success","message":"healthy"}
```

The manual equivalent (e.g. if you recreate it by hand) is a `POST`/`PUT` to
`/api/routes` with `{"name":"chap","code":"chap","url":"http://chap:8000/**"}`.

### Using chap from the DHIS2 UI

Install the [Modelling App](https://apps.dhis2.org/app/a29851f9-82a7-4ecd-8b2c-58e0f220bc75)
from the App Hub (App Management → App Hub). It uses the `chap` route above and the
`analytics_*` tables populated by `analytics-trigger`. Installing apps is outside the
scope of this compose setup.

### Inspecting the data

Both databases are published on `127.0.0.1` so you can browse the data with psql or
DBeaver — see [Ports & databases](#ports--databases-dbeaver--psql) for the connection
details. chap-core itself is internal; for ad-hoc poking use
`docker compose -f compose.chap.yml exec chap ...`.

### Notes

- The chap images are pinned to the `v2.0.0` tag (note the leading `v`).
- To stop and remove the chap-core volumes as well: `docker compose -f compose.chap.yml down -v`.

## Notes

- Published host ports — DHIS2 web and both databases — all bind to `127.0.0.1` and
  are env-overridable (see [Ports & databases](#ports--databases-dbeaver--psql)).
  chap-core, EWARS, and redis are internal to the Compose network.
- The `db-dump` service downloads and patches the dump file into the named volume only once; deleting the volume forces it to re-download.
- `analytics-trigger` runs the analytics export on first boot; it re-runs on every `up`
  (cheap if already current). DHIS2 needs a few GB of RAM for the populate phase — if
  the container gets OOM-killed mid-run, raise Docker's memory limit.
