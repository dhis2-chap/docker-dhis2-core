.PHONY: help start start-force start-chap start-chap-force clean ps logs route

# ==============================================================================
# Config
# ==============================================================================

COMPOSE   := docker compose
CHAP_FILE := compose.chapkit.yml
# compose.chapkit.yml is the umbrella for the whole chap stack: it `include`s
# compose.chap.yml (which itself includes compose.yml — DHIS2 + chap-core) plus
# every chapkit model overlay (e.g. compose.ewars.yml). So `$(CHAP_FILES)`
# drives the entire DHIS2 + chap-core + models stack under one compose project.
#
# compose.chap-route.yml is layered on top with a second `-f` to point the DHIS2
# "chap" route at the bundled chap service. It can't live in the include graph:
# `include` treats a same-named service as a conflict instead of deep-merging it,
# whereas `-f` file stacking deep-merges. CHAP_FILES drives all chap-stack targets.
CHAP_FILES := -f $(CHAP_FILE) -f compose.chap-route.yml

# Admin used by the `route` diagnostic; override on the CLI if you changed them,
# e.g. `DHIS2_ADMIN_PASSWORD=secret make route`.
DHIS2_ADMIN_USER     ?= admin
DHIS2_ADMIN_PASSWORD ?= district

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
	@echo ""
	@echo "Manage (the start targets run in the foreground — Ctrl+C to stop):"
	@echo "  clean             Remove containers AND volumes (full reset)"
	@echo "  ps                Show container status"
	@echo "  logs              Follow logs from all services"
	@echo "  route             Show the DHIS2 -> chap route and probe it end-to-end"
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
start-chap:
	@echo ">>> Starting DHIS2 + chap-core with chapkit models (compose.chapkit.yml) — Ctrl+C to stop"
	@$(COMPOSE) $(CHAP_FILES) up --remove-orphans

start-chap-force:
	@echo ">>> Recreating DHIS2 + chap-core from scratch (removing volumes) — Ctrl+C to stop"
	@$(COMPOSE) $(CHAP_FILES) down -v --remove-orphans
	@$(COMPOSE) $(CHAP_FILES) up --remove-orphans

# --- manage (operate on the whole project, chap + model services included) ---
clean:
	@echo ">>> Stopping and removing containers and volumes"
	@$(COMPOSE) $(CHAP_FILES) down -v

ps:
	@$(COMPOSE) $(CHAP_FILES) ps -a

logs:
	@$(COMPOSE) $(CHAP_FILES) logs -f

# Runs curl inside the dhis2-web container, so it uses DHIS2's internal port and
# the compose network regardless of the published DHIS2_PORT.
route:
	@echo ">>> chap route in DHIS2:"
	@$(COMPOSE) $(CHAP_FILES) exec -T dhis2-web curl -s -u "$(DHIS2_ADMIN_USER):$(DHIS2_ADMIN_PASSWORD)" "http://localhost:8080/api/routes.json?filter=code:eq:chap&fields=id,code,url"; echo
	@echo ">>> proxy probe (DHIS2 -> chap):"
	@$(COMPOSE) $(CHAP_FILES) exec -T dhis2-web curl -s -u "$(DHIS2_ADMIN_USER):$(DHIS2_ADMIN_PASSWORD)" "http://localhost:8080/api/routes/chap/run/health"; echo

# ==============================================================================
# Default
# ==============================================================================

.DEFAULT_GOAL := help
