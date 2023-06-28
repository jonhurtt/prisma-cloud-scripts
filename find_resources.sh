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
csp_pfix_array=("aws-" "azure-")

#Define Time Amount and Units for search
TIME_AMOUNT=24
TIME_UNIT="hour"

##############################################################################

TOTAL_RESOURCES=0
TOTAL_ALERTS=0
TOTAL_RESOURCES_WITH_ALERTS=0


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
PC_JWT_RESPONSE=$(curl --no-progress-meter \
				   --request POST \
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
fi

#Create CSV Headers
printf '%s\n' "cloudType,id,accountId,name,accountName,regionId,regionName,service,resourceType" > "${OUTPUT_LOCATION}/all_cloud_resources_${date}.csv"
printf '%s\n' "alertId,alertStatus,policyName,policyDesc,policySeverity,cloudType,resourceId,accountId,resourceName,accountName,regionId,regionName,service,resourceType,resourceApiName" > "${OUTPUT_LOCATION}/cloud_resources_with_alerts_$date.csv"

printf "%s\n" ${DIVIDER}
#Iterate through each of the CSP Prefix Array to capture all available API endpoints
for csp_indx in "${!csp_pfix_array[@]}"; do \
	printf "|- Assembling list of available APIs for %s...\n" ${csp_pfix_array[csp_indx]}
	config_request_body=$(cat <<EOF
	{
		  "query":"config from cloud.resource where api.name = ${csp_pfix_array[csp_indx]}",
		  "timeRange":{
			"type":"relative",
			"value":{
			   "unit":"${TIME_UNIT}",
			   "amount":${TIME_AMOUNT}
			}
		  }
	}
	EOF
	)
	
	curl --no-progress-meter --url "${PC_APIURL}/search/suggest" \
		-w '{"curl_http_code": %{http_code}}' \
		--header "accept: application/json; charset=UTF-8" \
		--header "content-type: application/json" \
		--header "x-redlock-auth: ${PC_JWT}" \
		--data "${config_request_body}" > "${JSON_OUTPUT_LOCATION}/00_api_suggestions_${csp_indx}.json"
		
	#Build Array with all available API Endpoints for CSP
	rql_api_array=($(cat ${JSON_OUTPUT_LOCATION}/00_api_suggestions_${csp_indx}.json | jq -r '.suggestions[]?'))
	
	printf '|- %s%s available API endpoints\n' ${csp_pfix_array[csp_indx]} ${#rql_api_array[@]}
	printf "%s\n" ${SPACER}
	
	#Iterate through all available API endpoints for CSP looking for Resources
	for api_query_indx in "${!rql_api_array[@]}"; do \
		current=$(date +%s)	
		progress=$(($current-$start))
		trigger=$(expr $progress % $jwt_token_timeout)
		
		#Refresh Token if TImer is almost up
		if [[ $trigger -gt $jwt_token_refresh ]]; then
			printf "%s\n" ${SPACER}
			printf "|- Refreshing JWT Token Refresh\n"
			
			PC_JWT_RESPONSE=$(curl --no-progress-meter --request GET \
				--url "${PC_APIURL}/auth_token/extend" \
				--header 'Accept: application/json; charset=UTF-8' \
				--header 'Content-Type: application/json charset=UTF-8' \
				--header "x-redlock-auth: ${PC_JWT}") \
			
			
			PC_JWT=$(printf %s "${PC_JWT_RESPONSE}" | jq -r '.token')
		 
			 if [ -z "${PC_JWT}" ]; then
				printf "|- JWT not recieved, recommending you check your variable assignment\n";
				printf "%s\n" ${DIVIDER}				
				exit;
			else
				sleep $((jwt_token_timeout-trigger))
			fi #end if JWT exisit
		fi #end token refresh. 
		
		printf "|- [api:%s/%s] Searching for resources via %s api with tags containing key:value of {%s:%s} ... \n" $api_query_indx ${#rql_api_array[@]} ${rql_api_array[api_query_indx]} ${KVP_KEY} ${KVP_VALUE}
		
		rql_request_body=$(cat <<EOF
		{
			  "query":"config from cloud.resource where api.name = ${rql_api_array[api_query_indx]} AND resource.status = Active AND json.rule = tags[?(@.key=='${KVP_KEY}')].value equals ${KVP_VALUE}",
			  "timeRange":{
				"type":"relative",
				"value":{
				"unit":"${TIME_UNIT}",
				"amount":${TIME_AMOUNT}
				}
			  }
		}
		EOF
		)
	
		config_HTTP_RESPONSE_CODE=$(curl --no-progress-meter --url "${PC_APIURL}/search/config" \
			--write-out %{http_code}\
			--header "accept: application/json; charset=UTF-8" \
			--header "content-type: application/json" \
			--header "x-redlock-auth: ${PC_JWT}" \
			--data "${rql_request_body}" \
			--output "${JSON_OUTPUT_LOCATION}/01_${csp_indx}_${api_query_indx}_api_query.json")
		
		#echo -ne "-->[${trigger}|${config_HTTP_RESPONSE_CODE}] Executing API ${api_query_indx} of ${#rql_api_array[@]}  \r"
			
		if ! [[ "$config_HTTP_RESPONSE_CODE" =~ ^2 ]]; then
			printf '%s\n' ${DIVIDER}		
			printf "ERROR: server returned HTTP code $config_HTTP_RESPONSE_CODE during search for resources (%s)\n" ${rql_api_array[api_query_indx]}
			printf '%s\n' ${DIVIDER}
			read -p "Press [Enter] to end script.."
			exit;
		fi
	
		RESOURCES=$(cat ${JSON_OUTPUT_LOCATION}/01_${csp_indx}_${api_query_indx}_api_query.json | jq '. | .data.totalRows')
		TOTAL_RESOURCES=$((TOTAL_RESOURCES+RESOURCES))

		#if Resources count is greater than 0, serach for alerts associated with Resource
		if [[ $RESOURCES -gt 0 ]]; then
			
			printf '%s\n' ${SPACER}
			printf '|- [api:%s/%s] %s => %s resource(s) of %s total\n' $api_query_indx ${#rql_api_array[@]} ${rql_api_array[api_query_indx]}  ${RESOURCES} ${TOTAL_RESOURCES}
			printf '%s\n' ${SPACER}
			
			resource_id_array=($(cat ${JSON_OUTPUT_LOCATION}/01_${csp_indx}_${api_query_indx}_api_query.json  | jq -r '. | .data.items[] | .id'))
		
			printf "|- Finding all alerts for resources found via %s matching key:value of {%s:%s} ...\n" ${rql_api_array[api_query_indx]} ${KVP_KEY} ${KVP_VALUE}
			#Iterate through all resources and retrieve Alerts
			for resource_id_indx in "${!resource_id_array[@]}"; do \
				current=$(date +%s)
				progress=$(($current-$start))
				trigger=$(expr $progress % $jwt_token_timeout)
							
				#Refresh Token if Timer is almost up
				if [[ $trigger -gt $jwt_token_refresh ]]; then
					printf "%s\n" ${SPACER}
					printf "Refreshing JWT Token Refresh\n"
					
					PC_JWT_RESPONSE=$(curl --no-progress-meter --request GET \
						--url "${PC_APIURL}/auth_token/extend" \
						--header 'Accept: application/json; charset=UTF-8' \
						--header 'Content-Type: application/json charset=UTF-8' \
						--header "x-redlock-auth: ${PC_JWT}") \
						
					PC_JWT=$(printf %s "${PC_JWT_RESPONSE}" | jq -r '.token')
					
					if [ -z "${PC_JWT}" ]; then
						printf "JWT not recieved, recommending you check your variable assignment\n";
						printf "%s\n" ${DIVIDER}
						exit;
					else
						sleep $((jwt_token_timeout-trigger))
					fi #end if JWT exisit
				fi #end token refresh. 
				
				alert_HTTP_RESPONSE_CODE=$(curl --no-progress-meter --request GET \
					--url "${PC_APIURL}/v2/alert?detailed=true&timeType=relative&timeAmount=${TIME_AMOUNT}&timeUnit=${TIME_UNIT}&resource.id=${resource_id_array[resource_id_indx]}" \
					--write-out %{http_code}\
					--header 'content-type: application/json; charset=UTF-8' \
					--header "x-redlock-auth: ${PC_JWT}" \
					--output "${JSON_OUTPUT_LOCATION}/03_${csp_indx}_alert_${resource_id_indx}.json")
				
				echo -ne "|-- [${trigger}|${alert_HTTP_RESPONSE_CODE}] Investigating resource ${resource_id_indx} of ${#resource_id_array[@]}  \r"	
				
				if ! [[ "$alert_HTTP_RESPONSE_CODE" =~ ^2 ]]; then
					printf '%s\n' ${DIVIDER}
					printf "ERROR: server returned HTTP code $alert_HTTP_RESPONSE_CODE during investigation of alerts (%s)\n" ${resource_id_array[resource_id_indx]}
					printf '%s\n' ${DIVIDER}
					read -p "Press [Enter] to end script.."
					exit;
				fi
				
				ALERTS=$(cat ${JSON_OUTPUT_LOCATION}/03_${csp_indx}_alert_${resource_id_indx}.json | jq '. | .totalRows')
				TOTAL_ALERTS=$((TOTAL_ALERTS+ALERTS))
				
				#IF Alerts > 0 then increment count (total resources with alerts) and add to CSV		
				if [[ "$ALERTS" -gt 0 ]]; then
					TOTAL_RESOURCES_WITH_ALERTS=$((TOTAL_RESOURCES_WITH_ALERTS+1))
					
					printf '|-- [resource:#%s/%s] Resource ID %s has %s of the total %s alerts\n' $resource_id_indx ${#resource_id_array[@]} ${resource_id_array[resource_id_indx]} ${ALERTS} ${TOTAL_ALERTS}
					
					cat ${JSON_OUTPUT_LOCATION}/03_${csp_indx}_*.json | jq -r '.items[] | {"alertId" : .id, "alertStatus" : .status, "policyName" : .policy.name, "policyDesc" : .policy.description, "policySeverity": .policy.severity, "cloudType": .resource.cloudType, "resourceId": .resource.id, "accountId": .resource.accountId,  "resourcenName": .resource.name,  "accountName": .resource.account,  "regionId": .resource.regionId,  "resourceRegion": .resource.region,  "cloudServiceName": .resource.cloudServiceName, "resourceType": .resource.resourceType, "resourceApiName": .resource.resourceApiName }' | jq -r '[.[]] | @csv' >> "${OUTPUT_LOCATION}/cloud_resources_with_alerts_$date.csv"
				fi #end of if Alerts > 0
			done #end iteration through resources
			printf '%s\n' ${SPACER}
			printf '%s Alerts across %s Resources [%s total resources]\n' ${TOTAL_ALERTS} ${TOTAL_RESOURCES_WITH_ALERTS} ${TOTAL_RESOURCES}
			printf '%s\n' ${SPACER}
		fi	# end of if Resources > 0
	done #end iteration through api endpoints

	#Create JSON for all Resoruces that match criteria
	cat ${JSON_OUTPUT_LOCATION}/01_${csp_indx}_*.json | jq -r '.data.items[] | {"cloudType": .cloudType, "id": .id, "accountId": .accountId,  "name": .name,  "accountName": .accountName,  "regionId": .regionId,  "regionName": .regionName,  "service": .service, "resourceType": .resourceType}' > "${JSON_OUTPUT_LOCATION}/02_${csp_indx}_all_cloud_resources_${date}.json"
	
	cat ${JSON_OUTPUT_LOCATION}/02_${csp_indx}_all_cloud_resources_${date}.json | jq -r '. | {"cloudType": .cloudType, "id": .id, "accountId": .accountId,  "name": .name,  "accountName": .accountName,  "regionId": .regionId,  "regionName": .regionName,  "service": .service, "resourceType": .resourceType}' | jq -r '[.[]] | @csv' >> "${OUTPUT_LOCATION}/all_cloud_resources_${date}.csv"
done #end iteration through CSP prefix

#Output Summary
printf '%s\n' ${SPACER}
printf '%s Alerts across %s Resources across %s total resources\n' ${TOTAL_ALERTS} ${TOTAL_RESOURCES_WITH_ALERTS} ${TOTAL_RESOURCES}
printf '%s\n' "Inventory Report located at ${OUTPUT_LOCATION}/all_cloud_resources_${date}.csv"
printf '%s\n' ${SPACER}

#rm -f ${JSON_OUTPUT_LOCATION}/*.json

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
