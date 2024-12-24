# Disk-Usage Monitoring Script

This script monitors specified file system paths and sends email notifications if disk usage exceeds a user-defined threshold. It includes a cooldown mechanism to limit the frequency of alerts and integrates with SendGrid API for sending notifications.

## Features
- Monitors disk usage on specified paths.
- Sends email notifications on reaching threshold levels (Warning, Critical).
- Cooldown mechanism to prevent multiple alerts in a short period.
- Customizable threshold and cooldown times.
- Integration with SendGrid API for email notifications.

## Requirements
- `curl` for sending emails via SendGrid API.
- A SendGrid account and API key.
- A SendGrid email template for the notifications.

## Setup
Before using the script, ensure that you have the following environment variables set:
- `API_KEY`: Your SendGrid API key.
- `TEMPLATE_ID`: The ID of the SendGrid email template.

Ensure the following files exist or are created:
- `/var/log/disk_usage.log`: Log file for recording disk usage checks and alert actions.
- `/tmp/disk_usage_info.log`: Temporary file for storing basic disk usage information.
- `/tmp/email_timestamp.log`: Timestamp file to manage cooldown between alerts.

## How to Use

1. **Basic Usage**  
   Monitor disk usage and send alerts when thresholds are exceeded:
   ```bash
   ./disk_usage.sh --email-to admin@example.com --email-from support@example.com / /mnt/data
 
2. **Custom Threshold and Cooldown**
   Set a custom disk usage threshold and cooldown period between warnings and critical alerts:
   ```bash
   ./disk_usage.sh --email-to admin@example.com --email-from support@example.com --threshold 90 -w 7200 -c 3600 / /mnt/data
   ```

## Options
- `--email-to <email>`: Email address to send notifications to (required).
- `--email-from <email>`: Sender email address (required).
- `--cc-emails <email1,email2,...>`: Comma-separated list of CC email addresses (optional).
- `-w, --cooldown-warning <seconds>`: Cooldown period for warning alerts in seconds (default: 3600).
- `-c, --cooldown-critical <seconds>`: Cooldown period for critical alerts in seconds (default: 1800).
- `--threshold <percentage>`: Disk usage threshold to trigger alerts (default: 80%).
- `--help`: Display the help message with usage instructions.

## Example
```bash
./disk_usage.sh --email-to admin@example.com --email-from support@example.com --cc-emails cc1@example.com,cc2@example.com -w 7200 -c 3600 --threshold 90 / /mnt/data
```
This will send alerts if the disk usage exceeds 90% and use a 2-hour cooldown for warning alerts and 1-hour cooldown for critical alerts.