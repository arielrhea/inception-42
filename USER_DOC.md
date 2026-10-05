# Inception User Guide

## Services provided

The stack provides a WordPress website through three Docker services:

- **NGINX** is the only public entry point. It accepts HTTPS connections on port 443 using TLS 1.2 or TLS 1.3.
- **WordPress with PHP-FPM** generates the website and provides the administration panel. It is reachable only by NGINX through the private Docker network.
- **MariaDB** stores WordPress content, settings, and user data. It is reachable only by WordPress through the private Docker network.

The website files and database survive ordinary container removal because they are stored in the `wordpress_data` and `mariadb_data` named volumes.

## Initial setup and startup

Run every project command from the repository root:

```bash
cd /home/arhea/inception
```

The local domain must resolve to the virtual machine. Check it with:

```bash
getent hosts arhea.42.fr
```

If no address is returned, add the local mapping once:

```bash
grep -q 'arhea\.42\.fr' /etc/hosts || \
    echo '127.0.0.1 arhea.42.fr' | \
    sudo tee -a /etc/hosts
```

Build the images and start the complete stack with:

```bash
make
```

On a fresh clone, this command also:

1. copies `srcs/.env.example` to the Git-ignored `srcs/.env`;
2. generates any missing password files inside the Git-ignored `secrets/` directory;
3. validates the Docker and Compose configuration;
4. builds the three custom images;
5. starts all three containers in the background.

Existing `srcs/.env` and secret files are preserved.

## Accessing WordPress

Open the website at:

```text
https://arhea.42.fr
```

Open the administration panel at:

```text
https://arhea.42.fr/wp-admin/
```

The TLS certificate is self-signed for this local project. A browser warning is therefore expected. Confirm that the certificate is issued for `arhea.42.fr` before accepting the warning.

The administrator username is configured as `WORDPRESS_ADMIN_USER` in `srcs/.env`. Its default value is:

```text
arhea_owner
```

The administrator password is stored locally in:

```text
secrets/wp_admin_password.txt
```

Display it only on a trusted terminal when it is needed for login:

```bash
cat secrets/wp_admin_password.txt
```

## Stopping and restarting the project

Stop the containers while keeping them available for a later start:

```bash
make stop
```

Start the same stopped containers again:

```bash
make start
```

Restart the running services:

```bash
make restart
```

Remove the containers and project network while preserving the website and database volumes:

```bash
make down
```

Build again if necessary and recreate the containers from the persistent data:

```bash
make up
```

## Credentials

Non-confidential configuration is kept in the local `srcs/.env` file. Passwords are kept in separate local files:

| File | Purpose |
|---|---|
| `secrets/db_root_password.txt` | MariaDB root password. |
| `secrets/db_password.txt` | Password used by WordPress to connect to MariaDB. |
| `secrets/wp_admin_password.txt` | WordPress administrator password. |
| `secrets/wp_user_password.txt` | Password for the second WordPress user. |

`srcs/.env` and the complete `secrets/` directory are ignored by Git. Never add their real contents to a commit, issue, message, screenshot, or shared log.

Check their permissions without printing their contents:

```bash
stat --format='%a %n' \
    secrets \
    srcs/.env \
    secrets/*.txt
```

The expected permissions are `700` for `secrets/` and `600` for `srcs/.env` and each secret file.

Changing a secret file does not automatically change a password already stored inside MariaDB or WordPress. Replacing only the file can therefore break authentication.

For a complete credential reset when the existing website data may be deleted, run:

```bash
make fclean

(
    umask 077
    openssl rand -hex 24 > secrets/db_root_password.txt
    openssl rand -hex 24 > secrets/db_password.txt
    openssl rand -hex 24 > secrets/wp_admin_password.txt
    openssl rand -hex 24 > secrets/wp_user_password.txt
)

make
```

This procedure permanently deletes and recreates both persistent volumes. Do not use it when existing website or database content must be preserved. Preserving the data requires coordinated password changes inside WordPress and MariaDB before replacing the corresponding local secret files.

## Checking service status

Display the current service state with:

```bash
make ps
```

All three services—`nginx`, `wordpress`, and `mariadb`—should show an `Up` or `running` state. NGINX must be the only service with a host port published, using port 443.

Test the HTTPS response from the virtual machine with:

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

The expected result is:

```text
HTTP status: 200
```

`--insecure` is used here only because the local certificate is self-signed. The `--resolve` option sends this test directly to the local virtual machine without depending on external DNS.

Follow the service logs with:

```bash
make logs
```

Press `Ctrl+C` to stop following the logs; this does not stop the containers.

## Destructive cleanup

The following command removes the project containers, images, network, and both persistent volumes:

```bash
make fclean
```

The following command performs the same destructive cleanup and then rebuilds the complete stack:

```bash
make re
```

Both commands permanently delete the current WordPress website files and MariaDB database. Local `srcs/.env` and `secrets/` files remain available for the next initialization.
