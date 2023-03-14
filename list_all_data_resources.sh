#!/usr/bin/env bash

access_key="​ACCESS_KEY​"
secret_key="​SECRET_KEY​"
api_url="https://api4.prismacloud.io"


date=$(date +%Y%m%d-%H%M)


request_body=$(cat <<EOF
{"username": "$access_key", "password": "$secret_key"}
EOF
)


login_response=$(curl --request POST \
                      --url "$api_url/login" \
                      --header 'Accept: application/json; charset=UTF-8' \
                      --header 'Content-Type: application/json; charset=UTF-8' \
                      --data "${request_body}")

jwt=$(printf '%s' "$login_response" | jq -r '.token')

rql_api_response=$(curl --url "$api_url/dlp/api/v1/resource-inventory/resources" \
                        --header "accept: application/json; charset=UTF-8" \
                        --header "content-type: application/json" \
                        --header "x-redlock-auth: $jwt") \


printf '%s\n' "resourceName,size,dssEligibleSize,wildfireEligibleSize,dssAndWildfireEligibleSize,dssAndWildfireEligibleSize,isInventoryConfigured" > "list_of_data_resources.csv"

printf '%s' "$rql_api_response" | jq -r '.resources[] | {"resourceName": .resourceName, "size": .storageSize.size, "dssEligibleSize": .storageSize.dssEligibleSize, "wildfireEligibleSize": .storageSize.wildfireEligibleSize, "dssAndWildfireEligibleSize": .storageSize.dssAndWildfireEligibleSize, "dssAndWildfireEligibleSize": .storageSize.dssAndWildfireEligibleSize, "isInventoryConfigured": .storageSize.isInventoryConfigured}' | jq -r '[.[]] | @csv' >> list_of_data_resources.csv

printf '%s\n' "cloudtype,id,accountId,name,accountName,regionId,regionName,service,resourceType" > "./reports/cloud_resources_without_tags_$date.csv"

printf '\n\n\n%s\n\n' "All done your report is in the reports directory and is named list_of_data_resources.csv"
