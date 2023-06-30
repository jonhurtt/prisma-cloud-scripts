#!/usr/bin/env bash
#------------------------------------------------------------------------------------------------------------------#
# Written By Jonathan Hurtt
#
# REQUIREMENTS: 
# Requires jq to be installed: 'sudo apt-get install jq'
#
##############################################################################
clear

date=$(date +%Y%m%d)

#Secrets
PC_APIURL="REDACTED"
PC_ACCESSKEY="REDACTED"
PC_SECRETKEY="REDACTED"

#Tag Key Value Pair
KVP_KEY="created-by"
KVP_VALUE="prismacloud-agentless-scan"

#Select CSP from {"aws-" "azure-" "gcp-" "gcloud-" "alibaba-" "oci-"} 
csp_pfix_array=("aws-" "azure-" "gcp-" "gcloud-" "alibaba-" "oci-")

#Define Time Amount and Units for search
RESOURCE_TIME_AMOUNT=24
RESOURCE_TIME_UNIT="hour"

ALERT_TIME_AMOUNT=30
ALERT_TIME_UNIT="day"

##############################################################################

TOTAL_RESOURCES=0
TOTAL_ALERTS=0
TOTAL_RESOURCES_WITH_ALERTS=0

#used for batching curl command for finding alerts
batch_size=10
curl_break=5

#Amount of Time the JWT is valid (10 min) adjust refresh to lower number with slower connections
jwt_token_timeout=600
jwt_token_refresh=590

#Define Folder Locations
OUTPUT_LOCATION=./output
JSON_OUTPUT_LOCATION=./output/json

#Create output folders
mkdir -p ${OUTPUT_LOCATION}
rm -f ${OUTPUT_LOCATION}/*.csv
rm -f ${OUTPUT_LOCATION}/*.json

mkdir -p ${JSON_OUTPUT_LOCATION}
rm -f ${JSON_OUTPUT_LOCATION}/*.json
 
SPACER="===================================================================================================================================="
DIVIDER="++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"

printf "%s\n" ${DIVIDER}
#Begin Applicaiton Timer
start_time=$(date +%Y%m%d-%H:%M:%S)
printf "Start Time: ${start_time}\n"
start=$(date +%s)

#Define Auth Payload for JWT
AUTH_PAYLOAD=$(cat <<EOF
{"username": "${PC_ACCESSKEY}", "password": "${PC_SECRETKEY}"}
EOF
)

#API Call for JWT
PC_JWT_RESPONSE=$(curl -s --request POST \
	--url "${PC_APIURL}/login" \
	--header 'Accept: application/json; charset=UTF-8' \
	--header 'Content-Type: application/json; charset=UTF-8' \
	--data "${AUTH_PAYLOAD}")


PC_JWT=$(printf %s "${PC_JWT_RESPONSE}" | jq -r '.token')

if [ -z "${PC_JWT}" ]; then
	printf "JWT not recieved, recommending you check your variable assignment\n";
	exit;
else
	printf "JWT Recieved\n"
	printf "%s\n" ${SPACER}
fi

printf "Assembling list of available APIs...\n"
for csp_indx in "${!csp_pfix_array[@]}"; do \

	config_request_body=$(cat <<EOF
	{
		  "query":"config from cloud.resource where api.name = ${csp_pfix_array[csp_indx]}",
		  "timeRange":{
			"type":"relative",
			"value":{
			   "unit":"${RESOURCE_TIME_UNIT}",
			   "amount":${RESOURCE_TIME_AMOUNT}
			}
		  }
	}
	EOF
	)
	
	curl --no-progress-meter --url "${PC_APIURL}/search/suggest" \
		--header "accept: application/json; charset=UTF-8" \
		--header "content-type: application/json" \
		--header "x-redlock-auth: ${PC_JWT}" \
		--data "${config_request_body}" > "${JSON_OUTPUT_LOCATION}/00_api_suggestions_${csp_indx}.json"
done #end iteration through CSP prefix.

rql_api_array=($(cat ${JSON_OUTPUT_LOCATION}/00_api_suggestions_* | jq -r '.suggestions[]?'))

printf '%s available API endpoints\n' ${#rql_api_array[@]}
printf "%s\n" ${SPACER}

printf "Searching for resources with tags containing key:value of {%s:%s} over past %s %s... \n"  ${KVP_KEY} ${KVP_VALUE} ${RESOURCE_TIME_AMOUNT} ${RESOURCE_TIME_UNIT}
printf "%s\n" ${SPACER}

for api_query_indx in "${!rql_api_array[@]}"; do \
	
	rql_request_body=$(cat <<EOF
	{
		  "query":"config from cloud.resource where api.name = ${rql_api_array[api_query_indx]} AND resource.status = Active AND json.rule = tags[?(@.key=='${KVP_KEY}')].value equals ${KVP_VALUE}",
		  "timeRange":{
			"type":"relative",
			"value":{
			"unit":"${RESOURCE_TIME_UNIT}",
			"amount":${RESOURCE_TIME_AMOUNT}
			}
		  }
	}
	EOF
	)
	
	curl --no-progress-meter --url "${PC_APIURL}/search/config" \
		--header "accept: application/json; charset=UTF-8" \
		--header "content-type: application/json" \
		--header "x-redlock-auth: ${PC_JWT}" \
		--data "${rql_request_body}" > "${JSON_OUTPUT_LOCATION}/01_api_query_${api_query_indx}.json" &
done
wait

#Create CSV for all resources
printf '%s\n' "cloudType,id,accountId,name,accountName,regionId,regionName,service,resourceType,tags" > "${OUTPUT_LOCATION}/all_cloud_resources_${date}.csv"

cat ${JSON_OUTPUT_LOCATION}/01_api_query_*.json | jq -r '.data.items[] | {"cloudType": .cloudType, "id": .id, "accountId": .accountId,  "name": .name,  "accountName": .accountName,  "regionId": .regionId,  "regionName": .regionName,  "service": .service, "resourceType": .resourceType, "tags" : (.data.tags | map(.key,.value) | join(":")) }' | jq -r '[.[]] | @csv' >> "${OUTPUT_LOCATION}/all_cloud_resources_${date}.csv"

printf '%s\n' "Inventory Report located at ${OUTPUT_LOCATION}/all_cloud_resources_${date}.csv"
printf "%s\n" ${SPACER}

#Find all Resouce IDs to search for Alerts
resource_id_array=($(cat ${JSON_OUTPUT_LOCATION}/01_api_query_*.json | jq -r '.data.items[].id'))

printf "Finding all alerts for %s resources found matching key:value of {%s:%s} over past %s %s ...\n" ${#resource_id_array[@]} ${KVP_KEY} ${KVP_VALUE} ${ALERT_TIME_AMOUNT} ${ALERT_TIME_UNIT}
printf "%s\n" ${SPACER}

array_count=${#resource_id_array[@]}
counter=0

#Batch Curl for large resource counts (>1K)
while [ $counter -lt ${#resource_id_array[@]} ]
do
	#Resize Batach size is needed
	if [[ $((counter + batch_size )) -ge $((${#resource_id_array[@]})) ]]; then
		batch_size=$(( ${#resource_id_array[@]} - counter ))
	fi
	
	#Iterate through array in batches
	for ((batch_index=1;batch_index<=batch_size;batch_index++));do
		curl_url="${PC_APIURL}/v2/alert?detailed=true&timeType=relative&timeAmount=${ALERT_TIME_AMOUNT}&timeUnit=${ALERT_TIME_UNIT}&resource.id=${resource_id_array[counter]}"
		echo -ne "-->[${trigger}] Investigating resource ${counter} of ${#resource_id_array[@]}  \r"		
		curl --no-progress-meter --request GET \
			--url ${curl_url} \
			--header 'content-type: application/json; charset=UTF-8' \
			--header "x-redlock-auth: ${PC_JWT}" > "${JSON_OUTPUT_LOCATION}/02_alerts_${counter}.json" &
		
		counter=$(( counter + 1 ))
	done #end for loop
	sleep ${curl_break}
	
	current=$(date +%s)
	progress=$(($current-$start))
	trigger=$(expr $progress % $jwt_token_timeout)

	#Refresh Token if TImer is almost up
	if [[ $trigger -gt $jwt_token_refresh ]]; then
		printf "%s\n" ${SPACER}
		printf "Refreshing JWT Token Refresh\n"
	
		PC_JWT_RESPONSE=$(curl -s --request GET \
			--url "${PC_APIURL}/auth_token/extend" \
			--header 'Accept: application/json; charset=UTF-8' \
			--header 'Content-Type: application/json charset=UTF-8' \
			--header "x-redlock-auth: ${PC_JWT}") \
		
		PC_JWT=$(printf %s "${PC_JWT_RESPONSE}" | jq -r '.token')
	 
		 if [ -z "${PC_JWT}" ]; then
			printf "JWT not recieved, recommending you check your variable assignment\n";
			printf "%s\n" ${SPACER}
			exit;
		else
			printf "JWT Recieved\n"
			printf "%s\n" ${SPACER}
			sleep $((jwt_token_timeout-trigger))
		fi #end if JWT exisit
	fi #end token refresh. 
done #end while/do

printf '%s\n' ${SPACER}

printf '%s\n' "alertId,alertStatus,policyName,policyDesc,policySeverity,cloudType,resourceId,accountId,resourceName,accountName,regionId,regionName,service,resourceType,resourceApiName" > "${OUTPUT_LOCATION}/cloud_resources_with_alerts_$date.csv"

cat ${JSON_OUTPUT_LOCATION}/02_alerts_*.json | jq -r '.items[] | {"alertId" : .id, "alertStatus" : .status, "policyName" : .policy.name, "policyDesc" : .policy.description, "policySeverity": .policy.severity, "cloudType": .resource.cloudType, "resourceId": .resource.id, "accountId": .resource.accountId,  "resourcenName": .resource.name,  "accountName": .resource.account,  "regionId": .resource.regionId,  "resourceRegion": .resource.region,  "cloudServiceName": .resource.cloudServiceName, "resourceType": .resource.resourceType, "resourceApiName": .resource.resourceApiName }' | jq -r '[.[]] | @csv' >> "${OUTPUT_LOCATION}/cloud_resources_with_alerts_$date.csv"

number_of_alerts=($(cat ${JSON_OUTPUT_LOCATION}/02_alerts_*.json | jq -r '.items[].id'))


printf '%s alerts found from %s resources\n' ${#number_of_alerts[@]} ${#resource_id_array[@]}
printf '%s\n' "Full Report located at ${OUTPUT_LOCATION}/cloud_resources_with_alerts_$date.csv"

rm -f ${JSON_OUTPUT_LOCATION}/*.json

printf '%s\n' ${DIVIDER}
end=$(date +%s)
end_time=$(date +%Y%m%d-%H:%M:%S)
duration=$end-$start

printf "Start Time: ${start_time}\n"
printf "End Time: ${end_time}\n"
printf "%s\n" ${SPACER}
printf "Completed in $(((duration/60))) minutes and $((duration%60)) seconds\n"
printf "Elapsed Time: $(($end-$start)) seconds\n"
printf '%s\n' ${DIVIDER}
printf "Complete - Exiting\n"
printf '%s\n' ${DIVIDER}
exit
#end
