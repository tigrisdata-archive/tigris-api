V=v1
ifeq ($(API_DIR),)
API_DIR=.
endif
PROTO_DIR=server/${V}
ifeq ($(GEN_DIR),)
GEN_DIR=${PROTO_DIR}
endif

all: lint

.PRECIOUS: ${PROTO_DIR}/%_openapi.yaml ${PROTO_DIR}/%.proto

COMPONENTS = api health admin auth observability

# Generate GRPC client/server, openapi spec, http server
${PROTO_DIR}/%_openapi.yaml ${GEN_DIR}/%.pb.go ${GEN_DIR}/%.pb.gw.go: ${PROTO_DIR}/%.proto
	protoc -I. --openapi_out=${API_DIR} --openapi_opt=naming=proto,enum_type=string \
		--go_out=${API_DIR} --go_opt=paths=source_relative \
		--go-grpc_out=${API_DIR} --go-grpc_opt=require_unimplemented_servers=false,paths=source_relative \
		--grpc-gateway_out=${API_DIR} --grpc-gateway_opt=paths=source_relative,allow_delete_body=true \
		$<
	/bin/bash scripts/fix_openapi.sh ${API_DIR}/openapi.yaml ${PROTO_DIR}/$(*F)_openapi.yaml
	rm ${API_DIR}/openapi.yaml

# generate Go HTTP client from openapi spec
${API_DIR}/client/${V}/%/http.go: ${PROTO_DIR}/%_openapi.yaml
	mkdir -p ${API_DIR}/client/${V}/$(*F)
	oapi-codegen --old-config-style -package api -generate "client, types, spec" \
		-o ${API_DIR}/client/${V}/$(*F)/http.go \
		${PROTO_DIR}/$(*F)_openapi.yaml

generate: \
	$(COMPONENTS:%=$(GEN_DIR)/%.pb.go) \
	$(COMPONENTS:%=$(GEN_DIR)/%.pb.gw.go) \
	$(COMPONENTS:%=$(PROTO_DIR)/%_openapi.yaml)

client: ${API_DIR}/client/${V}/api/http.go

lint: generate client
	yq --exit-status 'tag == "!!map" or tag== "!!seq"' .github/workflows/*.yaml server/v1/*.yaml
	shellcheck scripts/*

clean:
	rm -f server/${V}/*.pb.go \
		server/${V}/*.pb.gw.go \
		client/${V}/*/http.go

