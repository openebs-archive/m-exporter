# Copyright © 2020 The OpenEBS Authors
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


# IMAGE_ORG can be used to customize the organization 
# under which images should be pushed. 
# By default the organization name is `openebs`. 

ifeq (${IMAGE_ORG}, )
  IMAGE_ORG = openebs
  export IMAGE_ORG
endif

# Specify the date of build
DBUILD_DATE=$(shell date -u +'%Y-%m-%dT%H:%M:%SZ')

# Specify the docker arg for repository url
ifeq (${DBUILD_REPO_URL}, )
  DBUILD_REPO_URL="https://github.com/openebs/openebs-exporter"
  export DBUILD_REPO_URL
endif

# Specify the docker arg for website url
ifeq (${DBUILD_SITE_URL}, )
  DBUILD_SITE_URL="https://openebs.io"
  export DBUILD_SITE_URL
endif

# Determine the arch/os
ifeq (${XC_OS}, )
  XC_OS:=$(shell go env GOOS)
endif
export XC_OS

ifeq (${XC_ARCH}, )
  XC_ARCH:=$(shell go env GOARCH)
endif
export XC_ARCH

ARCH:=${XC_OS}_${XC_ARCH}
export ARCH

# list only the source code directories
PACKAGES = $(shell go list ./... | grep -v 'vendor\|pkg/client/generated\|tests')

# list only the integration tests code directories
PACKAGES_IT = $(shell go list ./... | grep -v 'vendor\|pkg/client/generated' | grep 'tests')

# Specify the name for the binaries
EXPORTER=exporter

# If there are any external tools need to be used, they can be added by defining a EXTERNAL_TOOLS variable 
# Bootstrap the build by downloading additional tools
.PHONY: bootstrap
bootstrap:
	@for tool in  $(EXTERNAL_TOOLS) ; do \
		echo "Installing $$tool" ; \
		go get -u $$tool; \
	done

.PHONY: clean
clean:
	@echo '--> Cleaning exporter directory...'
	rm -rf bin/${EXPORTER}
	rm -rf ${GOPATH}/bin/${EXPORTER}
	@echo '--> Done cleaning.'
	@echo

# deps ensures fresh go.mod and go.sum.
.PHONY: deps
deps:
	@go mod tidy
	@go mod verify

.PHONY: test
test: format vet
	@echo "--> Running go test";
	$(PWD)/build/test.sh ${XC_ARCH}

.PHONY: testv
testv: format
	@echo "--> Running go test verbose" ;
	@go test -v $(PACKAGES)

.PHONY: format
format:
	@echo "--> Running go fmt"
	@go fmt $(PACKAGES) $(PACKAGES_IT)

# -composite: avoid "literal copies lock value from fakePtr"
.PHONY: vet
vet:
	@echo "--> Running go vet"
	@go list ./... | grep -v "./vendor/*" | xargs go vet -composites

.PHONY: verify-src
verify-src: 
	@echo "--> Checking for git changes post running tests";
	$(PWD)/build/check-diff.sh "format"

# Specify the name of the docker repo for amd64
EXPORTER_IMAGE?="m-exporter"

ifeq (${IMAGE_TAG}, )
  IMAGE_TAG = ci
  export IMAGE_TAG
endif

CSTOR_BASE_IMAGE= ${IMAGE_ORG}/cstor-base:${IMAGE_TAG}
export CSTOR_BASE_IMAGE

# build exporter binary
.PHONY: exporter
exporter:
	@echo "----------------------------"
	@echo "--> ${EXPORTER}              "
	@echo "----------------------------"
	@# PNAME is the sub-folder in ./bin where binary will be placed. 
	@# CTLNAME indicates the folder/pkg under cmd that needs to be built. 
	@# The output binary will be: ./bin/${PNAME}/<os-arch>/${CTLNAME}
	@# A copy of the binary will also be placed under: ./bin/${PNAME}/${CTLNAME}
	@PNAME=${EXPORTER} CTLNAME=${EXPORTER} CGO_ENABLED=0 sh -c "'$(PWD)/build/build.sh'"

export DBUILD_ARGS=--build-arg BASE_IMAGE=$(CSTOR_BASE_IMAGE) --build-arg DBUILD_DATE=${DBUILD_DATE} --build-arg DBUILD_REPO_URL=${DBUILD_REPO_URL} --build-arg DBUILD_SITE_URL=${DBUILD_SITE_URL} --build-arg RELEASE_TAG=${RELEASE_TAG} --build-arg BRANCH=${BRANCH}

# build exporter image
.PHONY: exporter-image
exporter-image: exporter
	@echo "-----------------------------------------------"
	@echo "--> ${EXPORTER} image                           "
	@echo "${IMAGE_ORG}/${EXPORTER_IMAGE}:${IMAGE_TAG}"
	@echo "-----------------------------------------------"
	@cp bin/${EXPORTER}/${EXPORTER} build/${EXPORTER}
	@cd build/${EXPORTER} && \
	 sudo docker build -t "${IMAGE_ORG}/${EXPORTER_IMAGE}:${IMAGE_TAG}" ${DBUILD_ARGS} .
	@rm build/${EXPORTER}/${EXPORTER}

.PHONY: all
all: check-license deps test exporter

# Push images
.PHONY: push
push:
	DIMAGE=${IMAGE_ORG}/${EXPORTER_IMAGE} ./build/push.sh

.PHONY: check_license
check-license:
	@echo ">> checking license header"
	@licRes=$$(for file in $$(find . -type f -regex '.*\.sh\|.*\.go\|.*Docker.*\|.*\Makefile*\|.*\yaml' ! -path './vendor/*' ) ; do \
               awk 'NR<=3' $$file | grep -Eq "(Copyright|generated|GENERATED)" || echo $$file; \
       done); \
       if [ -n "$${licRes}" ]; then \
               echo "license header checking failed:"; echo "$${licRes}"; \
               exit 1; \
       fi

# include the buildx recipes
include Makefile.buildx.mk
