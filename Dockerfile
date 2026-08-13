ARG BASE_IMAGE=b4f-rockynode:10
FROM ${BASE_IMAGE}

# Entrypoint needs root (postgres init, nginx). Base defaults to USER node.
USER root

LABEL org.opencontainers.image.title="zephyr"
LABEL org.opencontainers.image.version="1.0"

ENV LANG=zh_CN.UTF-8 \
    LC_ALL=zh_CN.UTF-8 \
    JWT_ACCESS_SECRET=zephyr-prod-access-secret-change-me \
    JWT_REFRESH_SECRET=zephyr-prod-refresh-secret-change-me \
    PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright

RUN mkdir -p \
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
      /opt/ms-playwright \
    && chown -R postgres:postgres \
      /var/lib/pgsql /var/lib/zephyr /var/log/postgresql /var/run/postgresql \
    && chown node:node /opt/ms-playwright

# --- deps layer: host-prepared node_modules (cached while lockfile unchanged) ---
COPY app/package.json app/pnpm-lock.yaml /app/
COPY app/node_modules /app/node_modules
COPY e2e /opt/zephyr-e2e
COPY ms-playwright /opt/ms-playwright
COPY features.env /tmp/zephyr-features.env
COPY entrypoint.sh /entrypoint.sh
COPY source.d /opt/zephyr/source.d
COPY nginx.conf /etc/nginx/nginx.conf
COPY zephyr-pg-backup /usr/local/bin/zephyr-pg-backup

WORKDIR /app

# Host-copied node_modules keep a host pnpm storeDir; do not `pnpm rebuild`.
# argon2 ships linux glibc prebuilds — just verify require() works.
RUN chmod +x /entrypoint.sh /usr/local/bin/zephyr-pg-backup \
    && chown -R node:node /app /opt/zephyr-e2e \
    && export PRISMA_CLI_BINARY_TARGETS=rhel-openssl-3.0.x \
    && printf '%s\n' "store-dir=/var/cache/pnpm/store" > /app/.npmrc \
    && chown node:node /app/.npmrc \
    && echo "zephyr: verify argon2 (prebuilt .node; no pnpm rebuild — host store path mismatch)" \
    && runuser -u node -- env HOME=/home/node \
         bash -lc 'node -e "require(\"argon2\")"' \
    && if [ -f /opt/zephyr-e2e/package.json ]; then \
         dnf install -y --setopt=install_weak_deps=False \
           alsa-lib atk at-spi2-atk cairo cups-libs dbus-libs \
           gtk3 libX11 libXcomposite libXdamage libXext libXfixes \
           libXrandr libxcb libxkbcommon mesa-libgbm nss nspr pango \
           libatomic \
         && dnf clean all \
         && if [ ! -d /opt/zephyr-e2e/node_modules ]; then \
              echo "zephyr: ERROR e2e packaged without node_modules — re-run prepare-context -e" >&2; \
              exit 1; \
            fi \
         && if [ -n "$(find /opt/ms-playwright -type f \( -name chrome -o -name chrome-headless-shell -o -name chromium \) 2>/dev/null | head -1)" ]; then \
              echo "zephyr: Chromium reused from build context (host Playwright cache)"; \
            else \
              echo "zephyr: Chromium missing in context — downloading inside image build…"; \
              runuser -u node -- env HOME=/home/node \
                PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright \
                bash -lc 'cd /opt/zephyr-e2e && pnpm exec playwright install chromium'; \
            fi \
         && test -f /opt/zephyr-e2e/node_modules/@playwright/test/package.json \
         && test -n "$(find /opt/ms-playwright -type f \( -name chrome -o -name chrome-headless-shell -o -name chromium \) 2>/dev/null | head -1)"; \
       else \
         echo "zephyr: e2e module omitted in this image"; \
       fi \
    && test -f node_modules/fastify/package.json \
    && test -f node_modules/argon2/package.json \
    && test -f node_modules/decimal.js/package.json

# --- app payload (changes often; does not re-copy node_modules) ---
COPY app/backend /app/backend
COPY app/prisma /app/prisma
COPY app/prisma-generated /app/prisma-generated
COPY web /var/www/zephyr
COPY mobile-www /var/www/mobile

RUN mkdir -p node_modules/.prisma \
    && rm -rf node_modules/.prisma/client \
    && cp -a prisma-generated node_modules/.prisma/client \
    && for d in node_modules/.pnpm/@prisma+client@*/node_modules; do \
         mkdir -p "$d/.prisma"; \
         rm -rf "$d/.prisma/client"; \
         cp -a prisma-generated "$d/.prisma/client"; \
       done \
    && rm -rf prisma-generated \
    && chown -R node:node /app /opt/zephyr-e2e /opt/ms-playwright /var/cache/pnpm /opt/minimal \
    && test -f node_modules/.prisma/client/libquery_engine-rhel-openssl-3.0.x.so.node \
    && test -f node_modules/.pnpm/@prisma+client@*/node_modules/.prisma/client/index.js \
    && test -f /app/prisma/src/createId.ts \
    && rm -f /tmp/zephyr-features.env

ENV PGDATA=/var/lib/pgsql/data/pgdata \
    BACKUP_ROOT=/var/lib/zephyr \
    PORT=8080 \
    ZEPHYR_DATA_DIR=/home/data/project/zephyr \
    ZEPHYR_UPLOAD_DIR=/home/data/project/zephyr/upload \
    ZEPHYR_CACHE_DIR=/home/data/project/zephyr/cache \
    ZEPHYR_LOG_DIR=/home/data/project/zephyr/log/backend \
    PNPM_STORE_DIR=/var/cache/pnpm/store \
    PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

EXPOSE 80 443 8080 8443 8081 5990

VOLUME [ \
  "/home/data/project/zephyr", \
  "/var/lib/pgsql/data", \
  "/var/lib/zephyr", \
  "/var/log/nginx", \
  "/var/log/postgresql" \
]

ENTRYPOINT ["/entrypoint.sh"]
CMD ["zephyr"]
