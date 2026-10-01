FROM debian:bookworm-slim

RUN apt-get update \
	&& DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
		ca-certificates \
		nginx \
		openssl \
	&& rm -rf /var/lib/apt/lists/* \
	&& grep -Fq 'ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;' /etc/nginx/nginx.conf \
	&& sed -i \
		's/ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;/ssl_protocols TLSv1.2 TLSv1.3;/' \
		/etc/nginx/nginx.conf \
	&& rm -f /etc/nginx/sites-enabled/default \
	&& ln -sf /dev/stdout /var/log/nginx/access.log \
	&& ln -sf /dev/stderr /var/log/nginx/error.log

COPY conf/inception.conf.template /etc/nginx/templates/inception.conf.template
COPY tools/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod 755 /usr/local/bin/docker-entrypoint.sh

EXPOSE 443

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
