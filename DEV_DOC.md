# Inception Developer Guide

## Architecture

Inception runs inside a Linux virtual machine and uses Docker Compose to build and operate three custom service images:

```text
Client
  |
  | HTTPS, host port 443
  v
NGINX
  |
  | FastCGI, Docker network port 9000
  v
WordPress + PHP-FPM
  |
  | MariaDB protocol, Docker network port 3306
  v
MariaDB
```

| Service | Image | Main process | Host exposure | Persistent path |
|---|---|---|---|---|
| `nginx` | `nginx:inception` | `nginx -g 'daemon off;'` | HTTPS on port 443 | Read-only `/var/www/html` |
| `wordpress` | `wordpress:inception` | `php-fpm8.2 --nodaemonize` | None; internal port 9000 | `/var/www/html` |
| `mariadb` | `mariadb:inception` | `mariadbd` | None; internal port 3306 | `/var/lib/mysql` |

All three images use `debian:bookworm-slim` as their base. The services communicate through the dedicated `inception` bridge network. NGINX is the only service that publishes a port on the virtual machine.

## Repository layout

```text
.
├── .gitignore
├── Makefile
├── README.md
├── USER_DOC.md
├── DEV_DOC.md
├── secrets/                         # Local and ignored by Git
│   ├── db_root_password.txt
│   ├── db_password.txt
│   ├── wp_admin_password.txt
│   └── wp_user_password.txt
└── srcs
    ├── .env                         # Local and ignored by Git
    ├── .env.example                 # Non-confidential tracked template
    ├── docker-compose.yml
    └── requirements
        ├── mariadb
        │   ├── Dockerfile
        │   ├── conf/60-inception.cnf
        │   └── tools/docker-entrypoint.sh
        ├── wordpress
        │   ├── Dockerfile
        │   ├── conf/www.conf
        │   └── tools/docker-entrypoint.sh
        └── nginx
            ├── Dockerfile
            ├── conf/inception.conf.template
            └── tools/docker-entrypoint.sh
```

## Host prerequisites

Use a Debian 12 virtual machine with at least:

- Docker Engine;
- the Docker Compose plugin invoked as `docker compose`;
- Git;
- GNU Make;
- OpenSSL;
- `curl` and trusted CA certificates;
- a user authorized to communicate with the Docker daemon.

Install the ordinary host tools with:

```bash
sudo apt update
sudo apt install -y ca-certificates curl git make openssl
```

Install Docker Engine and the Compose plugin from Docker's official Debian repository. The current official procedure should be checked at <https://docs.docker.com/engine/install/debian/>. A standard Debian 12 installation uses:

```bash
sudo install -m 0755 -d /etc/apt/keyrings

sudo curl \
    --fail \
    --silent \
    --show-error \
    --location \
    https://download.docker.com/linux/debian/gpg \
    --output /etc/apt/keyrings/docker.asc

sudo chmod a+r /etc/apt/keyrings/docker.asc

. /etc/os-release

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $VERSION_CODENAME stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

sudo apt update

sudo apt install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin
```

Allow the current user to use the Docker socket:

```bash
sudo usermod -aG docker "$USER"
```

Log out of the virtual machine and log in again so the new group membership takes effect. Then verify the tools and daemon:

```bash
docker --version
docker compose version
docker info >/dev/null
```

None of these commands should require `sudo` after the group change has taken effect.

## Docker data-root configuration

The subject requires persistent project data below `/home/arhea/data`. This project satisfies that requirement by configuring Docker's complete data root there. Perform this step before creating the project volumes.

Create or edit:

```text
/etc/docker/daemon.json
```

For a fresh Docker installation, its content is:

```json
{
  "data-root": "/home/arhea/data"
}
```

If `/etc/docker/daemon.json` already contains settings, add the `data-root` member to the existing JSON object instead of overwriting the other members.

Validate the configuration before restarting Docker:

```bash
sudo dockerd \
    --validate \
    --config-file=/etc/docker/daemon.json
```

The expected result is:

```text
configuration OK
```

Apply it and verify the effective path:

```bash
sudo systemctl restart docker
sudo systemctl is-active docker
docker info --format 'Docker Root Dir: {{.DockerRootDir}}'
```

The expected output includes:

```text
active
Docker Root Dir: /home/arhea/data
```

Changing the Docker data root on a machine that already has images or volumes makes the resources under the previous data root unavailable to the daemon. Configure it before project initialization or migrate existing Docker data deliberately.

## Obtaining and configuring the project

Clone the repository and enter its root directory:

```bash
git clone <repository-url> inception
cd inception
```

Configure local name resolution so the required domain reaches the virtual machine:

```bash
grep -q 'arhea\.42\.fr' /etc/hosts || \
    echo '127.0.0.1 arhea.42.fr' | \
    sudo tee -a /etc/hosts
```

Prepare the local configuration without building containers:

```bash
make prepare
```

On a fresh clone, `make prepare`:

1. checks Docker, Compose, OpenSSL, the Docker daemon, and the configured data root;
2. copies `srcs/.env.example` to `srcs/.env` only when the real file is absent;
3. creates only the password files that are absent;
4. applies mode `700` to `secrets/` and mode `600` to the environment and secret files.

It does not overwrite existing local configuration or passwords.

## Environment configuration

The local `srcs/.env` contains non-confidential deployment settings:

| Variable | Purpose | Project value |
|---|---|---|
| `DOMAIN_NAME` | HTTPS hostname and WordPress URL | `arhea.42.fr` |
| `MYSQL_HOST` | MariaDB Compose service name | `mariadb` |
| `MYSQL_DATABASE` | WordPress database | `wordpress` |
| `MYSQL_USER` | WordPress database account | `wp_user` |
| `WORDPRESS_TITLE` | Initial site title | `Inception` |
| `WORDPRESS_ADMIN_USER` | Administrator login | `arhea_owner` |
| `WORDPRESS_ADMIN_EMAIL` | Administrator email metadata | `owner@arhea.42.fr` |
| `WORDPRESS_SECOND_USER` | Second WordPress login | `arhea_editor` |
| `WORDPRESS_SECOND_USER_EMAIL` | Second user's email metadata | `editor@arhea.42.fr` |

The local email values are WordPress metadata and do not need to correspond to real mailboxes for this project.

Edit `srcs/.env` before the first initialization when deployment-specific values must change. Changing initialization values after the volumes contain data does not automatically rename existing database or WordPress accounts.

## Secrets

The `secrets/` directory contains four independent password files:

| Secret | Available to | Purpose |
|---|---|---|
| `db_root_password.txt` | MariaDB | MariaDB root password |
| `db_password.txt` | MariaDB and WordPress | Shared application database password |
| `wp_admin_password.txt` | WordPress | Initial administrator password |
| `wp_user_password.txt` | WordPress | Initial second-user password |

Compose mounts only the required files into each selected container under `/run/secrets/`. NGINX receives no password secret.

Verify that Git ignores all private local files:

```bash
git check-ignore -v \
    srcs/.env \
    secrets/db_root_password.txt \
    secrets/db_password.txt \
    secrets/wp_admin_password.txt \
    secrets/wp_user_password.txt
```

Verify that none is already tracked:

```bash
if git ls-files | grep -E '^(secrets/|srcs/\.env$)'
then
    echo 'ERROR: Git is tracking a private file'
else
    echo 'Git private-file tracking: OK'
fi
```

Do not replace a secret file while initialized volumes are in use. The applications store corresponding credentials internally, so changing only the file creates an authentication mismatch. Use a coordinated application-level password change or perform the destructive full reset documented in `USER_DOC.md`.

## Build and launch

The supported entry point is the root Makefile:

```bash
make
```

Its dependency chain is:

```text
all -> up -> config -> prepare -> check
```

Therefore a normal `make` validates the host and local files, validates the resolved Compose configuration, builds the images, and starts the stack in detached mode.

The equivalent lower-level sequence is:

```bash
make prepare

docker compose \
    -f srcs/docker-compose.yml \
    config --quiet

docker compose \
    -f srcs/docker-compose.yml \
    build

docker compose \
    -f srcs/docker-compose.yml \
    up --detach
```

Use the Makefile for normal operation because direct Compose commands do not create missing `.env` or secret files and do not validate the Docker data root.

## Makefile lifecycle commands

| Command | Effect on containers | Effect on volumes |
|---|---|---|
| `make` or `make all` | Build and start | Preserve |
| `make config` | Validate configuration only | Preserve |
| `make build` | Build images only | Preserve |
| `make up` | Build and create or recreate | Preserve |
| `make stop` | Stop without removing | Preserve |
| `make start` | Start existing stopped containers | Preserve |
| `make restart` | Restart existing containers | Preserve |
| `make down` or `make clean` | Remove containers and project network | Preserve |
| `make logs` | Follow logs until `Ctrl+C` | Preserve |
| `make ps` | Show current service state | Preserve |
| `make fclean` | Remove containers, images, and network | **Delete** |
| `make re` | Perform `fclean`, then build and start | **Delete and recreate** |

`make fclean` and `make re` are destructive because they remove both named volumes.

## Direct container management

Display the resolved Compose model:

```bash
docker compose \
    -f srcs/docker-compose.yml \
    config
```

Display container state and published ports:

```bash
docker compose \
    -f srcs/docker-compose.yml \
    ps
```

Show the last 100 log lines for one service:

```bash
docker compose \
    -f srcs/docker-compose.yml \
    logs \
    --tail=100 \
    nginx
```

Replace `nginx` with `wordpress` or `mariadb` to inspect another service. Logs must never contain password values or WordPress salts.

Rebuild and recreate one service after changing its Dockerfile, configuration, or entrypoint:

```bash
docker compose \
    -f srcs/docker-compose.yml \
    build nginx

docker compose \
    -f srcs/docker-compose.yml \
    up \
    --detach \
    --no-deps \
    nginx
```

Use the appropriate service name in place of `nginx`. Omit `--no-deps` when its dependencies also need to be started or recreated.

## Service verification

Validate the active NGINX configuration:

```bash
docker exec nginx nginx -t
```

Validate the PHP-FPM configuration:

```bash
docker exec wordpress php-fpm8.2 --test
```

Check that WordPress is installed:

```bash
docker exec wordpress sh -ec '
    /usr/sbin/gosu www-data /usr/local/bin/wp \
        core is-installed \
        --url="https://$DOMAIN_NAME" \
        --path=/var/www/html
'

echo "WordPress status: $?"
```

The expected status is `0`.

Check the WordPress database account over MariaDB's internal TCP listener:

```bash
docker exec mariadb sh -ec '
    MYSQL_PWD="$(cat /run/secrets/db_password)" \
    mariadb \
        --protocol=tcp \
        --host=127.0.0.1 \
        --port=3306 \
        --user="$MYSQL_USER" \
        --database="$MYSQL_DATABASE" \
        --execute="SELECT DATABASE(), CURRENT_USER();"
'
```

The result must identify the `wordpress` database and the `wp_user` account.

Check the complete public request path:

```bash
curl \
    --insecure \
    --resolve arhea.42.fr:443:127.0.0.1 \
    --silent \
    --show-error \
    --output /dev/null \
    --write-out 'HTTP status: %{http_code}\n' \
    https://arhea.42.fr/
```

The expected status is `200`.

## Network management

Inspect the project network:

```bash
docker network inspect inception
```

The network must use the `bridge` driver and contain `nginx`, `wordpress`, and `mariadb`. Service names provide internal DNS resolution. No `network_mode: host` or legacy container links are used.

Check published ports with:

```bash
docker ps \
    --format 'table {{.Names}}\t{{.Ports}}'
```

Only NGINX must show a host mapping such as `0.0.0.0:443->443/tcp`. WordPress may show internal `9000/tcp`, and MariaDB may show internal `3306/tcp`, but neither may contain a host mapping arrow.

## Volume management and persistence

The Compose project declares exactly two named volumes:

| Volume | Container mount | Stored data |
|---|---|---|
| `mariadb_data` | `/var/lib/mysql` | MariaDB system tables and WordPress database |
| `wordpress_data` | `/var/www/html` | WordPress core, configuration, plugins, themes, and uploads |

WordPress mounts `wordpress_data` read-write. NGINX mounts the same volume read-only at `/var/www/html` so it can serve static files without modifying the site data.

List and inspect them with:

```bash
docker volume ls

docker volume inspect \
    --format 'Name={{.Name}} Mountpoint={{.Mountpoint}}' \
    mariadb_data \
    wordpress_data
```

With the required Docker data root, their host mountpoints are:

```text
/home/arhea/data/volumes/mariadb_data/_data
/home/arhea/data/volumes/wordpress_data/_data
```

The data belongs to the volumes rather than to a particular container. `make down` removes the containers, but the volumes and their contents remain. A later `make` creates new containers that mount the same data.

Do not edit files directly inside Docker's volume directories. MariaDB files in particular require consistent ownership and database state. Use the application, database tools, or a deliberate backup and restore procedure.

The only project commands that remove the volumes are:

```bash
make fclean
make re
```

## Development workflow

After modifying a shell entrypoint, check its syntax before building:

```bash
sh -n srcs/requirements/mariadb/tools/docker-entrypoint.sh
sh -n srcs/requirements/wordpress/tools/docker-entrypoint.sh
sh -n srcs/requirements/nginx/tools/docker-entrypoint.sh
```

An exit status of `0` confirms shell grammar only; it does not prove that the script performs the intended operation.

Validate Compose after changing `srcs/docker-compose.yml` or `srcs/.env`:

```bash
make config
```

Build and test the affected service, then run the integrated HTTPS and service checks described above. Before committing, inspect the staged files and whitespace:

```bash
git status --short --ignored
git diff --cached --name-only
git diff --cached --check
```

Confirm again that no private file is tracked:

```bash
if git ls-files | grep -E '^(secrets/|srcs/\.env$)'
then
    echo 'ERROR: Git is tracking a private file'
else
    echo 'Git private-file tracking: OK'
fi
```

## Clean reconstruction

A clean reconstruction verifies that the repository can initialize empty volumes without relying on old container state. It permanently deletes the current site and database:

```bash
make fclean
make
make ps
```

Then verify HTTPS, WordPress, MariaDB, the network, and both volume mountpoints using the commands in this guide.

For evaluation, perform the final test from a fresh clone of the evaluated commit. The clone contains neither `srcs/.env` nor `secrets/`; the first `make` reconstructs them locally from the tracked template and cryptographically generated values.

## Common failures

### Docker data-root mismatch

If `make` reports that Docker's data root is not `/home/arhea/data`, correct `/etc/docker/daemon.json`, validate it, and restart Docker before continuing.

### Docker socket permission denied

Confirm that the user belongs to the `docker` group:

```bash
id
```

After `sudo usermod -aG docker "$USER"`, log out and back in. Starting a new terminal alone may not refresh the login session.

### Domain does not resolve

Check:

```bash
getent hosts arhea.42.fr
```

The virtual machine must resolve the domain to its local address. The self-signed certificate warning is expected; an HTTP connection on port 80 is not.

### Authentication fails after editing a secret

Restore the secret that matches the initialized data or perform a coordinated password update. For disposable data, use the complete destructive reset documented in `USER_DOC.md`. Repeated container restarts cannot repair mismatched credentials.

### A container repeatedly restarts

Inspect its state and logs:

```bash
docker compose -f srcs/docker-compose.yml ps
docker compose -f srcs/docker-compose.yml logs --tail=100 <service-name>
```

Correct the first explicit initialization or configuration error instead of adding an infinite wait loop.
