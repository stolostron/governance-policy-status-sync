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

PWD := $(shell pwd)
export PATH := $(PWD)/bin:$(PATH)

# Keep an existing GOPATH, make a private one if it is undefined
GOPATH_DEFAULT := $(PWD)/.go
export GOPATH ?= $(GOPATH_DEFAULT)
GOBIN_DEFAULT := $(GOPATH)/bin
export GOBIN ?= $(GOBIN_DEFAULT)
GOARCH = $(shell go env GOARCH)
GOOS = $(shell go env GOOS)
TESTARGS_DEFAULT := -v
export TESTARGS ?= $(TESTARGS_DEFAULT)
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

# Image URL to use all building/pushing image targets;
# Use your own docker registry and image name for dev/test by overridding the IMG and REGISTRY environment variable.
IMG ?= $(shell cat COMPONENT_NAME 2> /dev/null)
VERSION ?= $(shell cat COMPONENT_VERSION 2> /dev/null)
REGISTRY ?= quay.io/stolostron
TAG ?= latest
IMAGE_NAME_AND_VERSION ?= $(REGISTRY)/$(IMG)

include build/common/Makefile.common.mk

############################################################
# work section
############################################################

$(GOBIN):
	@mkdir -p $(GOBIN)

############################################################
# clean section
############################################################
.PHONY: clean:
clean::
	rm -f build/_output/bin/$(IMG)

############################################################
# format section
############################################################

.PHONY: fmt-dependencies
fmt-dependencies:
	$(call go-get-tool,$(PWD)/bin/gci,github.com/daixiang0/gci@v0.2.9)
	$(call go-get-tool,$(PWD)/bin/gofumpt,mvdan.cc/gofumpt@v0.2.0)

# All available format: format-go format-protos format-python
# Default value will run all formats, override these make target with your requirements:
#    eg: fmt: format-go format-protos
.PHONY: fmt
fmt: fmt-dependencies
	find . -not \( -path "./.go" -prune \) -name "*.go" | xargs gofmt -s -w
	find . -not \( -path "./.go" -prune \) -name "*.go" | xargs gofumpt -l -w
	find . -not \( -path "./.go" -prune \) -name "*.go" | xargs gci -w -local "$(shell cat go.mod | head -1 | cut -d " " -f 2)"

############################################################
# check section
############################################################

.PHONY: check
check: lint

.PHONY: lint-dependencies
lint-dependencies:
	$(call go-get-tool,$(PWD)/bin/golangci-lint,github.com/golangci/golangci-lint/cmd/golangci-lint@v1.41.1)

# All available linters: lint-dockerfiles lint-scripts lint-yaml lint-copyright-banner lint-go lint-python lint-helm lint-markdown lint-sass lint-typescript lint-protos
# Default value will run all linters, override these make target with your requirements:
#    eg: lint: lint-go lint-yaml
.PHONY: lint
lint: lint-dependencies lint-all

############################################################
# test section
############################################################
KUBEBUILDER_DIR = /usr/local/kubebuilder/bin
KBVERSION = 3.2.0
K8S_VERSION = 1.21.2
GOSEC = $(shell pwd)/bin/gosec
GOSEC_VERSION = 2.9.6

.PHONY: test
test:
	@go test $(TESTARGS) `go list ./... | grep -v test/e2e`

.PHONY: test-coverage
test-coverage: TESTARGS = -json -cover -covermode=atomic -coverprofile=coverage_unit.out
test-coverage: test

.PHONY: test-dependencies
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

$(GOSEC):
	curl -L https://github.com/securego/gosec/releases/download/v$(GOSEC_VERSION)/gosec_$(GOSEC_VERSION)_$(GOOS)_$(GOARCH).tar.gz | tar -xz -C /tmp/
	sudo mv /tmp/gosec $(GOSEC)

.PHONY: gosec-scan
gosec-scan: $(GOSEC)
	$(GOSEC) -fmt sonarqube -out gosec.json -no-fail -exclude-dir=.go ./...

############################################################
# build section
############################################################

.PHONY: build
build:
	@build/common/scripts/gobuild.sh build/_output/bin/$(IMG) ./

.PHONY: local
local:
	@GOOS=darwin build/common/scripts/gobuild.sh build/_output/bin/$(IMG) ./

.PHONY: run
run:
	HUB_CONFIG=$(HUB_CONFIG) MANAGED_CONFIG=$(MANAGED_CONFIG) WATCH_NAMESPACE=$(WATCH_NAMESPACE) go run ./main.go --leader-elect=false

############################################################
# images section
############################################################

.PHONY: build-images
build-images:
	@docker build -t ${IMAGE_NAME_AND_VERSION} -f build/Dockerfile .
	@docker tag ${IMAGE_NAME_AND_VERSION} $(REGISTRY)/$(IMG):$(TAG)

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

.PHONY: kind-deploy-controller
kind-deploy-controller:
	@echo installing $(IMG)
	kubectl create ns $(KIND_NAMESPACE) --kubeconfig=$(MANAGED_CONFIG)
	kubectl create secret -n $(KIND_NAMESPACE) generic hub-kubeconfig --from-file=kubeconfig=$(HUB_CONFIG_INTERNAL) --kubeconfig=$(MANAGED_CONFIG)
	kubectl apply -f deploy/operator.yaml -n $(KIND_NAMESPACE) --kubeconfig=$(MANAGED_CONFIG)

.PHONY: kind-deploy-controller-dev
kind-deploy-controller-dev: kind-deploy-controller
	@echo Pushing image to KinD cluster
	kind load docker-image $(REGISTRY)/$(IMG):$(TAG) --name $(KIND_NAME)
	@echo "Patch deployment image"
	kubectl patch deployment $(IMG) -n $(KIND_NAMESPACE) -p "{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"$(IMG)\",\"imagePullPolicy\":\"Never\"}]}}}}" --kubeconfig=$(MANAGED_CONFIG)
	kubectl patch deployment $(IMG) -n $(KIND_NAMESPACE) -p "{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"$(IMG)\",\"image\":\"$(REGISTRY)/$(IMG):$(TAG)\"}]}}}}" --kubeconfig=$(MANAGED_CONFIG)
	kubectl rollout status -n $(KIND_NAMESPACE) deployment $(IMG) --timeout=180s --kubeconfig=$(MANAGED_CONFIG)

.PHONY: kind-create-cluster
kind-create-cluster:
	@echo "creating cluster"
	kind create cluster --name test-hub $(KIND_ARGS)
	kind get kubeconfig --name test-hub > $(HUB_CONFIG)
	# needed for managed -> hub communication
	kind get kubeconfig --name test-hub --internal > $(HUB_CONFIG_INTERNAL)
	kind create cluster --name $(KIND_NAME) $(KIND_ARGS)
	kind get kubeconfig --name $(KIND_NAME) > $(MANAGED_CONFIG)

.PHONY: kind-delete-cluster
kind-delete-cluster:
	kind delete cluster --name test-hub
	kind delete cluster --name $(KIND_NAME)

.PHONY: install-crds
install-crds:
	@echo installing crds
	kubectl apply -f https://raw.githubusercontent.com/stolostron/governance-policy-propagator/main/deploy/crds/policy.open-cluster-management.io_policies.yaml --kubeconfig=$(HUB_CONFIG)
	kubectl apply -f https://raw.githubusercontent.com/stolostron/governance-policy-propagator/main/deploy/crds/policy.open-cluster-management.io_policies.yaml --kubeconfig=$(MANAGED_CONFIG)

.PHONY: install-resources
install-resources:
	@echo creating namespace on hub
	kubectl create ns $(WATCH_NAMESPACE) --kubeconfig=$(HUB_CONFIG)
	@echo creating namespace on managed
	kubectl create ns $(MANAGED_CLUSTER_NAME) --kubeconfig=$(MANAGED_CONFIG)

.PHONY: e2e-dependencies
e2e-dependencies:
	go get github.com/onsi/ginkgo/v2/ginkgo@$(GINKGO_VERSION)
	go get github.com/onsi/gomega/...@$(GOMEGA_VERSION)

.PHONY: e2e-test
e2e-test:
	$(GOPATH)/bin/ginkgo -v --fail-fast --slow-spec-threshold=10s $(E2E_TEST_ARGS) test/e2e

.PHONY: e2e-test-coverage
e2e-test-coverage: E2E_TEST_ARGS = --json-report=report_e2e.json --output-dir=.
e2e-test-coverage: e2e-test

.PHONY: e2e-build-instrumented
e2e-build-instrumented:
	go test -covermode=atomic -coverpkg=$(shell cat go.mod | head -1 | cut -d ' ' -f 2)/... -c -tags e2e ./ -o build/_output/bin/$(IMG)-instrumented

.PHONY: e2e-run-instrumented
e2e-run-instrumented:
	HUB_CONFIG=$(HUB_CONFIG) MANAGED_CONFIG=$(MANAGED_CONFIG) WATCH_NAMESPACE=$(WATCH_NAMESPACE) ./build/_output/bin/$(IMG)-instrumented -test.run "^TestRunMain$$" -test.coverprofile=coverage_e2e.out &>/dev/null &

.PHONY: e2e-stop-instrumented
e2e-stop-instrumented:
	ps -ef | grep '$(IMG)' | grep -v grep | awk '{print $$2}' | xargs kill

.PHONY: e2e-debug
e2e-debug:
	@echo gathering hub info
	kubectl get all -n managed --kubeconfig=$(HUB_CONFIG)
	kubectl get Policy.policy.open-cluster-management.io --all-namespaces --kubeconfig=$(HUB_CONFIG)
	@echo gathering managed cluster info
	kubectl get all -n $(KIND_NAMESPACE) --kubeconfig=$(MANAGED_CONFIG)
	kubectl get all -n managed --kubeconfig=$(MANAGED_CONFIG)
	kubectl get leases -n managed --kubeconfig=$(MANAGED_CONFIG)
	kubectl get Policy.policy.open-cluster-management.io --all-namespaces --kubeconfig=$(MANAGED_CONFIG)
	kubectl describe pods -n $(KIND_NAMESPACE) --kubeconfig=$(MANAGED_CONFIG)
	kubectl logs $$(kubectl get pods -n $(KIND_NAMESPACE) -o name --kubeconfig=$(MANAGED_CONFIG) | grep $(IMG)) -n $(KIND_NAMESPACE) --kubeconfig=$(MANAGED_CONFIG)

############################################################
# test coverage
############################################################
GOCOVMERGE = $(shell pwd)/bin/gocovmerge
.PHONY: coverage-dependencies
coverage-dependencies:
	$(call go-get-tool,$(GOCOVMERGE),github.com/wadey/gocovmerge)

COVERAGE_FILE = coverage.out
.PHONY: coverage-merge
coverage-merge: coverage-dependencies
	@echo Merging the coverage reports into $(COVERAGE_FILE)
	$(GOCOVMERGE) $(PWD)/coverage_* > $(COVERAGE_FILE)

.PHONY: coverage-verify
coverage-verify:
	./build/common/scripts/coverage_calc.sh
