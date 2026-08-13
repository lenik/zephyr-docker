# zephyr image — build / push / pull / compose definitions
# Runtime instance lives in ../i-local (make -C ../i-local up).

SHELL = /bin/bash
.PHONY: all vendor-node prepare-context build build-roles push pull compose compose-medium

REGISTRY ?= 183.131.83.99:1244
IMAGE_NAME ?= zephyr
IMAGE_TAG ?= 1.0
IMAGE = $(IMAGE_NAME):$(IMAGE_TAG)
REMOTE_IMAGE = $(REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG)
BASE_IMAGE ?= $(REGISTRY)/b4f-rocky:10
ROOT = $(CURDIR)
REPO = $(ROOT)/..
CTX = /tmp/zephyr-docker-ctx
VENDOR_NODE = $(ROOT)/vendor/node

BUILD_OPTS = --pull=false --provenance=false --sbom=false

all: build

vendor-node:
	@command -v node >/dev/null || { echo "node not found on host" >&2; exit 1; }
	@NODE_SRC=$$(dirname $$(dirname $$(readlink -f $$(command -v node)))); \
	  echo "vendor node from $$NODE_SRC"; \
	  rm -rf $(VENDOR_NODE); \
	  mkdir -p $(VENDOR_NODE); \
	  rsync -a --delete \
	    --exclude='CHANGELOG.md' --exclude='README.md' --exclude='*.md' \
	    "$$NODE_SRC"/ $(VENDOR_NODE)/; \
	  chmod 755 $(VENDOR_NODE)/bin/node; \
	  $(VENDOR_NODE)/bin/node -v

prepare-context:
	@test -d $(REPO)/web/dist || { echo "missing web/dist — run: pnpm -C web build" >&2; exit 1; }
	@test -d $(REPO)/backend/dist || { echo "missing backend/dist — run: pnpm -C backend build" >&2; exit 1; }
	@test -e $(REPO)/backend/changelog/zh_CN || { echo "missing backend/changelog/zh_CN symlink" >&2; exit 1; }
	@command -v node >/dev/null || { echo "node not found on host" >&2; exit 1; }
	@echo "prisma generate (native + rhel-openssl-3.0.x)…"
	@cd $(REPO) && PRISMA_CLI_BINARY_TARGETS=rhel-openssl-3.0.x pnpm exec prisma generate
	@echo "prepare context at $(CTX)"
	@rm -rf $(CTX)
	@mkdir -p $(CTX)
	@cp $(ROOT)/Dockerfile $(CTX)/Dockerfile
	@cp $(ROOT)/entrypoint.sh $(CTX)/entrypoint.sh
	@cp $(ROOT)/scripts/zephyr-pg-backup $(CTX)/zephyr-pg-backup
	@chmod +x $(CTX)/entrypoint.sh $(CTX)/zephyr-pg-backup
	@NODE_SRC=$$(dirname $$(dirname $$(readlink -f $$(command -v node)))); \
	  echo "copy node from $$NODE_SRC"; \
	  rsync -a --delete --exclude='*.md' "$$NODE_SRC"/ $(CTX)/node/; \
	  chmod 755 $(CTX)/node/bin/node
	@echo "pnpm deploy backend → $(CTX)/app"
	@cd $(REPO) && pnpm --filter zephyr-backend deploy --prod --config.package-import-method=copy $(CTX)/app
	@mkdir -p $(CTX)/app/backend
	@if [[ -d $(CTX)/app/dist ]]; then mv $(CTX)/app/dist $(CTX)/app/backend/dist; fi
	@if [[ -d $(CTX)/app/src ]]; then mv $(CTX)/app/src $(CTX)/app/backend/src; fi
	@rm -rf $(CTX)/app/changelog
	@# Follow symlinks so image gets real debian changelog files (pnpm deploy may keep broken links)
	@mkdir -p $(CTX)/app/backend/changelog
	@rsync -aL $(REPO)/backend/changelog/ $(CTX)/app/backend/changelog/
	@cp -a $(REPO)/prisma $(CTX)/app/prisma
	@ESBUILD=$$(find $(REPO)/node_modules/.pnpm -path '*/esbuild/bin/esbuild' -type f 2>/dev/null | head -1); \
	  test -n "$$ESBUILD"; \
	  "$$ESBUILD" $(REPO)/prisma/seed.ts --bundle --platform=node --format=cjs --packages=external \
	    --outfile=$(CTX)/app/prisma/seed.cjs
	@mkdir -p $(CTX)/app/node_modules/@prisma
	@PRISMA_PKG=$$(find $(REPO)/node_modules/.pnpm -maxdepth 1 -type d -name 'prisma@*' 2>/dev/null | head -1); \
	  if [[ -n "$$PRISMA_PKG" && -d "$$PRISMA_PKG/node_modules/prisma" ]]; then \
	    rsync -aL "$$PRISMA_PKG/node_modules/prisma"/ $(CTX)/app/node_modules/prisma/; \
	  else \
	    rsync -aL $(REPO)/node_modules/prisma/ $(CTX)/app/node_modules/prisma/; \
	  fi
	@TSX_PKG=$$(find $(REPO)/node_modules/.pnpm -maxdepth 1 -type d -name 'tsx@*' 2>/dev/null | head -1); \
	  if [[ -n "$$TSX_PKG" && -d "$$TSX_PKG/node_modules/tsx" ]]; then \
	    rsync -aL "$$TSX_PKG/node_modules/tsx"/ $(CTX)/app/node_modules/tsx/; \
	  else \
	    rsync -aL $(REPO)/node_modules/tsx/ $(CTX)/app/node_modules/tsx/; \
	  fi
	@if [[ -d $(REPO)/node_modules/esbuild ]]; then rsync -aL $(REPO)/node_modules/esbuild/ $(CTX)/app/node_modules/esbuild/; fi
	@PRISMA_CLIENT_PKG=$$(find $(REPO)/node_modules/.pnpm -maxdepth 1 -type d -name '@prisma+client@*' 2>/dev/null | head -1); \
	  test -n "$$PRISMA_CLIENT_PKG"; \
	  rm -rf $(CTX)/app/node_modules/@prisma/client; \
	  rsync -aL "$$PRISMA_CLIENT_PKG/node_modules/@prisma/client"/ $(CTX)/app/node_modules/@prisma/client/
	@PRISMA_GEN=$$(find $(REPO)/node_modules/.pnpm -type d -path '*/@prisma+client@*/node_modules/.prisma/client' 2>/dev/null | head -1); \
	  test -n "$$PRISMA_GEN"; \
	  test -f "$$PRISMA_GEN/libquery_engine-rhel-openssl-3.0.x.so.node"; \
	  mkdir -p $(CTX)/app/node_modules/.prisma; \
	  rsync -aL "$$PRISMA_GEN"/ $(CTX)/app/node_modules/.prisma/client/
	@PRISMA_ENG_ROOT=$$(find $(REPO)/node_modules/.pnpm -maxdepth 1 -type d -name '@prisma+engines@*' 2>/dev/null | head -1); \
	  test -n "$$PRISMA_ENG_ROOT"; \
	  PRISMA_ENG="$$PRISMA_ENG_ROOT/node_modules/@prisma/engines"; \
	  test -f "$$PRISMA_ENG/schema-engine-rhel-openssl-3.0.x"; \
	  for pkg in engines debug engines-version fetch-engine get-platform; do \
	    rsync -aL "$$PRISMA_ENG_ROOT/node_modules/@prisma/$$pkg"/ $(CTX)/app/node_modules/@prisma/$$pkg/; \
	  done; \
	  for d in $(CTX)/app/node_modules/.pnpm/@prisma+engines@*/node_modules/@prisma/engines; do \
	    if [[ -d "$$d" ]]; then rsync -aL "$$PRISMA_ENG"/ "$$d"/; fi; \
	  done
	@for d in $(CTX)/app/node_modules/.pnpm/@prisma+client@*/node_modules; do \
	    if [[ -d "$$d" ]]; then \
	      mkdir -p "$$d/.prisma"; \
	      rsync -aL $(CTX)/app/node_modules/.prisma/client/ "$$d/.prisma/client/"; \
	    fi; \
	  done
	@echo "densify cross-device hardlinks…"
	@python3 $(ROOT)/scripts/densify-hardlinks.py $(CTX)/app $(CTX)/node
	@rsync -a $(REPO)/web/dist/ $(CTX)/web/
	@mkdir -p $(CTX)/mobile-www
	@cp -a $(ROOT)/www/mobile/. $(CTX)/mobile-www/
	@du -sh --apparent-size $(CTX) $(CTX)/node $(CTX)/app $(CTX)/web
	@test -x $(CTX)/node/bin/node
	@test -f $(CTX)/app/backend/dist/server.js
	@test -f $(CTX)/app/backend/changelog/en
	@test -f $(CTX)/app/backend/changelog/zh_CN
	@test -f $(CTX)/app/node_modules/prisma/build/index.js
	@test -f $(CTX)/app/node_modules/@prisma/client/package.json
	@test -f $(CTX)/app/node_modules/@prisma/debug/package.json
	@test -f $(CTX)/app/node_modules/.prisma/client/libquery_engine-rhel-openssl-3.0.x.so.node
	@test -x $(CTX)/app/node_modules/@prisma/engines/schema-engine-rhel-openssl-3.0.x
	@node -e 'const r=require("module").createRequire("/tmp/zephyr-docker-ctx/app/node_modules/prisma/build/index.js"); r("@prisma/engines"); console.log("prisma engines ok")'
	@echo "context ready"

build: prepare-context
	docker build $(BUILD_OPTS) \
		--build-arg BASE_IMAGE=$(BASE_IMAGE) \
		-t $(REMOTE_IMAGE) \
		$(CTX)
	docker tag $(REMOTE_IMAGE) $(IMAGE)

push:
	@docker image inspect $(REMOTE_IMAGE) >/dev/null 2>&1 || $(MAKE) build
	docker push $(REMOTE_IMAGE)

pull:
	@if docker pull localhost:1244/$(IMAGE_NAME):$(IMAGE_TAG) 2>/dev/null; then \
	  docker tag localhost:1244/$(IMAGE_NAME):$(IMAGE_TAG) $(IMAGE); \
	  docker tag localhost:1244/$(IMAGE_NAME):$(IMAGE_TAG) $(REMOTE_IMAGE); \
	else \
	  docker pull $(REMOTE_IMAGE); \
	  docker tag $(REMOTE_IMAGE) $(IMAGE); \
	fi

# Thin image layer: role-aware entrypoint (backend|web|zephyr) on zephyr:1.0.
build-roles:
	@docker image inspect zephyr:$(IMAGE_TAG) >/dev/null 2>&1 \
	  || docker image inspect $(REMOTE_IMAGE) >/dev/null 2>&1 \
	  || $(MAKE) pull
	@docker image inspect zephyr:$(IMAGE_TAG) >/dev/null 2>&1 \
	  || docker tag $(REMOTE_IMAGE) zephyr:$(IMAGE_TAG)
	docker build $(BUILD_OPTS) \
	  --build-arg BASE_IMAGE=zephyr:$(IMAGE_TAG) \
	  -f $(ROOT)/Dockerfile.roles \
	  -t zephyr:$(IMAGE_TAG) \
	  -t $(REMOTE_IMAGE)-roles \
	  $(ROOT)

# Render merged compose (defaults instance to ../i-local).
INSTANCE ?= $(ROOT)/../i-local
OVERLAY ?= host
compose:
	@test -d $(INSTANCE) || { echo "missing instance dir $(INSTANCE)" >&2; exit 1; }
	ZEPHYR_DOCKER=$(ROOT) ZEPHYR_INSTANCE=$(abspath $(INSTANCE)) \
	  docker compose \
	    -f $(ROOT)/docker-compose.yml \
	    -f $(ROOT)/docker-compose.$(OVERLAY).yml \
	    --project-directory $(abspath $(INSTANCE)) \
	    config

# Medium topology compose (defaults instance to ../i-medium).
MEDIUM_INSTANCE ?= $(ROOT)/../i-medium
WEB_REPLICAS ?= 3
compose-medium:
	@test -d $(MEDIUM_INSTANCE) || { echo "missing instance dir $(MEDIUM_INSTANCE)" >&2; exit 1; }
	ZEPHYR_DOCKER=$(ROOT) ZEPHYR_INSTANCE=$(abspath $(MEDIUM_INSTANCE)) \
	  docker compose \
	    -f $(ROOT)/docker-compose.medium.yml \
	    --project-directory $(abspath $(MEDIUM_INSTANCE)) \
	    config
