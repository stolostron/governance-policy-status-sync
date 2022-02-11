# Copyright 2019 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# Copyright Contributors to the Open Cluster Management project

# Image URL to use all building/pushing image targets;
# Use your own docker registry and image name for dev/test by overridding the IMG and REGISTRY environment variable.
IMG ?= $(shell cat COMPONENT_NAME 2> /dev/null)
REGISTRY ?= quay.io/stolostron
TAG ?= latest

# Github host to use for checking the source tree;
# Override this variable ue with your own value if you're working on forked repo.
GIT_HOST ?= github.com/stolostron

PWD := $(shell pwd)
BASE_DIR := $(shell basename $(PWD))
export PATH=$(shell echo $$PATH):$(PWD)/bin

# Keep an existing GOPATH, make a private one if it is undefined
GOPATH_DEFAULT := $(PWD)/.go
export GOPATH ?= $(GOPATH_DEFAULT)
GOBIN_DEFAULT := $(GOPATH)/bin
export GOBIN ?= $(GOBIN_DEFAULT)
GOARCH = $(shell go env GOARCH)
GOOS = $(shell go env GOOS)
TESTARGS_DEFAULT := -v
export TESTARGS ?= $(TESTARGS_DEFAULT)
DEST ?= $(GOPATH)/src/$(GIT_HOST)/$(BASE_DIR)
VERSION ?= $(shell cat COMPONENT_VERSION 2> /dev/null)
IMAGE_NAME_AND_VERSION ?= $(REGISTRY)/$(IMG)
# Handle KinD configuration
KIND_NAME ?= test-managed
KIND_NAMESPACE ?= open-cluster-management-agent-addon
KIND_VERSION ?= latest
MANAGED_CLUSTER_NAME ?= managed
WATCH_NAMESPACE ?= $(MANAGED_CLUSTER_NAME)
HUB_CONFIG ?= $(PWD)/kubeconfig_hub
HUB_CONFIG_INTERNAL ?= $(PWD)/kubeconfig_hub_internal
MANAGED_CONFIG ?= $(PWD)/kubeconfig_managed
ifneq ($(KIND_VERSION), latest)
	KIND_ARGS = --image kindest/node:$(KIND_VERSION)
else
	KIND_ARGS =
endif
# Fetch Ginkgo/Gomega versions from go.mod
GINKGO_VERSION := $(shell awk '/github.com\/onsi\/ginkgo/ {print $$2}' go.mod | head -1)
GOMEGA_VERSION := $(shell awk '/github.com\/onsi\/gomega/ {print $$2}' go.mod)
# Test coverage threshold
export COVERAGE_MIN ?= 69

LOCAL_OS := $(shell uname)
ifeq ($(LOCAL_OS),Linux)
    TARGET_OS ?= linux
    XARGS_FLAGS="-r"
else ifeq ($(LOCAL_OS),Darwin)
    TARGET_OS ?= darwin
    XARGS_FLAGS=
else
    $(error "This system's OS $(LOCAL_OS) isn't recognized/supported")
endif

.PHONY: fmt lint test coverage build build-images fmt-dependencies lint-dependencies

include build/common/Makefile.common.mk

############################################################
# work section
############################################################
$(GOBIN):
	@echo "create gobin"
	@mkdir -p $(GOBIN)

work: $(GOBIN)

############################################################
# format section
############################################################

fmt-dependencies:
	$(call go-get-tool,$(PWD)/bin/gci,github.com/daixiang0/gci@v0.2.9)
	$(call go-get-tool,$(PWD)/bin/gofumpt,mvdan.cc/gofumpt@v0.2.0)

# All available format: format-go format-protos format-python
# Default value will run all formats, override these make target with your requirements:
#    eg: fmt: format-go format-protos
fmt: fmt-dependencies
	find . -not \( -path "./.go" -prune \) -name "*.go" | xargs gofmt -s -w
	find . -not \( -path "./.go" -prune \) -name "*.go" | xargs gofumpt -l -w
	find . -not \( -path "./.go" -prune \) -name "*.go" | xargs gci -w -local "$(shell cat go.mod | head -1 | cut -d " " -f 2)"

############################################################
# check section
############################################################

check: lint

lint-dependencies:
	$(call go-get-tool,$(PWD)/bin/golangci-lint,github.com/golangci/golangci-lint/cmd/golangci-lint@v1.41.1)

# All available linters: lint-dockerfiles lint-scripts lint-yaml lint-copyright-banner lint-go lint-python lint-helm lint-markdown lint-sass lint-typescript lint-protos
# Default value will run all linters, override these make target with your requirements:
#    eg: lint: lint-go lint-yaml
lint: lint-dependencies lint-all

############################################################
# test section
############################################################
KUBEBUILDER_DIR = /usr/local/kubebuilder/bin
KBVERSION = 3.2.0
K8S_VERSION = 1.21.2

test:
	@go test $(TESTARGS) `go list ./... | grep -v test/e2e`

test-coverage: TESTARGS = -json -cover -covermode=atomic -coverprofile=coverage_unit.out
test-coverage: test

test-dependencies:
	@if (ls $(KUBEBUILDER_DIR)/*); then \
		echo "^^^ Files found in $(KUBEBUILDER_DIR). Skipping installation."; exit 1; \
	else \
		echo "^^^ Kubebuilder binaries not found. Installing Kubebuilder binaries."; \
	fi
	sudo mkdir -p $(KUBEBUILDER_DIR)
	sudo curl -L https://github.com/kubernetes-sigs/kubebuilder/releases/download/v$(KBVERSION)/kubebuilder_$(GOOS)_$(GOARCH) -o $(KUBEBUILDER_DIR)/kubebuilder
	sudo chmod +x $(KUBEBUILDER_DIR)/kubebuilder
	curl -L "https://go.kubebuilder.io/test-tools/$(K8S_VERSION)/$(GOOS)/$(GOARCH)" | sudo tar xz --strip-components=2 -C $(KUBEBUILDER_DIR)/

############################################################
# build section
############################################################

build:
	@build/common/scripts/gobuild.sh build/_output/bin/$(IMG) ./

local:
	@GOOS=darwin build/common/scripts/gobuild.sh build/_output/bin/$(IMG) ./

run:
	HUB_CONFIG=$(HUB_CONFIG) MANAGED_CONFIG=$(MANAGED_CONFIG) WATCH_NAMESPACE=$(WATCH_NAMESPACE) go run ./main.go --leader-elect=false

############################################################
# images section
############################################################

build-images:
	@docker build -t ${IMAGE_NAME_AND_VERSION} -f build/Dockerfile .
	@docker tag ${IMAGE_NAME_AND_VERSION} $(REGISTRY)/$(IMG):$(TAG)

############################################################
# clean section
############################################################
clean::
	rm -f build/_output/bin/$(IMG)

############################################################
# Generate manifests
############################################################
CONTROLLER_GEN = $(shell pwd)/bin/controller-gen
KUSTOMIZE = $(shell pwd)/bin/kustomize

.PHONY: manifests
manifests: controller-gen
	$(CONTROLLER_GEN) $(CRD_OPTIONS) rbac:roleName=governance-policy-status-sync paths="./..." output:rbac:artifacts:config=deploy/rbac

.PHONY: generate
generate: controller-gen ## Generate code containing DeepCopy, DeepCopyInto, and DeepCopyObject method implementations.
	$(CONTROLLER_GEN) object:headerFile="hack/boilerplate.go.txt" paths="./..."

.PHONY: generate-operator-yaml
generate-operator-yaml: kustomize manifests
	$(KUSTOMIZE) build deploy/manager > deploy/operator.yaml

.PHONY: controller-gen
controller-gen: ## Download controller-gen locally if necessary.
	$(call go-get-tool,$(CONTROLLER_GEN),sigs.k8s.io/controller-tools/cmd/controller-gen@v0.6.1)

.PHONY: kustomize
kustomize: ## Download kustomize locally if necessary.
	$(call go-get-tool,$(KUSTOMIZE),sigs.k8s.io/kustomize/kustomize/v3@v3.8.7)

define go-get-tool
@[ -f $(1) ] || { \
set -e ;\
TMP_DIR=$$(mktemp -d) ;\
cd $$TMP_DIR ;\
go mod init tmp ;\
echo "Downloading $(2)" ;\
GOBIN=$(PWD)/bin go get $(2) ;\
rm -rf $$TMP_DIR ;\
}
endef

############################################################
# e2e test section
############################################################
.PHONY: kind-bootstrap-cluster
kind-bootstrap-cluster: kind-create-cluster install-crds kind-deploy-controller install-resources

.PHONY: kind-bootstrap-cluster-dev
kind-bootstrap-cluster-dev: kind-create-cluster install-crds install-resources

kind-deploy-controller:
	@echo installing $(IMG)
	kubectl create ns $(KIND_NAMESPACE) --kubeconfig=$(MANAGED_CONFIG)
	kubectl create secret -n $(KIND_NAMESPACE) generic hub-kubeconfig --from-file=kubeconfig=$(HUB_CONFIG_INTERNAL) --kubeconfig=$(MANAGED_CONFIG)
	kubectl apply -f deploy/operator.yaml -n $(KIND_NAMESPACE) --kubeconfig=$(MANAGED_CONFIG)

kind-deploy-controller-dev: kind-deploy-controller
	@echo Pushing image to KinD cluster
	kind load docker-image $(REGISTRY)/$(IMG):$(TAG) --name $(KIND_NAME)
	@echo "Patch deployment image"
	kubectl patch deployment $(IMG) -n $(KIND_NAMESPACE) -p "{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"$(IMG)\",\"imagePullPolicy\":\"Never\"}]}}}}" --kubeconfig=$(MANAGED_CONFIG)
	kubectl patch deployment $(IMG) -n $(KIND_NAMESPACE) -p "{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"$(IMG)\",\"image\":\"$(REGISTRY)/$(IMG):$(TAG)\"}]}}}}" --kubeconfig=$(MANAGED_CONFIG)
	kubectl rollout status -n $(KIND_NAMESPACE) deployment $(IMG) --timeout=180s --kubeconfig=$(MANAGED_CONFIG)

kind-create-cluster:
	@echo "creating cluster"
	kind create cluster --name test-hub $(KIND_ARGS)
	kind get kubeconfig --name test-hub > $(HUB_CONFIG)
	# needed for managed -> hub communication
	kind get kubeconfig --name test-hub --internal > $(HUB_CONFIG_INTERNAL)
	kind create cluster --name $(KIND_NAME) $(KIND_ARGS)
	kind get kubeconfig --name $(KIND_NAME) > $(MANAGED_CONFIG)

kind-delete-cluster:
	kind delete cluster --name test-hub
	kind delete cluster --name $(KIND_NAME)

install-crds:
	@echo installing crds
	kubectl apply -f https://raw.githubusercontent.com/stolostron/governance-policy-propagator/main/deploy/crds/policy.open-cluster-management.io_policies.yaml --kubeconfig=$(HUB_CONFIG)
	kubectl apply -f https://raw.githubusercontent.com/stolostron/governance-policy-propagator/main/deploy/crds/policy.open-cluster-management.io_policies.yaml --kubeconfig=$(MANAGED_CONFIG)

install-resources:
	@echo creating namespace on hub
	kubectl create ns $(WATCH_NAMESPACE) --kubeconfig=$(HUB_CONFIG)

e2e-dependencies:
	go get github.com/onsi/ginkgo/v2/ginkgo@$(GINKGO_VERSION)
	go get github.com/onsi/gomega/...@$(GOMEGA_VERSION)

e2e-test:
	$(GOPATH)/bin/ginkgo -v --fail-fast --slow-spec-threshold=10s $(E2E_TEST_ARGS) test/e2e

e2e-test-coverage: E2E_TEST_ARGS = --json-report=report_e2e.json --output-dir=.
e2e-test-coverage: e2e-test


e2e-debug:
	@echo gathering hub info
	kubectl get all -n managed --kubeconfig=$(PWD)/kubeconfig_hub
	kubectl get Policy.policy.open-cluster-management.io --all-namespaces --kubeconfig=$(PWD)/kubeconfig_hub
	@echo gathering managed cluster info
	kubectl get all -n $(KIND_NAMESPACE) --kubeconfig=$(PWD)/kubeconfig_managed
	kubectl get all -n managed --kubeconfig=$(PWD)/kubeconfig_managed
	kubectl get leases -n managed --kubeconfig=$(PWD)/kubeconfig_managed
	kubectl get Policy.policy.open-cluster-management.io --all-namespaces --kubeconfig=$(PWD)/kubeconfig_managed
	kubectl describe pods -n $(KIND_NAMESPACE) --kubeconfig=$(PWD)/kubeconfig_managed
	kubectl logs $$(kubectl get pods -n $(KIND_NAMESPACE) -o name --kubeconfig=$(PWD)/kubeconfig_managed | grep $(IMG)) -n $(KIND_NAMESPACE) --kubeconfig=$(PWD)/kubeconfig_managed

############################################################
# test coverage
############################################################
GOCOVMERGE = $(shell pwd)/bin/gocovmerge
coverage-dependencies:
	$(call go-get-tool,$(GOCOVMERGE),github.com/wadey/gocovmerge)

COVERAGE_FILE = coverage.out
coverage-merge: coverage-dependencies
	@echo Merging the coverage reports into $(COVERAGE_FILE)
	$(GOCOVMERGE) $(PWD)/coverage_* > $(COVERAGE_FILE)

coverage-verify:
	./build/common/scripts/coverage_calc.sh
