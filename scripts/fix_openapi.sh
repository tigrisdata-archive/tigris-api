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


set -e

IN_FILE=$1
OUT_FILE=$2

main() {
	fix_bytes

	if [[ "$OUT_FILE" == *"user_openapi"* ]]; then
		for i in InsertUserMetadataRequest \
			InsertUserMetadataResponse \
			UpdateUserMetadataRequest \
			UpdateUserMetadataResponse \
			GetUserMetadataRequest \
			GetUserMetadataResponse; do

			yq_fix_object $i value
		done
	fi

  # Empty security in the health.proto doesn't work,
  # so fixing it here
	if [[ "$OUT_FILE" == *"health_openapi"* ]]; then
	  yq_cmd ".security=[]"
	fi

	if [[ "$OUT_FILE" != *"api_openapi"* ]]; then
		yq_del_namespace_name CreateNamespaceRequest
		exit 0
	fi

	# Fix the types of filter and document fields to be object on HTTP wire.
	# The original format in proto file is "bytes", which allows to skip
	# unmarshalling in GRPC, we also implement custom unmarshalling for HTTP
	for i in DeleteRequest UpdateRequest ReadRequest SearchRequest; do
		yq_fix_object $i filter
	done

	yq_fix_object InsertRequest documents.items
	yq_fix_object ReplaceRequest documents.items
	yq_fix_object UpdateRequest fields
	yq_fix_object ReadRequest fields
	yq_fix_object ReadResponse data
	yq_fix_object SearchRequest fields
	yq_fix_object SearchRequest facet
	yq_fix_object SearchRequest sort
	yq_fix_object SearchHit data
	yq_fix_object CreateOrUpdateCollectionRequest schema
	yq_fix_object StreamEvent data
	yq_fix_object PublishRequest messages.items
	yq_fix_timestamp ResponseMetadata created_at
	yq_fix_timestamp ResponseMetadata updated_at

	yq_fix_object DescribeCollectionResponse schema
	yq_fix_object CollectionDescription schema

	yq_del_service_tags

	for i in InsertRequest ReplaceRequest UpdateRequest DeleteRequest ReadRequest \
		CreateOrUpdateCollectionRequest DropCollectionRequest \
		CreateDatabaseRequest DropDatabaseRequest \
		ListDatabasesRequest ListCollectionsRequest SearchRequest \
		BeginTransactionRequest CommitTransactionRequest RollbackTransactionRequest; do

		yq_del_db_coll $i
	done

	yq_streaming_response ReadResponse "collections/{collection}/documents/read"
	yq_streaming_response SearchResponse "collections/{collection}/documents/search"
	yq_streaming_response EventsResponse "collections/{collection}/events"
	yq_streaming_response SubscribeResponse "collections/{collection}/messages/subscribe"

	yq_error_response
}

fix_bytes() {
	# According to the OpenAPI spec format should be "byte",
	# but protoc-gen-openapi generates it as "bytes".
	# We fix it here
	# This is done last to also copy input file to output
	sed -e 's/format: bytes/format: byte/g' "$IN_FILE" >"$OUT_FILE"
}

yq_cmd() {
	yq -I 4 -i "$1" "$OUT_FILE"
}

# Delete name attribute from body
yq_del_namespace_name() {
	yq_cmd "del(.components.schemas.$1.properties.name)"
}

# Change type of documents, filters, fields, schema to be JSON object
# instead of bytes.
# It's defined as bytes in proto to implement custom unmarshalling.
yq_fix_object() {
	yq_cmd "del(.components.schemas.$1.properties.$2.format)"
	yq_cmd ".components.schemas.$1.properties.$2.type=\"object\""
}

yq_fix_timestamp() {
	yq_cmd ".components.schemas.$1.properties.$2.format=\"date-time\""
}

# Delete db and collection fields from request body
yq_del_db_coll() {
	yq_cmd "del(.components.schemas.$1.properties.db)"
	yq_cmd "del(.components.schemas.$1.properties.collection)"
}

yq_del_service_tags() {
  yq_cmd "del(.paths[] | .get.tags[0])"
  yq_cmd "del(.paths[] | .post.tags[0])"
  yq_cmd "del(.paths[] | .put.tags[0])"
  yq_cmd "del(.paths[] | .delete.tags[0])"
  yq_cmd "del(.tags[] | select(.name == \"Tigris\"))"
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

  yq_cmd '.paths."/api/v1/databases/{db}/'"$2"'".post.responses.200.content."application/json".schema.$ref="#/components/schemas/Streaming'"$1"'"'
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

main
