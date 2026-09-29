#!/bin/sh

set -eu

DATA_DIR="/var/lib/mysql"
RUN_DIR="/run/mysqld"
SOCKET="$RUN_DIR/mysqld.sock"
INIT_MARKER="$DATA_DIR/.inception_initialized"

ROOT_PASSWORD_FILE="/run/secrets/db_root_password"
USER_PASSWORD_FILE="/run/secrets/db_password"

unset MYSQL_HOST
unset MYSQL_TCP_PORT

mkdir -p "$DATA_DIR" "$RUN_DIR"
chown mysql:mysql "$DATA_DIR" "$RUN_DIR"

if [ ! -f "$INIT_MARKER" ]; then
    if [ -d "$DATA_DIR/mysql" ]; then
        echo "Error: partial MariaDB initialization detected." >&2
        exit 1
    fi

    case "${MYSQL_DATABASE:-}" in
        ""|*[!A-Za-z0-9_]*)
            echo "Error: MYSQL_DATABASE is missing or invalid." >&2
            exit 1
            ;;
    esac

    case "${MYSQL_USER:-}" in
        ""|*[!A-Za-z0-9_]*)
            echo "Error: MYSQL_USER is missing or invalid." >&2
            exit 1
            ;;
    esac

    if [ ! -s "$ROOT_PASSWORD_FILE" ] || [ ! -s "$USER_PASSWORD_FILE" ]; then
        echo "Error: MariaDB secret files are missing or empty." >&2
        exit 1
    fi

    DB_ROOT_PASSWORD="$(cat "$ROOT_PASSWORD_FILE")"
    DB_PASSWORD="$(cat "$USER_PASSWORD_FILE")"

    case "$DB_ROOT_PASSWORD" in
        ""|*[!0-9a-f]*)
            echo "Error: root password must be non-empty hexadecimal text." >&2
            exit 1
            ;;
    esac

    case "$DB_PASSWORD" in
        ""|*[!0-9a-f]*)
            echo "Error: database password must be non-empty hexadecimal text." >&2
            exit 1
            ;;
    esac

    mariadb-install-db \
        --user=mysql \
        --datadir="$DATA_DIR" \
        --auth-root-authentication-method=socket \
        --auth-root-socket-user=mysql \
        --skip-test-db

    mariadbd \
        --user=mysql \
        --datadir="$DATA_DIR" \
        --skip-networking \
        --socket="$SOCKET" &

    TEMP_PID="$!"

    stop_temporary_server()
    {
        if kill -0 "$TEMP_PID" 2>/dev/null; then
            kill "$TEMP_PID" 2>/dev/null || true
            wait "$TEMP_PID" 2>/dev/null || true
        fi
    }

    trap stop_temporary_server 0 HUP INT TERM

    attempt=0

    until mariadb-admin \
        --protocol=socket \
        --host=localhost \
        --socket="$SOCKET" \
        --user=root \
        ping --silent >/dev/null 2>&1
    do
        attempt=$((attempt + 1))

        if [ "$attempt" -ge 30 ]; then
            echo "Error: temporary MariaDB server did not become ready." >&2
            exit 1
        fi

        sleep 1
    done

    mariadb \
        --protocol=socket \
        --host=localhost \
        --socket="$SOCKET" \
        --user=root <<EOF
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
ALTER USER '${MYSQL_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
ALTER USER 'root'@'localhost'
    IDENTIFIED VIA unix_socket
    OR mysql_native_password USING PASSWORD('${DB_ROOT_PASSWORD}');
GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION;
ALTER USER 'mysql'@'localhost' IDENTIFIED VIA unix_socket;
GRANT ALL PRIVILEGES ON *.* TO 'mysql'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SHUTDOWN;
EOF

    wait "$TEMP_PID"

    touch "$INIT_MARKER"
    chown mysql:mysql "$INIT_MARKER"

    unset DB_ROOT_PASSWORD DB_PASSWORD
fi

exec mariadbd \
    --user=mysql \
    --datadir="$DATA_DIR"
