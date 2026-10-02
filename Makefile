COMPOSE_FILE := srcs/docker-compose.yml
COMPOSE := docker compose -f $(COMPOSE_FILE)
DATA_ROOT := /home/arhea/data

ENV_FILE := srcs/.env
ENV_TEMPLATE := srcs/.env.example

SECRETS_DIR := secrets
SECRET_FILES := \
	$(SECRETS_DIR)/db_root_password.txt \
	$(SECRETS_DIR)/db_password.txt \
	$(SECRETS_DIR)/wp_admin_password.txt \
	$(SECRETS_DIR)/wp_user_password.txt

.DEFAULT_GOAL := all
.DELETE_ON_ERROR:

.PHONY: all check prepare config build up start stop restart down clean fclean re logs ps

all: up

check:
	@command -v docker >/dev/null 2>&1 || { printf 'ERROR: docker is not installed\n' >&2; exit 1; }
	@docker compose version >/dev/null 2>&1 || { printf 'ERROR: Docker Compose is not installed\n' >&2; exit 1; }
	@docker info >/dev/null 2>&1 || { printf 'ERROR: Docker daemon is not available\n' >&2; exit 1; }
	@command -v openssl >/dev/null 2>&1 || { printf 'ERROR: openssl is not installed\n' >&2; exit 1; }
	@actual_root="$$(docker info --format '{{.DockerRootDir}}')"; \
	if [ "$$actual_root" != "$(DATA_ROOT)" ]; then \
		printf 'ERROR: Docker data root must be %s (found %s)\n' "$(DATA_ROOT)" "$$actual_root" >&2; \
		exit 1; \
	fi

prepare: check $(ENV_FILE) $(SECRET_FILES)
	@chmod 700 $(SECRETS_DIR)
	@chmod 600 $(ENV_FILE) $(SECRET_FILES)

$(ENV_FILE): | $(ENV_TEMPLATE)
	@cp $(ENV_TEMPLATE) $(ENV_FILE)
	@printf 'Created %s from %s\n' "$@" "$(ENV_TEMPLATE)"

$(SECRET_FILES):
	@mkdir -p $(SECRETS_DIR)
	@umask 077; openssl rand -hex 24 > "$@"
	@printf 'Created %s\n' "$@"

config: prepare
	$(COMPOSE) config --quiet

build: config
	$(COMPOSE) build

up: config
	$(COMPOSE) up --detach --build

start: prepare
	$(COMPOSE) start

stop: prepare
	$(COMPOSE) stop

restart: prepare
	$(COMPOSE) restart

down: prepare
	$(COMPOSE) down --remove-orphans

clean: down

fclean: prepare
	$(COMPOSE) down --volumes --rmi all --remove-orphans

re: fclean
	$(MAKE) all

logs: prepare
	$(COMPOSE) logs --follow

ps: prepare
	$(COMPOSE) ps
