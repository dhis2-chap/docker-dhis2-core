.PHONY: help start start-force start-chap start-chap-force start-ocs start-ocs-force clean ps logs route ocs-route clean-ocs-data restart-ocs

# ==============================================================================
# Config
# ==============================================================================

COMPOSE   := docker compose
CHAP_FILE := compose.chapkit.yml
# compose.chapkit.yml is the umbrella for the whole chap stack: it `include`s
# compose.chap.yml (which itself includes compose.yml — DHIS2 + chap-core) plus
# every chapkit model overlay (e.g. compose.ewars.yml). So `-f $(CHAP_FILE)`
# drives the entire DHIS2 + chap-core + models stack under one compose project.

# Admin used by the `route` diagnostic; override on the CLI if you changed them,
# e.g. `DHIS2_ADMIN_PASSWORD=secret make route`.
DHIS2_ADMIN_USER     ?= admin
DHIS2_ADMIN_PASSWORD ?= district

# Default netrc to ~/.netrc if it exists; fall back to /dev/null so the OCS
# stack starts even for users who don't have ERA5-Land credentials.
NETRC_DEFAULT := $(shell [ -f "$(HOME)/.netrc" ] && echo "$(HOME)/.netrc" || echo "/dev/null")

# ==============================================================================
# Targets
# ==============================================================================

help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Start:"
	@echo "  start             Start DHIS2 only (compose.yml)"
	@echo "  start-force       Recreate DHIS2 from scratch (wipes volumes, fresh dump + analytics)"
	@echo "  start-chap        Start DHIS2 + chap-core with chapkit models (compose.chapkit.yml)"
	@echo "  start-chap-force  Recreate DHIS2 + chap-core from scratch (wipes all volumes)"
	@echo "  start-ocs         Start DHIS2 + OCS (compose.ocs.yml)"
	@echo "  start-ocs-force   Recreate DHIS2 + OCS from scratch (wipes all volumes)"
	@echo ""
	@echo "Manage (the start targets run in the foreground — Ctrl+C to stop):"
	@echo "  clean             Remove containers AND volumes (full reset)"
	@echo "  restart-ocs       Restart the OCS container only (picks up .env changes)"
	@echo "  clean-ocs-data    Clear OCS cached data only (DHIS2 data preserved)"
	@echo "                    To change the extent, edit docker/ocs/climate-service.yaml then re-run"
	@echo "  ps                Show container status"
	@echo "  logs              Follow logs from all services"
	@echo "  route             Show the DHIS2 -> chap route and probe it end-to-end"
	@echo "  ocs-route         Show the DHIS2 -> OCS route and probe it end-to-end"
	@echo ""
	@echo "Published host ports (all on 127.0.0.1, override per stack to avoid clashes):"
	@echo "  DHIS2_PORT    DHIS2 web        default 8080"
	@echo "  DHIS2_DB_PORT DHIS2 database   default 15432   (psql/DBeaver)"
	@echo "  CHAP_DB_PORT  chap database    default 15433   (psql/DBeaver, start-chap only)"
	@echo "  e.g.  DHIS2_PORT=8081 make start-chap"
	@echo "chap-core itself stays internal — DHIS2 reaches it via the 'chap' route."

# --- start: DHIS2 only --- (foreground; Ctrl+C to stop)
# --remove-orphans so switching from the chap stack to DHIS2-only actually stops
# the chap containers (both share one compose project).
start:
	@echo ">>> Starting DHIS2 (compose.yml) — Ctrl+C to stop"
	@$(COMPOSE) up --remove-orphans

start-force:
	@echo ">>> Recreating DHIS2 from scratch (removing volumes) — Ctrl+C to stop"
	@$(COMPOSE) down -v --remove-orphans
	@$(COMPOSE) up --remove-orphans

# --- start: DHIS2 + chap-core (with chapkit models) --- (foreground; Ctrl+C to stop)
# The chap stack points the DHIS2 -> chap route at the bundled chap service. We set
# DHIS2_ROUTE_URL here rather than overriding chap-route-init in compose.chap.yml, because
# redefining a service imported via `include:` is rejected by older Docker Compose
# ("conflicts with imported resource"). An explicit DHIS2_ROUTE_URL in your environment wins.
start-chap:
	@echo ">>> Starting DHIS2 + chap-core with chapkit models (compose.chapkit.yml) — Ctrl+C to stop"
	@DHIS2_ROUTE_URL="$${DHIS2_ROUTE_URL:-$${CHAP_ROUTE_URL:-http://chap:8000/**}}" $(COMPOSE) -f $(CHAP_FILE) up --remove-orphans

start-chap-force:
	@echo ">>> Recreating DHIS2 + chap-core from scratch (removing volumes) — Ctrl+C to stop"
	@$(COMPOSE) -f $(CHAP_FILE) down -v --remove-orphans
	@DHIS2_ROUTE_URL="$${DHIS2_ROUTE_URL:-$${CHAP_ROUTE_URL:-http://chap:8000/**}}" $(COMPOSE) -f $(CHAP_FILE) up --remove-orphans

start-ocs:
	@echo ">>> Starting DHIS2 + OCS (compose.ocs.yml) — Ctrl+C to stop"
	@NETRC_FILE="$${NETRC_FILE:-$(NETRC_DEFAULT)}" OCS_ROUTE_URL="$${OCS_ROUTE_URL:-http://ocs:9000/**}" $(COMPOSE) -f compose.ocs.yml up --remove-orphans

start-ocs-force:
	@echo ">>> Recreating DHIS2 + OCS from scratch (removing volumes) — Ctrl+C to stop"
	@$(COMPOSE) -f compose.ocs.yml down -v --remove-orphans
	@NETRC_FILE="$${NETRC_FILE:-$(NETRC_DEFAULT)}" OCS_ROUTE_URL="$${OCS_ROUTE_URL:-http://ocs:9000/**}" $(COMPOSE) -f compose.ocs.yml up --remove-orphans

# --- manage (operate on the whole project, chap + model services included) ---
clean:
	@echo ">>> Stopping and removing containers and volumes"
	@$(COMPOSE) -f $(CHAP_FILE) down -v

ps:
	@$(COMPOSE) -f $(CHAP_FILE) ps -a

logs:
	@$(COMPOSE) -f $(CHAP_FILE) logs -f

# Runs curl inside the dhis2-web container, so it uses DHIS2's internal port and
# the compose network regardless of the published DHIS2_PORT.
route:
	@echo ">>> chap route in DHIS2:"
	@$(COMPOSE) -f $(CHAP_FILE) exec -T dhis2-web curl -s -u "$(DHIS2_ADMIN_USER):$(DHIS2_ADMIN_PASSWORD)" "http://localhost:8080/api/routes.json?filter=code:eq:chap&fields=id,code,url"; echo
	@echo ">>> proxy probe (DHIS2 -> chap):"
	@$(COMPOSE) -f $(CHAP_FILE) exec -T dhis2-web curl -s -u "$(DHIS2_ADMIN_USER):$(DHIS2_ADMIN_PASSWORD)" "http://localhost:8080/api/routes/chap/run/health"; echo

ocs-route:
	@echo ">>> OCS route in DHIS2:"
	@$(COMPOSE) -f compose.ocs.yml exec -T dhis2-web curl -s -u "$(DHIS2_ADMIN_USER):$(DHIS2_ADMIN_PASSWORD)" "http://localhost:8080/api/routes.json?filter=code:eq:ocs&fields=id,code,url"; echo
	@echo ">>> proxy probe (DHIS2 -> OCS):"
	@$(COMPOSE) -f compose.ocs.yml exec -T dhis2-web curl -s -u "$(DHIS2_ADMIN_USER):$(DHIS2_ADMIN_PASSWORD)" "http://localhost:8080/api/routes/ocs/run/health"; echo

# Stops OCS, wipes only the ocs-data volume, and leaves DHIS2 untouched.
# To also change the extent, edit docker/ocs/climate-service.yaml before restarting.
restart-ocs:
	@echo ">>> Restarting OCS"
	@NETRC_FILE="$${NETRC_FILE:-$(NETRC_DEFAULT)}" $(COMPOSE) -f compose.ocs.yml up -d --no-deps --force-recreate ocs

clean-ocs-data:
	@echo ">>> Clearing OCS cached data (DHIS2 data preserved)"
	@$(COMPOSE) -f compose.ocs.yml stop ocs
	@$(COMPOSE) -f compose.ocs.yml run --rm --no-deps ocs sh -c "rm -rf /app/data/*"

# ==============================================================================
# Default
# ==============================================================================

.DEFAULT_GOAL := help
