ARG BASE_IMAGE=183.131.83.99:1244/b4f-rocky:10
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.title="zephyr"
LABEL org.opencontainers.image.version="1.0"

RUN --mount=type=cache,id=zephyr-dnf,target=/var/cache/dnf,sharing=locked \
    dnf -y --setopt=install_weak_deps=False install \
      ca-certificates xz tar nginx \
      postgresql-server postgresql \
    && dnf -y clean all \
    && rm -f /etc/nginx/conf.d/default.conf \
    && mkdir -p \
      /home/data/project/zephyr/upload \
      /home/data/project/zephyr/cache \
      /home/data/project/zephyr/log/backend \
      /home/data/project/zephyr/log/web \
      /home/data/project/zephyr/log/mobile \
      /var/lib/pgsql/data \
      /var/lib/zephyr/wal \
      /var/lib/zephyr/base \
      /var/log/nginx \
      /var/log/postgresql \
      /var/run/postgresql \
      /var/www/zephyr \
      /var/www/mobile \
      /etc/nginx/certs \
      /app \
    && chown -R postgres:postgres \
      /var/lib/pgsql /var/lib/zephyr /var/log/postgresql /var/run/postgresql

# Context prepared by `make prepare-context` on /tmp (vendor node + app + web)
COPY node /usr/local/node
RUN set -eux; \
    test -x /usr/local/node/bin/node; \
    test -f /usr/local/node/lib/node_modules/npm/bin/npm-cli.js; \
    ln -sfn /usr/local/node/bin/node /usr/local/bin/node; \
    ln -sfn /usr/local/node/bin/npm /usr/local/bin/npm; \
    ln -sfn /usr/local/node/bin/npx /usr/local/bin/npx; \
    if [[ -e /usr/local/node/bin/pnpm ]]; then ln -sfn /usr/local/node/bin/pnpm /usr/local/bin/pnpm; fi; \
    chmod 755 /usr/local/node/bin/node; \
    node -v; npm -v

COPY app /app
COPY web /var/www/zephyr
COPY mobile-www /var/www/mobile
COPY entrypoint.sh /entrypoint.sh
COPY zephyr-pg-backup /usr/local/bin/zephyr-pg-backup
RUN chmod +x /entrypoint.sh /usr/local/bin/zephyr-pg-backup \
    && ln -sfn /app/node_modules/.bin/tsx /usr/local/bin/tsx 2>/dev/null || true \
    && ln -sfn /app/node_modules/.bin/prisma /usr/local/bin/prisma 2>/dev/null || true \
    && if [[ -x /app/node_modules/prisma/build/index.js ]]; then \
         printf '%s\n' '#!/bin/sh' 'exec node /app/node_modules/prisma/build/index.js "$@"' > /usr/local/bin/prisma; \
         chmod +x /usr/local/bin/prisma; \
       fi; \
    if [[ -f /app/node_modules/tsx/dist/cli.mjs ]]; then \
         printf '%s\n' '#!/bin/sh' 'exec node /app/node_modules/tsx/dist/cli.mjs "$@"' > /usr/local/bin/tsx; \
         chmod +x /usr/local/bin/tsx; \
       fi

WORKDIR /app

ENV PGDATA=/var/lib/pgsql/data/pgdata \
    BACKUP_ROOT=/var/lib/zephyr \
    PORT=8080 \
    ZEPHYR_DATA_DIR=/home/data/project/zephyr \
    ZEPHYR_UPLOAD_DIR=/home/data/project/zephyr/upload \
    ZEPHYR_CACHE_DIR=/home/data/project/zephyr/cache \
    ZEPHYR_LOG_DIR=/home/data/project/zephyr/log/backend

EXPOSE 80 443 8080 8443 8081 5432

VOLUME [ \
  "/home/data/project/zephyr", \
  "/var/lib/pgsql/data", \
  "/var/lib/zephyr", \
  "/var/log/nginx", \
  "/var/log/postgresql" \
]

ENTRYPOINT ["/entrypoint.sh"]
CMD ["zephyr"]
