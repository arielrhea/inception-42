FROM debian:bookworm-slim

ARG WORDPRESS_VERSION=7.1.2
ARG WORDPRESS_SHA1=761b8101538f0631a0bfc4fba7bc4abeea92f81c
ARG WP_CLI_VERSION=2.12.0
ARG WP_CLI_SHA512=be928f6b8ca1e8dfb9d2f4b75a13aa4aee0896f8a9a0a1c45cd5d2c98605e6172e6d014dda2e27f88c98befc16c040cbb2bd1bfa121510ea5cdf5f6a30fe8832

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gosu \
        php8.2-cli \
        php8.2-fpm \
        php8.2-curl \
        php8.2-gd \
        php8.2-mbstring \
        php8.2-mysql \
        php8.2-xml \
        php8.2-zip \
        tar \
    && rm -rf /var/lib/apt/lists/*

RUN curl --fail --location \
        --output /tmp/wordpress.tar.gz \
        "https://wordpress.org/wordpress-${WORDPRESS_VERSION}.tar.gz" \
    && printf '%s  %s\n' "$WORDPRESS_SHA1" /tmp/wordpress.tar.gz \
        | sha1sum --check - \
    && tar --extract --gzip \
        --file /tmp/wordpress.tar.gz \
        --directory /usr/src \
    && chown --recursive www-data:www-data /usr/src/wordpress \
    && rm /tmp/wordpress.tar.gz

RUN curl --fail --location \
        --output /usr/local/bin/wp \
        "https://github.com/wp-cli/wp-cli/releases/download/v${WP_CLI_VERSION}/wp-cli-${WP_CLI_VERSION}.phar" \
    && printf '%s  %s\n' "$WP_CLI_SHA512" /usr/local/bin/wp \
        | sha512sum --check - \
    && chmod 755 /usr/local/bin/wp

COPY conf/www.conf /etc/php/8.2/fpm/pool.d/www.conf
COPY tools/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod 755 /usr/local/bin/docker-entrypoint.sh

EXPOSE 9000

WORKDIR /var/www/html

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["php-fpm8.2", "--nodaemonize"]
