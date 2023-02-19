#!/bin/bash
# Written By Jonathan R. Hurtt
# Tested on Feb 15th, 2023 on prisma_cloud_enterprise_edition

# Requires jq to be installed sudo apt-get install jq


# Access key should be created in the Prisma Cloud Console under: Settings > Access keys
# Decision to leave access keys in the script to simplify the workflow
# Recommendations for hardening are: store variables in a secret manager of choice or export the access_keys/secret_key as env variables in a separate script. 

# Place the access key and secret key between "<ACCESS_KEY>", <SECRET_KEY> marks respectively below.


# Only variable(s) needing to be assigned by the end-user
# Found under compute > system > Utilities > path to Console should look like: https://region.cloud.twistlock.com/region-account

spacer="\033[0;34m========================================================================================================================================================================\033[0m"


# Create access keys in the Prisma Cloud Enterprise Edition Console
# access_key="<PRISMA_ENTERPRISE_EDITION_ACCESS_KEY>"
# secret_key="<PRISMA_ENTERPRISE_EDTION_SECRET_KEY>"

#Prisma Cloud Stack URL
pc_api_url="https://api4.prismacloud.io"

#RQL suffix, what will be appeneded to all RQL queries 
rql_suffix=" AND resource.status = Active AND json.rule='$.tags[*] size equals 0'"
#rql_suffix=" AND json.rule='$.tags[*] size equals 0'"
#rql_suffix=" AND json.rule='$.tags[*] size greater than 1'"

# list of all the supported CSPs
all_csp_pfix=("aws-" "azure-" "gcp-" "gcloud-" "alibaba-" "oci-")

#Amount of Time the JWT is valid (10 min) adjust refresh to lower number with slower connections
jwt_token_timeout=600
jwt_token_refresh=595

#ID counter for the # each API Endpoint/RQL Query
api_endpoint_id=0

#Counter to keep track of # of resources that match RQL Query
total_resource_count=0

#Variable for all CSP API Endpoints
all_api_endpoints=""

#Date Format to use for folder creation
date=$(date +%Y%m%d-%H%M)

# No edits needed below this line
error_and_exit() {
  echo
  echo "ERROR: ${1}"
  echo
  exit 1
}

#Begin Applicaiton Timer
echo -e $spacer
start_time=$(date +%Y%m%d-%H:%M:%S)
echo -e "\033[1;34mStart Time: ${start_time}\033[0m"
start=$(date +%s)
echo -e $spacer

#Status Update
echo -e "\033[1;33mLogging into Prisma Cloud\033[0m"
echo -e $spacer

auth_body_single="
{
 'username':'${access_key}', 
 'password':'${secret_key}'
}"

auth_body="${auth_body_single//\'/\"}"

# debugging to ensure jq is installed
if ! type "jq" > /dev/null; then
  error_and_exit "\033[1;31mjq not installed or not in execution path, jq is required for script execution.\033[0m"
fi

# debugging to ensure the variables are assigned correctly not required
if [[ ! $pc_api_url =~ https.*prismacloud.io.* ]]; then
  echo -e $spacer;
  echo "\033[1;31mpc_api_url variable isn't formatted or assigned correctly; it should look like: https://api{0|1|2|3|4}.prismacloud.io\033[0m";
  echo -e $spacer
  exit;
fi

if [[ ! $access_key =~ ^.{35,40}$ ]]; then
  echo "\033[1;31mcheck the access_key variable because it doesn't appear to be the correct length\033[0m";
  echo -e $spacer
  exit;
fi

if [[ ! $secret_key =~ ^.{27,31}$ ]]; then
  echo "\033[1;31mcheck the access_key variable because it doesn't appear to be the correct length\033[0m";
  exit;
fi

#Obtain JWT
jwt_query=$(curl -s --url "${pc_api_url}/login" \
                 --header 'Accept: application/json; charset=UTF-8' \
                 --header 'Content-Type: application/json; charset=UTF-8' \
                 --data "${auth_body}")

#Parse CURL Response to find Token
jwt=$(printf %s "$jwt_query" | jq -r '.token' )

if [ -z "${jwt}" ]; then
	echo -e $spacer
	echo -e "\033[32mJSON Web Token not recieved, recommending you check your variable assignment\033[0m";
	echo -e $spacer
	exit;
else
	echo -e $spacer
	echo -e "\033[0;32mJSON Web Token Recieved\033[0m"
  echo -e $spacer
fi


echo -e $spacer
echo -e "\033[0;33mBuilding Supported CSP List\033[0m"
echo -e $spacer

#Make Root Directory
root_dir="./${date}"
mkdir $root_dir
echo -e "\033[0;33mRoot Directory Created ${root_dir}\033[0m"

#Make RQL Output Directory
rql_output_dir="${root_dir}/rql_output"
mkdir $rql_output_dir
echo -e "\033[0;33mRQL Output Directory Created ${rql_output_dir}\033[0m"

#Make Report Directory
report_dir="${root_dir}/reports"
mkdir $report_dir
echo -e "\033[0;33mReport Directory Created ${report_dir}\033[0m"

#Create all Files Names
all_api_endpoints_list_file="${report_dir}/${date}_all_api_endpoints.csv"
resources_json_file="${report_dir}/${date}_resources.json"
resources_csv_file="${report_dir}/${date}_resources_report.csv"

all_api_endpoints_stats_file="${report_dir}/${date}_all_api_endpoints_stats_report.csv"

#Build Header for CSV Output
resource_header="#cloudtype,endpoint,id,accountId,name,accountName,regionId,regionName,service,resourceType"
api_endpoint_stats_header="#api_endpoint_id,cloudType,endpoint,resource_count,rql_query"
echo ${api_endpoint_stats_header} > ${all_api_endpoints_stats_file}


#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#Loop through all CSPs and find all API Endpoints
#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
echo -e $spacer
echo -e "\033[0;33mRetrieving updated list of all APIs\033[0m"
echo -e $spacer

for csp in ${all_csp_pfix[@]}; do
  csp_api_endpoints=""
  
  #Building Data Payload for Suggestion Query
  echo
  echo -e $spacer
  echo -e "\033[0;33mCapturing APIs for '${csp}'..."  
  data_query="config from cloud.resource where api.name = ${csp}"
  data_payload="{'query':'${data_query}'}"
  echo -e $spacer
  
  #Displaying Data Payload
  #echo -e "\033[0;33mRQL Query Data Payload for ${csp}\033[0m"  
  #echo $data_payload
  #echo -e $spacer
  
  #Creating File for API Endpoints and executing API Call via CURL
  touch ${rql_output_dir}/_api_endpoints_${csp}list.json
  curl  -s --url "${pc_api_url}/search/suggest" \
       --header "accept: application/json; charset=UTF-8" \
       --header "content-type: application/json" \
       --header "x-redlock-auth: ${jwt}" \
       --data "${data_payload}" > ${rql_output_dir}/_api_endpoints_${csp}list.json

  echo -e $spacer
  echo "Curl Complete: Output saved to ${rql_output_dir}/_api_endpoints_${csp}list.json"
  echo -e $spacer
  
  echo "Proccessing RQL Query to find up to date API endpoints for ${csp}..."
  echo -e $spacer
  
  #echo -e "\033[0;33mList of API Endpoints for '${csp}'\033[0m"
  #echo -e $spacer
  #cat ${rql_output_dir}/_api_endpoints_${csp}list.json  | jq -r '.suggestions[]'
  #echo -e $spacer

  echo -e "\033[0;33mSuccessfully Captured APIs for '${csp}'\033[0m"
  echo -e $spacer
  
  echo -e "\033[0;33mReading CSP API Endpoint for ${csp}...\033[0m"
  csp_api_endpoints=$(cat ${rql_output_dir}/_api_endpoints_${csp}list.json  | jq -r '.suggestions[]')
  echo -e $spacer
  
  echo -e "\033[0;33mIterating through all APIs and bulidig RQLs and appending \"${rql_suffix}\"\033[0m"
  echo -e $spacer
  
  #+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  #Loop through all API Endpoints to retrieve list of resources
  #+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++  
  for endpoint in ${csp_api_endpoints[@]}; do
  
    current=$(date +%s)
    progress=$(($current-$start))
    trigger=$(expr $progress % $jwt_token_timeout)
    
    echo -e $spacer
    echo -e "\033[1;37mCurrent Execution Timer (sec) - ${progress} (${trigger})\033[0m"
    echo -e $spacer
    echo

    #Refresh Token if TImer is almost up
    if [[ $trigger -gt $jwt_token_refresh ]]; then
      echo -e $spacer
      echo -e "\033[1;33mJWT Token Refresh\033[0m"
      #read -p "Press [Enter] to continue.."
      #echo -e $spacer
      
      #echo -e "\033[0;33mJWT Token\033[0m"
      #echo $jwt
      #echo -e $spacer
      
      jwt_query=$(curl -s --url "${pc_api_url}/auth_token/extend" \
                       --header 'Accept: application/json; charset=UTF-8' \
                       --header 'Content-Type: application/json; charset=UTF-8' \
                       --header "x-redlock-auth: ${jwt}") \
    
      #echo -e "\033[0;33mJWT Query Response\033[0m"
      #echo $jwt_query
      #echo -e $spacer
      
      #Parse CURL Response to find Token
      jwt=$(printf %s "$jwt_query" | jq -r '.token' )
      
      #echo -e "\033[0;33mJWT Token\033[0m"
      #echo $jwt
      #echo -e $spacer
      
      if [ -z "${jwt}" ]; then
        echo -e "\033[1;33mJSON Web Token not recieved, recommending you check your variable assignment\033[0m";
        echo -e $spacer
        echo
        exit;
      else
        echo -e "\033[1;33mJSON Web Token Recieved\033[0m"
        echo -e $spacer
        sleep $((jwt_token_timeout-jwt_token_refresh))
        echo
      fi
    fi
    
    echo -e $spacer
    echo -e "\033[1;36m[#${api_endpoint_id}] - Creating RQL for ${endpoint}...\033[0m"
    echo -e $spacer
    resource_count=0
      
    rql_query="config from cloud.resource where api.name = ${endpoint}${rql_suffix}"
    #echo $rql_query
    #echo -e $spacer
    
    rql_payload=$(cat <<EOF
    {
     "query":"${rql_query}",
     "timeRange": {
       "type": "relative",
       "value":{
         "unit":"hour",
         "amount":24
       }
     }
    }
    EOF)
    
    #echo -e "\033[0;33m[#${api_endpoint_id}] - Executing API and saving to Response to ${rql_output_dir}/rql_response_${api_endpoint_id}.json\033[0m"
    #echo -e $spacer
    
    
    touch ${rql_output_dir}/rql_response_${api_endpoint_id}.json
    curl -s --url "${pc_api_url}/search/config" \
         --header "accept: application/json; charset=UTF-8" \
         --header "content-type: application/json" \
         --header "x-redlock-auth: ${jwt}" \
         --data "${rql_payload}" > ${rql_output_dir}/rql_response_${api_endpoint_id}.json
    
  
    echo -e "\033[1;31m[#${api_endpoint_id}] - RQL Response Snippet"
    head -c 160 ${rql_output_dir}/rql_response_${api_endpoint_id}.json
    echo 
    echo -e $spacer
        
    echo "[#${api_endpoint_id}] - Proccessing RQL Query for ${endpoint}..."
    echo -e $spacer
    #Get Resourse Count from JSON output and then add it to total resource count
    cloudType=$(cat ${rql_output_dir}/rql_response_${api_endpoint_id}.json | jq -r '.cloudType')
    resource_count=$(cat ${rql_output_dir}/rql_response_${api_endpoint_id}.json | jq -r '.data.totalRows')
    total_resource_count=$((total_resource_count+resource_count))

    #echo -e "\033[1;33m[#${api_endpoint_id}] - cloudType: ${cloudType}\033[0m"
    echo -e "\033[1;37m[#${api_endpoint_id}] - Number of Resources: ${resource_count}\033[0m"
    echo -e "\033[1;33m[#${api_endpoint_id}] - Total Number of Resources: ${total_resource_count}\033[0m"
    
    api_endpoint_stats="${api_endpoint_id},${cloudType},${endpoint},${resource_count},${rql_query}"
    echo ${api_endpoint_stats} >> ${all_api_endpoints_stats_file}
    echo -e $spacer
  
    cat ${rql_output_dir}/rql_response_${api_endpoint_id}.json | jq -r '.data.items[] | {"cloudtype": .cloudType, "endpoint": "'${endpoint}'", "id": .id, "accountId": .accountId,  "name": .name,  "accountName": .accountName,  "regionId": .regionId,  "regionName": .regionName,  "service": .service, "resourceType": .resourceType }' >> ${resources_json_file}
    
    echo -e "\033[1;36m[#${api_endpoint_id}] - Results for ${endpoint} stored in ${resources_json_file}\033[0m"  
    echo -e $spacer
    echo
    echo
    
    #Incrementing API Endpiont 
    ((api_endpoint_id++))
  done
  #+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  #end of Loop -  for endpoint
  #+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

echo
echo -e $spacer
echo -e "\033[0;33mSuccessfully Executed all RQL for all APIs Endpoints for '${csp}'\033[0m"
echo -e $spacer
echo

#read -p "Press [Enter] to continue.."
#echo -e $spacer
    
done
#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#end of Loop - for csp 
#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

echo
echo -e $spacer
echo -e "\033[0;33mComplete Executing All RQL Queries for all CSPs\033[0m"
echo -e $spacer

#read -p "Press [Enter] to continue.."
#echo -e $spacer


echo -e "\033[1;33mPreparing Output for ${resources_csv_file}...\033[0m"
echo -e $spacer
echo -e "\033[1;31mTotal Number of API Endpoints serached: ${api_endpoint_id}\033[0m"
echo -e "\033[1;31mTotal Number of Resources: ${total_resource_count}\033[0m"
echo -e $spacer

echo ${resource_header} > ${resources_csv_file}
cat ${resources_json_file} | jq -r '[.[]] | @csv ' >> ${resources_csv_file}


echo -e "\033[1;33mAll Files located in ${report_dir}"
echo -e $spacer
end=$(date +%s)
end_time=$(date +%Y%m%d-%H:%M:%S)
duration=$end-$start

echo -e "\033[1;34mStart Time: ${start_time}\033[0m"
echo -e "\033[1;34mEnd Time: ${end_time}\033[0m"
echo -e $spacer
echo -e "\033[1;37mCompleted in $(((duration/60))) minutes and $((duration%60)) seconds\033[0m"
echo -e "\033[1;37mElapsed Time: $(($end-$start)) seconds\033[0m"
echo -e $spacer
echo -e "\033[1;31mComplete - Exiting\033[0m"
echo -e $spacer
exit