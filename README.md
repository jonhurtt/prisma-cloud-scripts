# prisma-cloud-scripts
repo for Prisma Cloud Scripts leveraging published API

[Search All APIs](https://github.com/JonHurtt/prisma-cloud-scripts/blob/main/search_all_apis.sh) - Iterate through all supported RQL config API Endpoints with suffix of choice to generate CSV of all resources that match critiera

eg: 
Base RQL Statement - config from "cloud.resource where api.name = [API ENDPOINT]

Configurable RQL Suffix Example: [AND resource.status = Active AND json.rule='$.tags[*] size equals 0'"]

More Efficent Version located here - [find_cloud_resources_without_tags.sh](https://github.com/PaloAltoNetworks/prisma_channel_resources/blob/main/prisma_bash_toolbox-main/find_cloud_resources_without_tags.sh)


More Bash Scripts can be found here: [Prisma Bash Toolbox](https://github.com/kyle9021/prisma_channel_resources/tree/main/prisma_bash_toolbox-main)
