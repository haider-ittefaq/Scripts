#!/bin/bash
if [ $EUID -ne 0 ]; then
	echo "[-] Please run this script with sudo"
	exit 1
fi

# Default values
EMAIL_TO=""
EMAIL_FROM=""
CC_EMAILS=("")
EMAIL_SERVICE="SENDGRID"
API_KEY=${API_KEY:-""}
TEMPLATE_ID=${TEMPLATE_ID:-""}
THRESHOLD=80
COOLDOWN_WARNING=3600
COOLDOWN_CRITICAL=1800
LOG_FILE="/var/log/disk_usage.log"
INFO_FILE="/tmp/disk_usage_info.log"
EMAIL_TIMESTAMP_FILE="/tmp/email_timestamp.log"
PATHS_TO_MONITOR=()
OS_NAME=$(uname -s)
HOSTNAME=$(hostname)

usage() {
	cat <<EOF
Usage: $0 --email-to <email_to> --email-from <email_from> [--cc-emails <cc_email1,cc_email2,...>] 
          [-w <seconds> | --cooldown-warning <seconds>] 
          [-c <seconds> | --cooldown-critical <seconds>] 
          [--threshold <percentage>] [--email-service <service>] <paths_to_monitor...>

Description:
This script monitors specified file system paths and sends email notifications if disk usage exceeds a user-defined threshold. It integrates with the SendGrid API to send alerts using a dynamic email template.


Options:
  --email-to          Specify the recipient email address (required).
  --email-from        Specify the sender email address (required).
  --cc-emails         Specify a comma-separated list of CC email addresses (optional).
  -w, --cooldown-warning  Set cooldown time for warning alerts in seconds (default: 3600).
  -c, --cooldown-critical Set cooldown time for critical alerts in seconds (default: 1800).
  --threshold         Set disk usage threshold as a percentage (default: 80).
  --email-service     Specify the email service to use (default: SENDGRID). Future options: MAILGUN, GMAIL.
  --help              Display this help message and exit.

Arguments:
  <paths_to_monitor...>  One or more file paths to monitor (required).

Examples:
  Basic usage:
    $0 --email-to admin@example.com --email-from support@example.com / /mnt/vol_data_example

  Custom cooldown and threshold:
    $0 --email-to admin@example.com --email-from support@example.com -w 7200 -c 3600 --threshold 90 / /mnt/vol_data_example
EOF
	exit 0
}

# Parse arguments
while [[ "$#" -gt 0 ]]; do
	case $1 in
	--email-to)
		EMAIL_TO="$2"
		shift
		;;
	--email-from)
		EMAIL_FROM="$2"
		shift
		;;
	--cc-emails)
		IFS=',' read -ra CC_EMAILS <<<"$2"
		shift
		;;
	-w | --cooldown-warning)
		COOLDOWN_WARNING="$2"
		shift
		;;
	-c | --cooldown-critical)
		COOLDOWN_CRITICAL="$2"
		shift
		;;
	--threshold)
		THRESHOLD="$2"
		shift
		;;
	--email-service)
		EMAIL_SERVICE="$2"
		shift
		;;
	--help) usage ;;
	*) PATHS_TO_MONITOR+=("$1") ;;
	esac
	shift
done

# Validate the email service early
case "$EMAIL_SERVICE" in
SENDGRID)
	# SendGrid-specific validation
	[[ -z "$API_KEY" || -z "$TEMPLATE_ID" ]] && {
		echo "Missing API_KEY or TEMPLATE_ID for SendGrid"
		exit 1
	}
	;;
*)
	echo "Unsupported email service: $EMAIL_SERVICE"
	exit 1
	;;
esac

if [[ ${#CC_EMAILS[@]} -gt 0 && ${CC_EMAILS[0]} != "" ]]; then
	cc_list=$(printf ', {"email": "%s"}' "${CC_EMAILS[@]}")
	cc_list="[${cc_list:2}]"
else
	cc_list="[]"
fi

# Validate required arguments
if [[ -z "$EMAIL_TO" || -z "$EMAIL_FROM" || "${#PATHS_TO_MONITOR[@]}" -eq 0 ]]; then
	usage
fi

# Ensure required files exist
[[ -f $LOG_FILE ]] || touch $LOG_FILE
[[ -f $INFO_FILE ]] || touch $INFO_FILE
[[ -f $EMAIL_TIMESTAMP_FILE ]] || touch $EMAIL_TIMESTAMP_FILE

send_email_sendgrid() {
	local alert_level=$1
	local disk_usage=$2
	local path=$3

	echo $API_KEY
	echo $TEMPLATE_ID

	# Set alert time
	alert_time=$(date '+%d-%m-%Y %H:%M')

	# Build dynamic template data
	dynamic_template_data=$(
		cat <<EOF
{
  "disk_usage": "$disk_usage",
  "alert_level": "$alert_level",
  "os_name": "$OS_NAME",
  "hostname": "$HOSTNAME",
  "path": "$path",
  "alert_time": "$alert_time",
  "subject": "Disk Usage - $alert_level"
}
EOF
	)

	# Build template data based on CC presence
	if [[ ${#CC_EMAILS[@]} -gt 0 && ${CC_EMAILS[0]} != "" ]]; then
		cc_list=$(printf ', {"email": "%s"}' "${CC_EMAILS[@]}")
		cc_list="[${cc_list:2}]"
		template_data=$(
			cat <<EOF
{
  "personalizations": [{
    "to": [{"email": "$EMAIL_TO"}],
    "cc": $cc_list,
    "dynamic_template_data": $dynamic_template_data
  }],
  "from": {"email": "$EMAIL_FROM"},
  "template_id": "$TEMPLATE_ID"
}
EOF
		)
	else
		template_data=$(
			cat <<EOF
{
  "personalizations": [{
    "to": [{"email": "$EMAIL_TO"}],
    "dynamic_template_data": $dynamic_template_data
  }],
  "from": {"email": "$EMAIL_FROM"},
  "template_id": "$TEMPLATE_ID"
}
EOF
		)
	fi

	# Send the email
	response=$(curl -s -w "%{http_code}" -X POST https://api.sendgrid.com/v3/mail/send \
		-H "Authorization: Bearer $API_KEY" \
		-H "Content-Type: application/json" \
		-d "$template_data")

	# Get the HTTP status code
	http_code="${response: -3}"

	if [[ $http_code -ne 202 ]]; then
		echo "Failed to send email. HTTP status code: $http_code" >>$INFO_FILE
		continue
	fi

	email_sent="Yes"
	email_success=$([[ $http_code -eq 202 ]] && echo "True" || echo "False")

	if [[ $email_success == "True" ]]; then
		sed -i "/^$alert_level:/d" $EMAIL_TIMESTAMP_FILE
		echo "$alert_level:$(date +%s)" >>$EMAIL_TIMESTAMP_FILE
	fi
}

create_log_message() {
	echo "$(date '+%Y/%m/%d %H:%M:%S') [$type] Disk Usage: $current_disk_usage% Path: $path Email Sent: $email_sent Success: $email_success" >>$LOG_FILE
}

# Generic function to send email
send_email() {
	local alert_level="$1"
	local disk_usage="$2"
	local path="$3"

	case "$EMAIL_SERVICE" in
	SENDGRID)
		send_email_sendgrid "$alert_level" "$disk_usage" "$path"
		;;
	*)
		echo "Unsupported email service: $EMAIL_SERVICE"
		exit 1
		;;
	esac
}

# Main logic
for path in "${PATHS_TO_MONITOR[@]}"; do
	# Check disk usage
	current_disk_usage=$(df -h "$path" | awk 'NR==2 {print $5}' | cut -d'%' -f1)

	# Check if disk usage is empty or not
	if [[ -z "$current_disk_usage" ]]; then
		echo "Error: Unable to retrieve disk usage for $path"
		continue
	fi

	type="Normal"
	[[ $current_disk_usage -ge $THRESHOLD ]] && type="Warning"
	[[ $current_disk_usage -ge 90 ]] && type="Critical"

	email_sent="No"
	email_success="False"

	last_email_sent=$(grep "^$type:" $EMAIL_TIMESTAMP_FILE | cut -d':' -f2)
	[[ -z $last_email_sent ]] && last_email_sent=0

	current_time=$(date +%s)
	time_diff=$((current_time - last_email_sent))

	if [[ $type == "Critical" && $time_diff -ge $COOLDOWN_CRITICAL ]]; then
		send_email "$type" "$current_disk_usage" "$path"
	elif [[ $type == "Critical" ]]; then
		cooldown_remaining=$((COOLDOWN_CRITICAL - time_diff))
		echo "$(date '+%Y/%m/%d %H:%M:%S') [$type] Cooldown active for $cooldown_remaining seconds. Email not sent." >>$INFO_FILE
	elif [[ $type == "Warning" && $time_diff -ge $COOLDOWN_WARNING ]]; then
		send_email "$type" "$current_disk_usage" "$path"
	elif [[ $type == "Warning" ]]; then
		cooldown_remaining=$((COOLDOWN_WARNING - time_diff))
		echo "$(date '+%Y/%m/%d %H:%M:%S') [$type] Cooldown active for $cooldown_remaining seconds. Email not sent." >>$INFO_FILE
	fi

	create_log_message
done

exit 0
