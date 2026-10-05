*This project has been created as part of the 42 curriculum by arhea.*

# Inception

## Description

Inception builds a small web infrastructure inside a Debian virtual machine. Docker Compose builds three custom images and runs each main service in its own container:

- **NGINX** is the only public entry point. It accepts HTTPS connections on port 443 with TLS 1.2 or TLS 1.3 and forwards PHP requests to WordPress through FastCGI.
- **WordPress with PHP-FPM** provides the website and its two application users. It listens only inside the Docker network on port 9000.
- **MariaDB** stores the WordPress database and listens only inside the Docker network on port 3306.

The request path is:

```text
Browser -> HTTPS/443 -> NGINX -> FastCGI/9000 -> WordPress -> TCP/3306 -> MariaDB
```

The repository contains:

- a root `Makefile` that prepares local configuration, validates the environment, builds the images, and manages the stack;
- `srcs/docker-compose.yml`, which declares the services, private network, named volumes, and secrets;
- one custom `Dockerfile` for each service under `srcs/requirements/`;
- service configuration and entrypoint scripts under each service's `conf/` and `tools/` directories;
- `srcs/.env.example`, a tracked template containing non-confidential configuration;
- `USER_DOC.md` and `DEV_DOC.md` for user and developer procedures.

Real `srcs/.env` and `secrets/` files are created locally and ignored by Git.

### Main design choices

- Every service image is built from `debian:bookworm-slim`; no ready-made NGINX, WordPress, or MariaDB service image is used.
- Images are named after their services—`nginx:inception`, `wordpress:inception`, and `mariadb:inception`—and use explicit `inception` tags instead of the forbidden `latest` tag.
- Each entrypoint performs bounded, idempotent initialization and then uses `exec` to make the service the container's main process.
- Only NGINX publishes a host port. WordPress and MariaDB remain reachable only through the dedicated `inception` bridge network.
- MariaDB data and WordPress files use Docker named volumes. Docker's data root is `/home/arhea/data`, so the persistent volume data remains under the path required by the subject.
- Non-confidential settings use `.env`; passwords use separate Docker Compose secret files mounted under `/run/secrets/`.
- The containers use `restart: on-failure` so Docker restarts a service after an unexpected process failure.

### Virtual machines vs Docker

A virtual machine emulates a complete computer and runs its own operating-system kernel. It provides strong isolation but consumes more resources. A Docker container is an isolated group of processes that shares the host kernel, so it starts faster and uses fewer resources.

This project uses both layers: the Debian VM isolates the complete project from the physical computer, while Docker separates NGINX, WordPress, and MariaDB inside that VM.

### Secrets vs environment variables

Environment variables are convenient for non-confidential configuration such as the domain, database name, and application usernames. They can be visible through process or container inspection, so they are unsuitable for passwords.

Compose secrets expose confidential values to selected containers as files under `/run/secrets/`. This project therefore keeps passwords in local, Git-ignored files and uses `.env` only for non-confidential values.

### Docker network vs host network

The dedicated bridge network isolates service traffic and provides DNS resolution by service name: NGINX reaches `wordpress:9000`, and WordPress reaches `mariadb:3306`. Only explicitly published ports reach the host.

Host networking would make a container share the host's network namespace, reducing isolation and making port exposure harder to control. It is also forbidden by the subject.

### Docker volumes vs bind mounts

A named volume is managed by Docker and can survive container removal. It is identified by a logical name rather than by a service-specific host path. A bind mount directly maps a chosen host file or directory into a container, which couples the deployment to that exact host path and its permissions.

The subject requires named volumes and forbids bind mounts for the two persistent stores. This project uses `mariadb_data` for `/var/lib/mysql` and `wordpress_data` for `/var/www/html`.

## Instructions

### Prerequisites

Run the project from a Linux virtual machine with:

- Docker Engine;
- the Docker Compose plugin (`docker compose`);
- GNU Make;
- OpenSSL;
- the current user authorized to communicate with the Docker daemon;
- Docker configured with `/home/arhea/data` as its data root.

Verify the Docker data root:

```bash
docker info --format 'Docker Root Dir: {{.DockerRootDir}}'
```

Expected output:

```text
Docker Root Dir: /home/arhea/data
```

Configure local name resolution once:

```bash
grep -q 'arhea\.42\.fr' /etc/hosts || \
    echo '127.0.0.1 arhea.42.fr' | \
    sudo tee -a /etc/hosts
```

### Build and start

From the repository root, run:

```bash
make
```

On a fresh clone, the Makefile copies `srcs/.env.example` to the ignored `srcs/.env` and generates any missing password files with OpenSSL. Existing configuration and secrets are preserved. It then validates Compose, builds all three images, and starts the stack in the background.

Open:

- Website: `https://arhea.42.fr`
- WordPress administration: `https://arhea.42.fr/wp-admin/`

The certificate is self-signed, so a browser warning is expected in this local environment.

The WordPress administrator username is `arhea_owner`. Its locally generated password is stored in `secrets/wp_admin_password.txt`. Do not commit or publish that file.

### Project commands

| Command | Effect |
|---|---|
| `make` or `make all` | Validate, build, and start the entire stack. |
| `make config` | Validate the resolved Compose configuration. |
| `make build` | Build the three service images. |
| `make up` | Build and start the stack. |
| `make stop` | Stop existing containers without removing them. |
| `make start` | Start existing stopped containers. |
| `make restart` | Restart existing containers. |
| `make down` or `make clean` | Remove containers and the project network while preserving volumes. |
| `make ps` | Display service status and published ports. |
| `make logs` | Follow service logs; press `Ctrl+C` to stop following them. |
| `make fclean` | Remove project containers, images, network, and persistent volumes. |
| `make re` | Perform `fclean` and rebuild the stack from the remaining local configuration. |

`make fclean` and `make re` permanently delete the MariaDB and WordPress volume data.

For detailed operating instructions, see `USER_DOC.md`. For environment setup, architecture, and development procedures, see `DEV_DOC.md`.

## Resources

- [Docker overview](https://docs.docker.com/get-started/docker-overview/)
- [Dockerfile reference](https://docs.docker.com/reference/dockerfile/)
- [Docker Compose file reference](https://docs.docker.com/reference/compose-file/)
- [Docker bridge networking](https://docs.docker.com/engine/network/drivers/bridge/)
- [Docker volumes](https://docs.docker.com/engine/storage/volumes/)
- [Secrets in Docker Compose](https://docs.docker.com/compose/how-tos/use-secrets/)
- [NGINX HTTPS configuration](https://nginx.org/en/docs/http/configuring_https_servers.html)
- [NGINX FastCGI module](https://nginx.org/en/docs/http/ngx_http_fastcgi_module.html)
- [PHP-FPM documentation](https://www.php.net/manual/en/install.fpm.php)
- [MariaDB `mariadb-install-db`](https://mariadb.com/docs/server/clients-and-utilities/deployment-tools/mariadb-install-db)
- [WordPress WP-CLI handbook](https://make.wordpress.org/cli/handbook/)
- [GNU Make manual](https://www.gnu.org/software/make/manual/)
- [OpenSSL `rand`](https://docs.openssl.org/3.0/man1/openssl-rand/)

### AI usage

AI tools were used as an interactive tutor and reviewer to:

- explain Docker, Linux administration, TLS, networking, volumes, secrets, Make, and the interaction between the three services;
- compare implementation choices with the subject and official documentation;
- propose initial versions of Dockerfiles, configuration files, entrypoint scripts, Compose declarations, Makefile rules, and documentation;
- interpret command output and help diagnose installation, MariaDB authentication, PHP-FPM configuration, NGINX TLS, and Makefile dependency issues;
- design verification procedures for clean initialization, secret handling, networking, TLS versions, container recreation, and volume persistence;
- review wording and organization in the required documentation.

Every file was manually reviewed and entered in the virtual machine. Commands were executed and their actual output was checked before the corresponding changes were committed. AI suggestions were corrected whenever testing or the subject showed a mismatch; no generated result was accepted without verification.
