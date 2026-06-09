.PHONY: help start start-force start-chap start-chap-force clean ps logs route

# ==============================================================================
# Config
# ==============================================================================

COMPOSE   := docker compose
CHAP_FILE := compose.chap.yml
# The overlay `include`s compose.yml, so `-f $(CHAP_FILE)` controls the whole
# DHIS2 + chap-core stack under the same compose project.

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
	@echo "  start-chap        Start DHIS2 + chap-core (compose.chap.yml)"
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

# --- start: DHIS2 + chap-core --- (foreground; Ctrl+C to stop)
start-chap:
	@echo ">>> Starting DHIS2 + chap-core (compose.chap.yml) — Ctrl+C to stop"
	@$(COMPOSE) -f $(CHAP_FILE) up --remove-orphans

start-chap-force:
	@echo ">>> Recreating DHIS2 + chap-core from scratch (removing volumes) — Ctrl+C to stop"
	@$(COMPOSE) -f $(CHAP_FILE) down -v --remove-orphans
	@$(COMPOSE) -f $(CHAP_FILE) up --remove-orphans

# --- manage (operate on the whole project, chap services included) ---
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

# ==============================================================================
# Default
# ==============================================================================

.DEFAULT_GOAL := help
