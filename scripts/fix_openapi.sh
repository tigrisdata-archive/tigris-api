#!/bin/bash
# Copyright 2022-2023 Tigris Data, Inc.
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


set -e

IN_FILE=$1

main() {
	fix_bytes
	yq_update_description

	# user_openapi
	for i in InsertUserMetadataRequest \
		InsertUserMetadataResponse \
		UpdateUserMetadataRequest \
		UpdateUserMetadataResponse \
		GetUserMetadataRequest \
		GetNamespaceMetadataResponse \
		InsertNamespaceMetadataRequest \
		InsertNamespaceMetadataResponse \
		UpdateNamespaceMetadataRequest \
		UpdateNamespaceMetadataResponse \
		GetNamespaceMetadataRequest \
		GetNamespaceMetadataResponse; do
		yq_fix_object $i value
	done

	# Empty security in the health.proto doesn't work,
	# so fixing it here
	yq_cmd '.paths."/v1/health".get.security=[]'

	# Fix the types of filter and document fields to be object on HTTP wire.
	# The original format in proto file is "bytes", which allows to skip
	# unmarshalling in GRPC, we also implement custom unmarshalling for HTTP
	for i in DeleteRequest UpdateRequest ReadRequest SearchRequest; do
		yq_fix_object $i filter
	done

	yq_fix_object ImportRequest documents.items
	yq_fix_object InsertRequest documents.items
	yq_fix_object ReplaceRequest documents.items
	yq_fix_object UpdateRequest fields
	yq_fix_object ReadRequest fields
	yq_fix_array_object ReadRequest sort
	yq_fix_object ReadResponse data
	yq_fix_object SearchRequest fields
	yq_fix_object SearchRequest facet
	yq_fix_array_object SearchRequest sort
	yq_fix_object SearchHit data
	yq_fix_object CreateOrUpdateCollectionRequest schema
	yq_fix_object CreateOrUpdateCollectionsRequest schemas.items

	yq_fix_object DescribeCollectionResponse schema
	yq_fix_object CollectionDescription schema

	yq_fix_object CreateByIdRequest document
 	yq_fix_object DeleteByQueryRequest filter

 	yq_fix_object CreateOrUpdateIndexRequest schema
 	yq_fix_object IndexInfo schema

 	yq_fix_object UpdateDocumentRequest documents.items
 	yq_fix_object CreateOrReplaceDocumentRequest documents.items
 	yq_fix_object CreateDocumentRequest documents.items

 	yq_fix_object SearchIndexRequest filter
 	yq_fix_object SearchIndexRequest facet
 	yq_fix_array_object SearchIndexRequest sort

	yq_del_service_tags

	for i in InsertRequest ReplaceRequest UpdateRequest DeleteRequest ReadRequest \
		CreateOrUpdateCollectionRequest DropCollectionRequest \
		CreateProjectRequest DeleteProjectRequest ImportRequest \
		ListProjectsRequest ListCollectionsRequest SearchRequest \
		UpdateProjectRequest BeginTransactionRequest CommitTransactionRequest \
		RollbackTransactionRequest CreateAppKeyRequest \
		UpdateAppKeyRequest ListAppKeysRequest \
		DeleteAppKeyRequest CreateOrUpdateCollectionsRequest; do
		yq_del_project_coll $i
	done

	for i in CreateBranchRequest DeleteBranchRequest; do

		yq_del_project_branch $i
	done

	yq_streaming_response ReadResponse "collections/{collection}/documents/read"
	yq_streaming_response SearchResponse "collections/{collection}/documents/search"

	yq_error_response

	yq_fix_access_token_request

	for i in CreateCacheRequest  DeleteCacheRequest KeysRequest ; do
		yq_del_project_cache $i
	done

	for i in SetRequest GetSetRequest GetRequest DelRequest; do
		yq_del_project_cache_key $i
	done

}

fix_bytes() {
	# According to the OpenAPI spec format should be "byte",
	# but protoc-gen-openapi generates it as "bytes".
	# We fix it here
	sed -i'.bak' -e 's/format: bytes/format: byte/g' "$IN_FILE"
}

yq_cmd() {
	yq -I 4 -i "$1" "$IN_FILE"
}

# Change type of documents, filters, fields, schema to be JSON object
# instead of bytes.
# It's defined as bytes in proto to implement custom unmarshalling.
yq_fix_object() {
	yq_cmd "del(.components.schemas.$1.properties.$2.format)"
	yq_cmd ".components.schemas.$1.properties.$2.type=\"object\""
}

yq_fix_array_object() {
	yq_cmd "del(.components.schemas.$1.properties.$2.format)"
	yq_cmd ".components.schemas.$1.properties.$2.type=\"array\""
	yq_cmd ".components.schemas.$1.properties.$2.items.type=\"object\""
}

# Delete project and collection fields from request body
yq_del_project_coll() {
	yq_cmd "del(.components.schemas.$1.properties.project)"
	yq_cmd "del(.components.schemas.$1.properties.collection)"
}

# Delete project and branch fields from request body
yq_del_project_branch() {
	yq_cmd "del(.components.schemas.$1.properties.project)"
	yq_cmd "del(.components.schemas.$1.properties.branch)"
}

yq_del_service_tags() {
	yq_cmd "del(.paths[] | .get.tags[0])"
	yq_cmd "del(.paths[] | .post.tags[0])"
	yq_cmd "del(.paths[] | .put.tags[0])"
	yq_cmd "del(.paths[] | .patch.tags[0])"
	yq_cmd "del(.paths[] | .delete.tags[0])"
	yq_cmd "del(.tags[] | select(.name == \"Tigris\"))"
	yq_cmd "del(.tags[] | select(.name == \"HealthAPI\"))"
	yq_cmd "del(.tags[] | select(.name == \"Auth\"))"
	yq_cmd "del(.tags[] | select(.name == \"Billing\" and .description != \"*\"))"
	yq_cmd "del(.tags[] | select(.name == \"Search\" and .description != \"*\"))"
	yq_cmd "del(.tags[] | select(.name == \"Management\" and .description != \"*\"))"
	yq_cmd "del(.tags[] | select(.name == \"Observability\" and .description != \"*\"))"
	yq_cmd "del(.tags[] | select(.name == \"Cache\" and .description != \"*\"))"
	yq_cmd "del(.tags[] | select(.name == \"Realtime\" and .description != \"*\"))"
}

# By default GRPC gateway returns streaming response and error wrapped in a new
# object, instead of returning original response defined in proto file.
# This is done to be able to return an error in the middle of the stream.
#
# Response {
#   Result ProtoResponse // original response
#   Error grpc.Status
# }
#
# The following function fixes streaming response in OpenAPI to correspond above logic
#
# shellcheck disable=SC2016
yq_streaming_response() {
	yq_cmd 'with(.components.schemas.Streaming'"$1"';
	.type="object" |
	.properties.result.$ref="#/components/schemas/'"$1"'" |
	.properties.error.$ref="#/components/schemas/Error"
	)'

	yq_cmd '.paths."/v1/projects/{project}/database/'"$2"'".post.responses.200.content."application/json".schema.$ref="#/components/schemas/Streaming'"$1"'"'
}

# Rewrite default response Status to look like:
#
# Status:
#   error:
#      code int32
#      message string
#
# shellcheck disable=SC2016
yq_error_response() {
	yq_cmd "del(.components.schemas.Status)"
	yq_cmd 'with(.components.schemas.Status;
	.type="object" |
	.properties.error.$ref="#/components/schemas/Error"
	)'
	yq_cmd "del(.components.schemas.GetInfoResponse.properties.error)"
	yq_cmd "del(.components.schemas.GoogleProtobufAny)"
}

yq_update_description() {
  yq -i '.info.description|=load("server/v1/desc.yaml")' "$IN_FILE"
}

## openapi extension for proto doesn't support x-www-form-urlencoded
# content-type - this is to manually stich the openapi yaml file for
# get-access-token request
yq_fix_access_token_request() {
  yq_cmd ".paths./v1/auth/token.post.requestBody.content.x-www-form-urlencoded = .paths./v1/auth/token.post.requestBody.content.application/json | del(.paths./v1/auth/token.post.requestBody.content.application/json)"
}

# Delete project and cache name from request body
yq_del_project_cache() {
	yq_cmd "del(.components.schemas.$1.properties.project)"
	yq_cmd "del(.components.schemas.$1.properties.name)"
}

# Delete project, cache name and cache key name from request body
yq_del_project_cache_key() {
  yq_del_project_cache "$1"
	yq_cmd "del(.components.schemas.$1.properties.key)"
}


main
