V=v1
ifeq ($(API_DIR),)
API_DIR=.
endif
ifeq ($(PROTO_DIR),)
PROTO_DIR=server/${V}
endif
ifeq ($(GEN_DIR),)
GEN_DIR=${PROTO_DIR}
endif

all: lint

.PRECIOUS: ${PROTO_DIR}/openapi.yaml ${PROTO_DIR}/%.proto

COMPONENTS = api cache health auth observability management realtime search billing

# Generate GRPC client/server, openapi spec, http server
${GEN_DIR}/%.pb.go ${GEN_DIR}/%.pb.gw.go: ${PROTO_DIR}/%.proto
	protoc -I. \
		--go_out=${API_DIR} --go_opt=paths=source_relative \
		--go-grpc_out=${API_DIR} --go-grpc_opt=require_unimplemented_servers=false,paths=source_relative \
		--grpc-gateway_out=${API_DIR} --grpc-gateway_opt=paths=source_relative,allow_delete_body=true \
		$<

${PROTO_DIR}/openapi.yaml: $(COMPONENTS:%=$(PROTO_DIR)/%.proto) scripts/fix_openapi.sh
	protoc -I. -Iserver/v1 --openapi_out=${PROTO_DIR} --openapi_opt=naming=proto,enum_type=string $(COMPONENTS:%=$(PROTO_DIR)/%.proto)
	/bin/bash scripts/fix_openapi.sh ${PROTO_DIR}/openapi.yaml

# generate Go HTTP client from openapi spec
${API_DIR}/client/${V}/api/http.go: ${PROTO_DIR}/openapi.yaml
	mkdir -p ${API_DIR}/client/${V}/api
	oapi-codegen --old-config-style -package api -generate "client, types, spec" \
		-o ${API_DIR}/client/${V}/api/http.go \
		${PROTO_DIR}/openapi.yaml

# This target is also used by the server
generate: ${PROTO_DIR}/openapi.yaml $(COMPONENTS:%=$(GEN_DIR)/%.pb.go) $(COMPONENTS:%=$(GEN_DIR)/%.pb.gw.go)

# This target is also used by the client
client: ${API_DIR}/client/${V}/api/http.go

lint: generate client
	yq --exit-status 'tag == "!!map" or tag== "!!seq"' .github/workflows/*.yaml server/v1/*.yaml
	shellcheck scripts/*
	! which redocly || redocly lint ${PROTO_DIR}/openapi.yaml \
		--extends=recommended \
		--skip-rule=operation-4xx-response \
		--skip-rule=tag-description

clean:
	rm -f server/${V}/*.pb.go \
		server/${V}/*.pb.gw.go \
		client/${V}/*/http.go

