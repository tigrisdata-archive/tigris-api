#!/bin/bash
# Copyright 2022 Tigris Data, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -ex

export GO111MODULE=on

go install google.golang.org/protobuf/cmd/protoc-gen-go@v1
go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@v1
go install github.com/grpc-ecosystem/grpc-gateway/v2/protoc-gen-grpc-gateway@v2
go install github.com/google/gnostic/cmd/protoc-gen-openapi@v0 #generate openapi 3.0 spec
go install github.com/deepmap/oapi-codegen/cmd/oapi-codegen@v1 #generate go http client
go install github.com/mikefarah/yq/v4@latest # used to fix OpenAPI spec in scripts/fix_openapi.sh
#npm install @redocly/cli -g

ARCH=$(uname -m)
OS=$(uname -s)
PROTO_VERSION=21.9
PB_REL="https://github.com/protocolbuffers/protobuf/releases"

if [[ "$OS" == "Darwin" ]]; then
	if command -v brew > /dev/null 2>&1; then
		brew install protobuf
	fi
else
	case "${OS}-${ARCH}" in
		"Linux-aarch64")
			RELEASE=protoc-$PROTO_VERSION-linux-aarch_64.zip
			;;
		"Linux-x86_64")
			RELEASE=protoc-$PROTO_VERSION-linux-x86_64.zip
			;;
		*)
			echo "Unsupported architecture ${ARCH} or operating system ${OS}"
			exit 1
	esac

	DOWNLOAD_URL=$PB_REL/download/v$PROTO_VERSION/$RELEASE
	echo "Fetching release ${DOWNLOAD_URL}"
	curl -LO $DOWNLOAD_URL
	unzip $RELEASE -d "$HOME/.local"
	export PATH="$PATH:$HOME/.local/bin"
fi
