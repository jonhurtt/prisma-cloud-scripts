# prisma-cloud-scripts
repo for Prisma Cloud Scripts leveraging published API

[Search All APIs](https://github.com/JonHurtt/prisma-cloud-scripts/blob/main/search_all_apis.sh) - Iterate through all supported RQL config API Endpoints with suffix of choice to generate CSV of all resources that match critiera

eg: 
Base RQL Statement - config from "cloud.resource where api.name = [API ENDPOINT]

### Input: 

Enter access_key & secret_key in script to your Prisma Cloud Tenant (pc_api_url) 

Configurable RQL Suffix Example: [AND resource.status = Active AND json.rule='$.tags[*] size equals 0'"]

### Output
Will Create a Folder in format of "YYMMDD-HHMM" With two sub-folders (**reports** & **rql_output**)

reports will have the following:

**CSV of matched Resources**
with [#cloudtype, api_endpoint, id, accountId, name, accountName, regionId, regionName, service, resourceType]

**CSV of API Endpoint Stats**
Provides high level view of which endpoints produced the most resources and the RQL query for reference
[#api_endpoint_id, cloudType, api_endpoint, resource_count, rql_query]

**JSON File of all Resources**
resources_json_file.json - All Resources in JSON Format

rql_output will have the following:

**rql_response_XXX.json**
API responses for each RQL executed for reference. XXX is the "api_endpoint_id" 

**_api_endpoints_{csp}.json**
list of all the API endpoints for each CSP {aws, azure, gcp, oci & alibaba}

More Efficent Version located here - [find_cloud_resources_without_tags.sh](https://github.com/PaloAltoNetworks/prisma_channel_resources/blob/main/prisma_bash_toolbox-main/find_cloud_resources_without_tags.sh)

More Bash Scripts can be found here: [Prisma Bash Toolbox](https://github.com/kyle9021/prisma_channel_resources/tree/main/prisma_bash_toolbox-main)
