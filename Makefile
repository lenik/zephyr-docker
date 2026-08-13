# zephyr image — build / push / pull
# Runtime instance: ../i-local (self-contained; does not mount files from here).

SHELL = /bin/bash
.PHONY: all vendor-node prepare-context inspect-context build build-roles push pull compose compose-medium

REGISTRY ?= 183.131.83.99:1244
IMAGE_NAME ?= zephyr
IMAGE_TAG ?= 1.0
IMAGE = $(IMAGE_NAME):$(IMAGE_TAG)
REMOTE_IMAGE = $(REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG)
# Node/Postgres/nginx from local rockynode (short tag — do not pull from Hub).
BASE_IMAGE ?= b4f-rockynode:10
ROOT = $(CURDIR)
REPO = $(ROOT)/..
VENDOR_NODE = $(ROOT)/vendor/node
# Persistent context (NOT /tmp — tmpfs gets wiped; you can inspect after build).
CTX = $(ROOT)/.build-ctx

# --pull=false: BASE_IMAGE is local b4f-rockynode:10 (no registry). Override if remote.
# --network=host: required when daemon.json has "bridge": "none" (no docker0 / default bridge).
# App deps come from context/app/node_modules (host prefer-offline); image only rebuilds natives.
BUILD_OPTS = --pull=false --provenance=false --sbom=false --network=host
BUILD_ARGS ?=

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
# Optional prepare-context modules (see scripts/prepare-context.sh --help).
# Default: lean image (no e2e/Chromium). Opt-in: PREPARE_OPTS='-e -m' or '-a'
PREPARE_OPTS ?=

prepare-context:
	CTX=$(CTX) REPO=$(REPO) $(ROOT)/scripts/prepare-context.sh $(PREPARE_OPTS)

inspect-context:
	@test -d $(CTX) || { echo "missing $(CTX) — run: make prepare-context" >&2; exit 1; }
	@echo "=== $(CTX) ==="
	@du -sh $(CTX) $(CTX)/* 2>/dev/null || true
	@echo "--- MANIFEST ---"
	@cat $(CTX)/MANIFEST.txt 2>/dev/null || true
	@echo "--- app/node_modules (top) ---"
	@ls $(CTX)/app/node_modules 2>/dev/null | sort

build: prepare-context
	docker build $(BUILD_OPTS) $(BUILD_ARGS) \
		--build-arg BASE_IMAGE=$(BASE_IMAGE) \
		-t $(REMOTE_IMAGE) \
		$(CTX)
	docker tag $(REMOTE_IMAGE) $(IMAGE)
	@echo "build context kept at $(CTX) — make inspect-context"

push:
	@docker image inspect $(IMAGE) >/dev/null 2>&1 || $(MAKE) build
	docker tag $(IMAGE) $(REMOTE_IMAGE)
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

# Render merged compose from an instance dir (default ../i-local).
INSTANCE ?= $(ROOT)/../i-local
OVERLAY ?= host
compose:
	@test -d $(INSTANCE) || { echo "missing instance dir $(INSTANCE)" >&2; exit 1; }
	@test -f $(abspath $(INSTANCE))/docker-compose.yml || { \
	  echo "missing $(INSTANCE)/docker-compose.yml — use i-local (self-contained)" >&2; exit 1; }
	ZEPHYR_INSTANCE=$(abspath $(INSTANCE)) \
	  docker compose \
	    -f $(abspath $(INSTANCE))/docker-compose.yml \
	    -f $(abspath $(INSTANCE))/docker-compose.$(OVERLAY).yml \
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
