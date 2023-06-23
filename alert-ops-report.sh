#!/usr/bin/env bash
#------------------------------------------------------------------------------------------------------------------#
# Written By Jonathan Hurtt
#
# REQUIREMENTS: 
# Requires jq to be installed: 'sudo apt-get install jq'
#

source ./func/func.sh

#Secrets
PC_APIURL="REDACTED"
PC_ACCESSKEY="REDACTED"
PC_SECRETKEY="REDACTED"

#Define Time Intervals (minute, hour, day, week, month, year)
TIME_AMOUNT_array=(24 48 1 30 3)
TIME_UNIT_array=("hour" "hour" "week" "day" "month")

#Define Folder Locations
OUTPUT_LOCATION=./output
JSON_OUTPUT_LOCATION=./output/json

SPACER="==--==--==--==--==--==--==--==--==--==--==--==--==--==--==--==--==--==--==--==--==--==--"
DIVIDER="+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"

printf '%s\n\n' ${DIVIDER}
printf '%s\n\n' ${DIVIDER}

#Define Auth Payload for JWT
AUTH_PAYLOAD=$(cat <<EOF
{"username": "$PC_ACCESSKEY", "password": "$PC_SECRETKEY"}
EOF
)

#API Call for JWT
PC_JWT_RESPONSE=$(curl --request POST \
				   --url "$PC_APIURL/login" \
				   --header 'Accept: application/json; charset=UTF-8' \
				   --header 'Content-Type: application/json; charset=UTF-8' \
				   --data "${AUTH_PAYLOAD}")

quick_check "/login"

PC_JWT=$(printf %s "$PC_JWT_RESPONSE" | jq -r '.token')

ALERT_STATUS_array=("open" "snoozed" "dismissed" "resolved")
TOTAL_ROWS_SUMMARY=()

COUNT_ALERT_STATUS=${#ALERT_STATUS_array[@]}
COUNT_TIME_AMOUNT=${#TIME_AMOUNT_array[@]}

#Iterate through Time Amounts
for index in "${!TIME_AMOUNT_array[@]}"; do 
	TIME_AMOUNT=${TIME_AMOUNT_array[index]}
	TIME_UNIT=${TIME_UNIT_array[index]}
	
	#Iterate though Alert Status
	for status in "${!ALERT_STATUS_array[@]}"; do 
		printf '%s\n\n' ${DIVIDER}
		printf 'Finding Alerts over %s %s with Alert Status of %s\n' ${TIME_AMOUNT_array[index]} ${TIME_UNIT_array[index]} ${ALERT_STATUS_array[status]}
		ALERT_STATUS=${ALERT_STATUS_array[status]}
		
		#Executing API and storing output in output/json file
		printf '%s\n' ${SPACER}
		ALERTS_RESPONSE=$(curl --request GET \
				   		--url "${PC_APIURL}/v2/alert?detailed=true&timeType=relative&timeAmount=${TIME_AMOUNT}&timeUnit=${TIME_UNIT}&alert.status=${ALERT_STATUS}" \
				   		--header 'content-type: application/json; charset=UTF-8' \
				   		--header "x-redlock-auth: $PC_JWT" > "$JSON_OUTPUT_LOCATION/alert_${ALERT_STATUS}_${TIME_AMOUNT}_${TIME_UNIT}.json")
		printf '%s\n' ${SPACER}
		quick_check "/alert [${TIME_AMOUNT}] [${TIME_UNIT}] [${ALERT_STATUS}]"
		
		#printf '%s\n' "Displaying Alert Data for timeAmount = [${TIME_AMOUNT}] | timeUnit = [${TIME_UNIT}] | alert.status = [${ALERT_STATUS}]..."
		#printf '%s\n' "$ALERTS_RESPONSE"
		
		#Retrieving Total Rows for API Response
		TOTAL_ROWS=$(cat ${JSON_OUTPUT_LOCATION}/alert_${ALERT_STATUS}_${TIME_AMOUNT}_${TIME_UNIT}.json | jq '. | .totalRows')
		printf '%s\n' "Total # of Alerts: ${TOTAL_ROWS}"
		
		#Build Summary Array
		TOTAL_ROWS_SUMMARY+=(${TOTAL_ROWS})
	done
done
#End of Looping through Scenarios
printf '%s\n\n' ${DIVIDER}


printf '%s\n' "Exporting Summary dataset to CSV..."
printf '%s\n\n' ${DIVIDER}

#Build out CSV Header
CSV_SUMMARY_HEADER="#alert_status"
for index in "${!TIME_AMOUNT_array[@]}"; do
	CSV_SUMMARY_HEADER+=",${TIME_AMOUNT_array[index]}_${TIME_UNIT_array[index]}"
done

#Output Summary CSV header
printf '%s\n' ${CSV_SUMMARY_HEADER} > $OUTPUT_LOCATION/summary.csv

#Build out Summary CSV Data
for index in "${!ALERT_STATUS_array[@]}"; do
	OFFSET=$((+$index))
	CSV_DATA="${ALERT_STATUS_array[index]}" 
	for sindex in "${!TIME_AMOUNT_array[@]}"; do
		sOFFSET=$(($OFFSET+($sindex*$COUNT_ALERT_STATUS)))
		CSV_DATA+=",${TOTAL_ROWS_SUMMARY[sOFFSET]}"	
	done
	printf '%s\n' ${CSV_DATA}  >> $OUTPUT_LOCATION/summary.csv
done

printf '%s\n' "Removing Existing SV Files"
rm $OUTPUT_LOCATION/alert_*.csv

#Parse JSON Files in JSON_OUTPUT_LOCATION and convert to CSV
#alertId,alertStatus,alertTime,reason,dismissedBy,dismissalNote,policyId,policyName,policyType,severity,resourceid,resourceName,resourceAccount,resourceAccountId,resourceRegion,cloudType
#Iterate through 
for time_amount in "${!TIME_AMOUNT_array[@]}"; do 
	TIME_AMOUNT=${TIME_AMOUNT_array[time_amount]}
	TIME_UNIT=${TIME_UNIT_array[time_amount]}

	for status in "${!ALERT_STATUS_array[@]}"; do 
		ALERT_STATUS=${ALERT_STATUS_array[status]}
		printf '%s\n\n' ${DIVIDER}
		printf 'Creating CSV for Alerts over %s %s with Alert Status of %s\n' ${TIME_AMOUNT} ${TIME_UNIT} ${ALERT_STATUS}
	
		touch $OUTPUT_LOCATION/alert_${ALERT_STATUS}_${TIME_AMOUNT}_${TIME_UNIT}.csv
		
		printf '%s\n' "Exporting Alerts to CSV..."
		printf "#alertId,alertStatus,alertTime,reason,dismissedBy,dismissalNote,policyId,policyName,policyType,severity,resourceid,resourceName,resourceAccount,resourceAccountId,resourceRegion,cloudType\n" >> $OUTPUT_LOCATION/alert_${ALERT_STATUS}_${TIME_AMOUNT}_${TIME_UNIT}.csv
		
		cat ${JSON_OUTPUT_LOCATION}/alert_${ALERT_STATUS}_${TIME_AMOUNT}_${TIME_UNIT}.json | jq '.items[] | {alertId: .id,alertStatus: .status,alertTime: .alertTime,reason: .reason,dismissedBy: .dismissedBy,dismissalNote: .dismissalNote,policyId: .policy.policyId,policyName: .policy.name,policyType: .policy.policyType,severity: .policy.severity,resourceid: .resource.id,resourceName: .resource.name,resourceAccount: .resource.account,resourceAccountId: .resource.accountId,resourceRegion: .resource.region,cloudType: .resource.cloudType }' | jq -r '[.[]] | @csv' >> $OUTPUT_LOCATION/alert_${ALERT_STATUS}_${TIME_AMOUNT}_${TIME_UNIT}.csv
	done
done
printf '%s\n\n' ${DIVIDER}
printf '%s\n' "Removing JSON Files"
rm ${JSON_OUTPUT_LOCATION}/*.json
printf '%s\n\n' ${DIVIDER}
printf '%s\n' "Done."
printf '%s\n\n' ${DIVIDER}
printf '%s\n\n' ${DIVIDER}
#end
