#!/bin/sh

set -eu

TEMPLATE_FILE="/etc/nginx/templates/inception.conf.template"
CONFIG_FILE="/etc/nginx/conf.d/inception.conf"
SSL_DIR="/etc/nginx/ssl"
CERT_FILE="$SSL_DIR/inception.crt"
KEY_FILE="$SSL_DIR/inception.key"

case "${DOMAIN_NAME:-}" in
	""|.*|*.|*..*|*[!A-Za-z0-9.-]*)
		echo "ERROR: DOMAIN_NAME is missing or invalid" >&2
		exit 1
		;;
esac

mkdir -p "$SSL_DIR"

sed "s/__DOMAIN_NAME__/$DOMAIN_NAME/g" \
	"$TEMPLATE_FILE" > "$CONFIG_FILE"

if [ ! -s "$CERT_FILE" ] || [ ! -s "$KEY_FILE" ]; then
	(
		umask 077
		openssl req \
			-x509 \
			-nodes \
			-newkey rsa:2048 \
			-sha256 \
			-days 365 \
			-keyout "$KEY_FILE" \
			-out "$CERT_FILE" \
			-subj "/C=ES/O=42/OU=Inception/CN=$DOMAIN_NAME" \
			-addext "subjectAltName=DNS:$DOMAIN_NAME"
	)

	chmod 600 "$KEY_FILE"
	chmod 644 "$CERT_FILE"
fi

nginx -t

exec "$@"
