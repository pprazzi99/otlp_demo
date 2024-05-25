# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0


# All documents to be used in spell check.
ALL_DOCS := $(shell find . -type f -name '*.md' -not -path './.github/*' -not -path '*/node_modules/*' -not -path '*/_build/*' -not -path '*/deps/*' | sort)
PWD := $(shell pwd)

TOOLS_DIR := ./internal/tools
MISSPELL_BINARY=bin/misspell
MISSPELL = $(TOOLS_DIR)/$(MISSPELL_BINARY)

# see https://github.com/open-telemetry/build-tools/releases for semconvgen updates
# Keep links in semantic_conventions/README.md and .vscode/settings.json in sync!
SEMCONVGEN_VERSION=0.11.0

# TODO: add `yamllint` step to `all` after making sure it works on Mac.
.PHONY: all
all: install-tools markdownlint misspell

$(MISSPELL):
	cd $(TOOLS_DIR) && go build -o $(MISSPELL_BINARY) github.com/client9/misspell/cmd/misspell

.PHONY: misspell
misspell:	$(MISSPELL)
	$(MISSPELL) -error $(ALL_DOCS)

.PHONY: misspell-correction
misspell-correction:	$(MISSPELL)
	$(MISSPELL) -w $(ALL_DOCS)

.PHONY: markdownlint
markdownlint:
	@if ! npm ls markdownlint; then npm install; fi
	@for f in $(ALL_DOCS); do \
		echo $$f; \
		npx --no -p markdownlint-cli markdownlint -c .markdownlint.yaml $$f \
			|| exit 1; \
	done

.PHONY: install-yamllint
install-yamllint:
    # Using a venv is recommended
	pip install -U yamllint~=1.30.0

.PHONY: yamllint
yamllint:
	yamllint .

.PHONY: checklicense
checklicense:
	@echo "Checking license headers..."
	npx @kt3k/license-checker -q

.PHONY: addlicense
addlicense:
	@echo "Adding license headers..."
	npx @kt3k/license-checker -q -i

# Run all checks in order of speed / likely failure.
.PHONY: check
check: misspell markdownlint checklicense
	@echo "All checks complete"

# Attempt to fix issues / regenerate tables.
.PHONY: fix
fix: misspell-correction
	@echo "All autofixes complete"

.PHONY: install-tools
install-tools: $(MISSPELL)
	npm install
	@echo "All tools installed"

.PHONY: build
build:
	docker compose build

.PHONY: build-and-push-dockerhub
build-and-push-dockerhub:
	docker compose --env-file .dockerhub.env -f docker-compose.yml build
	docker compose --env-file .dockerhub.env -f docker-compose.yml push

.PHONY: build-and-push-ghcr
build-and-push-ghcr:
	docker compose --env-file .ghcr.env -f docker-compose.yml build
	docker compose --env-file .ghcr.env -f docker-compose.yml push

.PHONY: build-env-file
build-env-file:
	cp .env .dockerhub.env
	sed -i '/IMAGE_VERSION=.*/c\IMAGE_VERSION=${RELEASE_VERSION}' .dockerhub.env
	sed -i '/IMAGE_NAME=.*/c\IMAGE_NAME=${DOCKERHUB_REPO}' .dockerhub.env
	cp .env .ghcr.env
	sed -i '/IMAGE_VERSION=.*/c\IMAGE_VERSION=${RELEASE_VERSION}' .ghcr.env
	sed -i '/IMAGE_NAME=.*/c\IMAGE_NAME=${GHCR_REPO}' .ghcr.env

.PHONY: run-tests
run-tests:
	docker compose run frontendTests
	docker compose run traceBasedTests

.PHONY: run-tracetesting
run-tracetesting:
	docker compose run traceBasedTests ${SERVICES_TO_TEST}

.PHONY: generate-protobuf
generate-protobuf:
	./ide-gen-proto.sh

.PHONY: generate-kubernetes-manifests
generate-kubernetes-manifests:
	helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
	helm repo update
	echo "# Copyright The OpenTelemetry Authors" > kubernetes/opentelemetry-demo.yaml
	echo "# SPDX-License-Identifier: Apache-2.0" >> kubernetes/opentelemetry-demo.yaml
	echo "# This file is generated by 'make generate-kubernetes-manifests'" >> kubernetes/opentelemetry-demo.yaml
	echo "---" >> kubernetes/opentelemetry-demo.yaml
	echo "apiVersion: v1" >> kubernetes/opentelemetry-demo.yaml
	echo "kind: Namespace" >> kubernetes/opentelemetry-demo.yaml
	echo "metadata:" >> kubernetes/opentelemetry-demo.yaml
	echo "  name: otel-demo" >> kubernetes/opentelemetry-demo.yaml
	helm template opentelemetry-demo open-telemetry/opentelemetry-demo --namespace otel-demo | sed '/helm.sh\/chart\:/d' | sed '/helm.sh\/hook/d' | sed '/managed-by\: Helm/d' >> kubernetes/opentelemetry-demo.yaml

.PHONY: start
start:
	docker compose up --force-recreate --remove-orphans --detach
	@echo ""
	@echo "OpenTelemetry Demo is running."
	@echo "Go to http://localhost:8780 for Konakart."
	@echo "Go to http://localhost:9443 for the Flopsar UI."
	@echo "Go to http://localhost:8080 for the demo UI."
	@echo "Go to http://localhost:8080/jaeger/ui for the Jaeger UI."
	@echo "Go to http://localhost:8080/grafana/ for the Grafana UI."
	@echo "Go to http://localhost:8080/loadgen/ for the Load Generator UI."
	@(./flopsar.sh)

.PHONY: start-minimal
start-minimal:
	docker compose -f docker-compose.minimal.yml up --force-recreate --remove-orphans --detach
	@echo ""
	@echo "OpenTelemetry Demo in minimal mode is running."
	@echo "Go to http://localhost:8080 for the demo UI."
	@echo "Go to http://localhost:8080/jaeger/ui for the Jaeger UI."
	@echo "Go to http://localhost:8080/grafana/ for the Grafana UI."
	@echo "Go to http://localhost:8080/loadgen/ for the Load Generator UI."

# Observabilty-Driven Development (ODD)
.PHONY: start-odd
start-odd:
	docker compose --profile odd up --force-recreate --remove-orphans --detach
	@echo ""
	@echo "OpenTelemetry Demo is running."
	@echo "Go to http://localhost:8080 for the demo UI."
	@echo "Go to http://localhost:8080/jaeger/ui for the Jaeger UI."
	@echo "Go to http://localhost:8080/grafana/ for the Grafana UI."
	@echo "Go to http://localhost:8080/loadgen/ for the Load Generator UI."
	@echo "Go to http://localhost:11633/ for the Tracetest Web UI."

.PHONY: stop
stop:
	docker compose --profile tests --profile odd down --remove-orphans --volumes
	@echo ""
	@echo "OpenTelemetry Demo is stopped."

# Use to restart a single service component
# Example: make restart service=frontend
.PHONY: restart
restart:
# work with `service` or `SERVICE` as input
ifdef SERVICE
	service := $(SERVICE)
endif

ifdef service
	docker compose stop $(service)
	docker compose rm --force $(service)
	docker compose create $(service)
	docker compose start $(service)
else
	@echo "Please provide a service name using `service=[service name]` or `SERVICE=[service name]`"
endif

# Use to rebuild and restart (redeploy) a single service component
# Example: make redeploy service=frontend
.PHONY: redeploy
redeploy:
# work with `service` or `SERVICE` as input
ifdef SERVICE
	service := $(SERVICE)
endif

ifdef service
	docker compose build $(service)
	docker compose stop $(service)
	docker compose rm --force $(service)
	docker compose create $(service)
	docker compose start $(service)
else
	@echo "Please provide a service name using `service=[service name]` or `SERVICE=[service name]`"
endif

