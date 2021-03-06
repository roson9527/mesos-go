MESOS_API_VERSION := v1
API_PKG    := ./api/${MESOS_API_VERSION}/lib
CMD_PKG    := ./api/${MESOS_API_VERSION}/cmd

PROTO_PATH := ${GOPATH}/src/:${API_PKG}/vendor/:.
PROTO_PATH := ${PROTO_PATH}:${API_PKG}/vendor/github.com/gogo/protobuf/protobuf
PROTO_PATH := ${PROTO_PATH}:${API_PKG}/vendor/github.com/gogo/protobuf/gogoproto

PACKAGES ?= $(shell go list ${API_PKG}/...|grep -v vendor)
TEST_DIRS ?= $(sort $(dir $(shell find ${API_PKG} -name '*_test.go' | grep -v vendor)))
BINARIES ?= $(shell go list -f "{{.Name}} {{.ImportPath}}" ${CMD_PKG}/...|grep -v -e vendor|grep -e ^main|cut -f2 -d' ')
TEST_FLAGS ?= -race
COVERAGE_TARGETS = ${TEST_DIRS:%/=%.cover}

.PHONY: all
all: test

.PHONY: install
install:
	go install $(BINARIES)

.PHONY: test
test:
	go $@ $(TEST_FLAGS) $(TEST_DIRS)

.PHONY: test-verbose
test-verbose: TEST_FLAGS += -v
test-verbose: test

.PHONY: coverage $(COVERAGE_TARGETS)
coverage: TEST_FLAGS = -v -cover -race
coverage: $(COVERAGE_TARGETS)
	cat _output/*.cover | sed -e '2,$$ s/^mode:.*$$//' -e '/^$$/d' >_output/coverage.out
$(COVERAGE_TARGETS):
	mkdir -p _output && go test ./$(@:%.cover=%) $(TEST_FLAGS) -coverprofile=_output/$(subst /,___,$@)

.PHONY: vet
vet:
	go $@ $(PACKAGES)

.PHONY: codecs
codecs: protobufs ffjson

.PHONY: protobufs
protobufs: clean-protobufs
	(cd ${API_PKG}; protoc --proto_path="${PROTO_PATH}" --gogo_out=. *.proto)
	(cd ${API_PKG}; protoc --proto_path="${PROTO_PATH}" --gogo_out=. ./scheduler/*.proto)
	(cd ${API_PKG}; protoc --proto_path="${PROTO_PATH}" --gogo_out=. ./executor/*.proto)

.PHONY: clean-protobufs
clean-protobufs:
	(cd ${API_PKG}; -rm *.pb.go */*.pb.go)

.PHONY: ffjson
ffjson: clean-ffjson
	(cd ${API_PKG}; ffjson *.pb.go)
	(cd ${API_PKG}; ffjson scheduler/*.pb.go)
	(cd ${API_PKG}; ffjson executor/*.pb.go)

.PHONY: clean-ffjson
clean-ffjson:
	(cd ${API_PKG}; rm -f *ffjson.go */*ffjson.go)

GOPKG		:= github.com/mesos/mesos-go
GOPKG_DIRNAME	:= $(shell dirname $(GOPKG))
UID		?= $(shell id -u $$USER)
GID		?= $(shell id -g $$USER)

DOCKER_IMAGE_REPO       ?= jdef
DOCKER_IMAGE_NAME       ?= example-scheduler-httpv1
DOCKER_IMAGE_VERSION    ?= latest
DOCKER_IMAGE_TAG        ?= $(DOCKER_IMAGE_REPO)/$(DOCKER_IMAGE_NAME):$(DOCKER_IMAGE_VERSION)

GOLDFLAGS	= -X $(GOPKG)/api/${MESOS_API_VERSION}/cmd.DockerImageTag=$(DOCKER_IMAGE_TAG)

BUILD_STEP	:= 'ln -s /src /go/src/$(GOPKG) && cd /go/src/$(GOPKG) && go install -ldflags "$(GOLDFLAGS)" $(BINARIES)'
COPY_STEP	:= 'cp /go/bin/* /src/_output/ && chown $(UID):$(GID) /src/_output/*'

# required for docker/Makefile
export DOCKER_IMAGE_TAG

.PHONY: docker
docker:
	mkdir -p _output
	test -n "$(UID)" || (echo 'ERROR: $$UID is undefined'; exit 1)
	test -n "$(GID)" || (echo 'ERROR: $$GID is undefined'; exit 1)
	docker run --rm -v "$$PWD":/src -w /go/src/$(GOPKG_DIRNAME) golang:1.6.1-alpine sh -c $(BUILD_STEP)' && '$(COPY_STEP)
	make -C api/${MESOS_API_VERSION}/docker
