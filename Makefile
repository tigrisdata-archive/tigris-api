API_DIR=.
V=v1
GEN_DIR=${API_DIR}/server/${V}

all: lint

# Generate GRPC client/server, openapi spec, http server
${GEN_DIR}/%_openapi.yaml ${GEN_DIR}/%.pb.go ${GEN_DIR}/%.pb.gw.go: ${GEN_DIR}/%.proto
	protoc -I. --openapi_out=${API_DIR} --openapi_opt=naming=proto \
		--go_out=${API_DIR} --go_opt=paths=source_relative \
		--go-grpc_out=${API_DIR} --go-grpc_opt=require_unimplemented_servers=false,paths=source_relative \
		--grpc-gateway_out=${API_DIR} --grpc-gateway_opt=paths=source_relative,allow_delete_body=true \
		$<
	/bin/bash scripts/fix_openapi.sh ${API_DIR}/openapi.yaml ${GEN_DIR}/$(*F)_openapi.yaml
	rm ${API_DIR}/openapi.yaml

# generate Go HTTP client from openapi spec
${API_DIR}/client/${V}/%/http.go: ${GEN_DIR}/%_openapi.yaml
	mkdir -p ${API_DIR}/client/${V}/$(*F)
	oapi-codegen -package api -generate "client, types, spec" \
		-o ${API_DIR}/client/${V}/$(*F)/http.go \
		${GEN_DIR}/$(*F)_openapi.yaml

generate: ${GEN_DIR}/api.pb.go ${GEN_DIR}/api.pb.gw.go ${GEN_DIR}/health.pb.go ${GEN_DIR}/health.pb.gw.go ${GEN_DIR}/api_openapi.yaml

client: ${API_DIR}/client/${V}/api/http.go

lint: generate client
	yq --exit-status 'tag == "!!map" or tag== "!!seq"' .github/workflows/*.yaml server/v1/*.yaml
	shellcheck scripts/*

clean:
	rm -f server/${V}/*.pb.go \
		server/${V}/*.pb.gw.go \
		client/${V}/*/http.go

