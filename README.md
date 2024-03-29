# prisma-cloud-scripts
repo for Prisma Cloud Scripts leveraging published API

## [Search All APIs](https://github.com/JonHurtt/prisma-cloud-scripts/blob/main/search_all_apis.sh)
Iterate through all supported RQL config API Endpoints with suffix of choice to generate CSV of all resources that match critiera

### Input: 

- Define access_key & secret_key and pc_api_url in script to your Prisma Cloud Tenant 
- Base RQL Statement - config from "cloud.resource where api.name = [API ENDPOINT]
- Configurable RQL Suffix Example: [AND resource.status = Active AND json.rule='$.tags[*] size equals 0'"]

### Output
Will Create a Folder in format of "YYMMDD-HHMM" With two sub-folders (**reports** & **rql_output**)

reports will have the following:

- **CSV of matched Resources** with csv format of [#cloudtype, api_endpoint, id, accountId, name, accountName, regionId, regionName, service, resourceType]
- **CSV of API Endpoint Stats** Provides high level view of which endpoints produced the most resources and the RQL query for reference
[#api_endpoint_id, cloudType, api_endpoint, resource_count, rql_query]
- **JSON File of all Resources**
resources_json_file.json - All Resources in JSON Format

rql_output will have the following:

- **rql_response_XXX.json**
API responses for each RQL executed for reference. XXX is the "api_endpoint_id" 
- **_api_endpoints_{csp}.json**
list of all the API endpoints for each CSP {aws, azure, gcp, oci & alibaba}

More Efficent Version to look at Cloud Resources without any Tag Value is located here - [find_cloud_resources_without_tags.sh](https://github.com/PaloAltoNetworks/prisma_channel_resources/blob/main/prisma_bash_toolbox-main/find_cloud_resources_without_tags.sh)

## [Find Resources with Alerts](https://github.com/JonHurtt/prisma-cloud-scripts/blob/main/find_resources_with_alerts.sh)
Iterate through all supported RQL config API Endpoints looking for all active resources with defined key value pair of KVP_KEY:KVP_VALUE and then retrieve all alerts for resources matching key value pair

### Input: 

- Define PC_ACCESSKEY & PC_SECRETKEY and PC_APIURL in script to your Prisma Cloud Tenant 
- Define KVP_KEY and KVP_VALUE
- For faster results prune csp_pfix_array to only CSP prefix that match your environment
- Define RESOURCE_TIME_AMOUNT and RESOURCE_TIME_UNIT as time which resources exisit (eg 24 hour or 7 day)
- Define ALERT_TIME_AMOUNT and ALERT_TIME_UNIT as time which alerts exisit (eg 24 hour or 7 day)
- If you want preserve the json outputs remove line 220 "rm -f ${JSON_OUTPUT_LOCATION}/*.json"

### Output
- Will Create a folder "output" and "output/json"
- Create file "all_cloud_resources_YYYYMMDD.csv" with all active resources matching key value pair
- Create file "cloud_resources_with_alerts_YYYYMMDD.csv" with alerts of all active resources matching key value pair

## [List all Data Resources](https://github.com/JonHurtt/prisma-cloud-scripts/blob/main/list_all_data_resources.sh)

### Input: 

- Define access_key & secret_key and pc_api_url in script to your Prisma Cloud Tenant 

### Output
Will create a single CSV with list of all data stores from accounts with Data Securty (view from Data Security Settings) enabled to allow for more advanced caluations 



## [Alert Operations Report](https://github.com/JonHurtt/prisma-cloud-scripts/blob/main/alert-ops-report.sh)

### Input: 

- Define access_key & secret_key and pc_api_url in script to your Prisma Cloud Tenant
- Define Time Unit & Time Intervals

### Output
Will create a summary CSV with totals of alerts of by time unit/interval and indivual .csv files for each time unit/interval/alert status.

## Additional Links and Information
[Prisma Cloud Channel Resources](https://github.com/PaloAltoNetworks/prisma_channel_resources)

More Bash Scripts can be found here: [Prisma Bash Toolbox](https://github.com/kyle9021/prisma_channel_resources/tree/main/prisma_bash_toolbox-main)
