#!/bin/sh

set -eu

WORDPRESS_SOURCE="/usr/src/wordpress"
WORDPRESS_ROOT="/var/www/html"
FILES_MARKER="$WORDPRESS_ROOT/.inception_files_ready"
CONFIG_FILE="$WORDPRESS_ROOT/wp-config.php"
CONFIG_TEMP="$WORDPRESS_ROOT/wp-config.php.tmp"

DB_PASSWORD_FILE="/run/secrets/db_password"
ADMIN_PASSWORD_FILE="/run/secrets/wp_admin_password"
USER_PASSWORD_FILE="/run/secrets/wp_user_password"

require_value()
{
    name="$1"
    value="$2"

    if [ -z "$value" ]; then
        echo "Error: $name is empty or undefined." >&2
        exit 1
    fi
}

require_secret()
{
    file="$1"

    if [ ! -s "$file" ]; then
        echo "Error: required secret $file is missing or empty." >&2
        exit 1
    fi
}

require_value "DOMAIN_NAME" "${DOMAIN_NAME:-}"
require_value "MYSQL_HOST" "${MYSQL_HOST:-}"
require_value "MYSQL_DATABASE" "${MYSQL_DATABASE:-}"
require_value "MYSQL_USER" "${MYSQL_USER:-}"
require_value "WORDPRESS_TITLE" "${WORDPRESS_TITLE:-}"
require_value "WORDPRESS_ADMIN_USER" "${WORDPRESS_ADMIN_USER:-}"
require_value "WORDPRESS_ADMIN_EMAIL" "${WORDPRESS_ADMIN_EMAIL:-}"
require_value "WORDPRESS_SECOND_USER" "${WORDPRESS_SECOND_USER:-}"
require_value "WORDPRESS_SECOND_USER_EMAIL" "${WORDPRESS_SECOND_USER_EMAIL:-}"

case "$WORDPRESS_ADMIN_USER" in
    *[Aa][Dd][Mm][Ii][Nn]*)
        echo "Error: the WordPress administrator username contains a prohibited form of admin." >&2
        exit 1
        ;;
esac

if [ "$WORDPRESS_ADMIN_USER" = "$WORDPRESS_SECOND_USER" ]; then
    echo "Error: the two WordPress usernames must be different." >&2
    exit 1
fi

require_secret "$DB_PASSWORD_FILE"
require_secret "$ADMIN_PASSWORD_FILE"
require_secret "$USER_PASSWORD_FILE"

if [ ! -f "$WORDPRESS_SOURCE/wp-includes/version.php" ]; then
    echo "Error: the WordPress source files are missing from the image." >&2
    exit 1
fi

mkdir -p "$WORDPRESS_ROOT" /run/php

if [ ! -f "$FILES_MARKER" ]; then
    echo "Copying WordPress files into the persistent volume."
    cp -a "$WORDPRESS_SOURCE/." "$WORDPRESS_ROOT/"
    touch "$FILES_MARKER"
fi

chown -R www-data:www-data "$WORDPRESS_ROOT"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Creating the WordPress configuration."

    rm -f "$CONFIG_TEMP"
    trap 'rm -f "$CONFIG_TEMP"' 0 HUP INT TERM

    if ! /usr/sbin/gosu www-data /usr/local/bin/wp config create \
        --path="$WORDPRESS_ROOT" \
        --config-file="$CONFIG_TEMP" \
        --dbname="$MYSQL_DATABASE" \
        --dbuser="$MYSQL_USER" \
        --dbhost="${MYSQL_HOST}:3306" \
        --dbcharset=utf8mb4 \
        --skip-check \
        --skip-salts \
        --prompt=dbpass \
        < "$DB_PASSWORD_FILE" \
        >/dev/null 2>&1
    then
        echo "Error: unable to create the WordPress configuration." >&2
        exit 1
    fi

    for key in \
        AUTH_KEY \
        SECURE_AUTH_KEY \
        LOGGED_IN_KEY \
        NONCE_KEY \
        AUTH_SALT \
        SECURE_AUTH_SALT \
        LOGGED_IN_SALT \
        NONCE_SALT
    do
        salt="$(/usr/bin/php -r 'echo bin2hex(random_bytes(32));')"

        if ! /usr/sbin/gosu www-data /usr/local/bin/wp config set \
            "$key" \
            "$salt" \
            --type=constant \
            --config-file="$CONFIG_TEMP" \
            --path="$WORDPRESS_ROOT" \
            >/dev/null 2>&1
        then
            unset salt
            echo "Error: unable to add WordPress security keys." >&2
            exit 1
        fi
    done

    unset salt

    mv "$CONFIG_TEMP" "$CONFIG_FILE"
fi

chown www-data:www-data "$CONFIG_FILE"
chmod 640 "$CONFIG_FILE"

echo "Waiting for MariaDB."

attempt=1

while ! /usr/bin/php -r '
    mysqli_report(MYSQLI_REPORT_OFF);

    $password = trim(file_get_contents("/run/secrets/db_password"));

    $connection = @new mysqli(
        getenv("MYSQL_HOST"),
        getenv("MYSQL_USER"),
        $password,
        getenv("MYSQL_DATABASE"),
        3306
    );

    exit($connection->connect_errno === 0 ? 0 : 1);
'
do
    if [ "$attempt" -ge 30 ]; then
        echo "Error: MariaDB did not become available after 30 attempts." >&2
        exit 1
    fi

    echo "MariaDB is not ready yet: attempt $attempt of 30."
    sleep 2
    attempt=$((attempt + 1))
done

echo "MariaDB is available."

if ! /usr/sbin/gosu www-data /usr/local/bin/wp core is-installed \
    --url="https://${DOMAIN_NAME}" \
    --path="$WORDPRESS_ROOT" \
    >/dev/null 2>&1
then
    echo "Installing WordPress."

    if ! /usr/sbin/gosu www-data /usr/local/bin/wp core install \
        --path="$WORDPRESS_ROOT" \
        --url="https://${DOMAIN_NAME}" \
        --title="$WORDPRESS_TITLE" \
        --admin_user="$WORDPRESS_ADMIN_USER" \
        --admin_email="$WORDPRESS_ADMIN_EMAIL" \
        --skip-email \
        --prompt=admin_password \
        < "$ADMIN_PASSWORD_FILE" \
        >/dev/null 2>&1
    then
        echo "Error: unable to install WordPress." >&2
        exit 1
    fi
fi

if ! /usr/sbin/gosu www-data /usr/local/bin/wp user get \
    "$WORDPRESS_SECOND_USER" \
    --url="https://${DOMAIN_NAME}" \
    --path="$WORDPRESS_ROOT" \
    --field=ID \
    >/dev/null 2>&1
then
    echo "Creating the second WordPress user."

    if ! /usr/sbin/gosu www-data /usr/local/bin/wp user create \
        "$WORDPRESS_SECOND_USER" \
        "$WORDPRESS_SECOND_USER_EMAIL" \
        --url="https://${DOMAIN_NAME}" \
        --path="$WORDPRESS_ROOT" \
        --role=editor \
        --prompt=user_pass \
        < "$USER_PASSWORD_FILE" \
        >/dev/null 2>&1
    then
        echo "Error: unable to create the second WordPress user." >&2
        exit 1
    fi
fi

echo "Starting PHP-FPM."

exec "$@"
