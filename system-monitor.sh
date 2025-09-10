
#!/bin/bash

# System Monitor Script with Discord Webhook Alerts
# Monitors CPU, RAM, and Temperature
# Sends Discord notification when CPU usage exceeds 80%




WEBHOOK_URL="https://discord.com/api/webhooks/1415215763479986256/gZpP7GOD1dFSAh8EWy7H8DAz9C-Ne9p_casmGvZYHHjdtuTE8fYx9Jo1OQJUsgsmTUVE"

echo "System Monitor Started - Press Ctrl+C to stop"
echo "Monitoring CPU, RAM, and Temperature..."
echo "Discord alerts enabled for CPU usage > 80%"
echo "============================================="

while true; do
    echo "---------------------------------------------"
    echo "$(date '+%Y-%m-%d %H:%M:%S')"

    # CPU usage (%)
    CPU_USAGE_RAW=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}')
    CPU_USAGE=$(printf "%.0f" "$CPU_USAGE_RAW")
    echo "CPU Usage: ${CPU_USAGE}%"

    # RAM usage (%)
    RAM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
    RAM_USED=$(free -m | awk '/Mem:/ {print $3}')
    RAM_PERCENT=$(( RAM_USED * 100 / RAM_TOTAL ))
    echo "RAM Usage: ${RAM_USED}MB / ${RAM_TOTAL}MB (${RAM_PERCENT}%)"

    # Disk usage for root partition
    DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    DISK_INFO=$(df -h / | awk 'NR==2 {print $3 "/" $2}')
    echo "Disk Usage: ${DISK_INFO} (${DISK_USAGE}%)"

    # Temperature (requires lm-sensors)
    if command -v sensors &> /dev/null; then
        TEMP=$(sensors | grep -m 1 '°C' | awk '{print $2}' | sed 's/+//')
        echo "Temperature: $TEMP"
    else
        echo "Temperature: (install 'lm-sensors' to view)"
    fi

    # Load average
    LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}')
    echo "Load Average:$LOAD_AVG"
    
    # Discord webhook notification if CPU > 80%
    if [ "$CPU_USAGE" -gt 80 ]; then
        HOSTNAME=$(hostname)
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
        
        # Create JSON payload for Discord
        JSON_PAYLOAD=$(cat <<EOF
{
    "embeds": [
        {
            "title": "🚨 High CPU Usage Alert",
            "description": "CPU usage has exceeded the 80% threshold",
            "color": 15158332,
            "fields": [
                {
                    "name": "🖥️ Server",
                    "value": "$HOSTNAME",
                    "inline": true
                },
                {
                    "name": "📊 CPU Usage",
                    "value": "$CPU_USAGE%",
                    "inline": true
                },
                {
                    "name": "💾 RAM Usage",
                    "value": "$RAM_PERCENT%",
                    "inline": true
                },
                {
                    "name": "🕒 Timestamp",
                    "value": "$TIMESTAMP",
                    "inline": false
                }
            ],
            "footer": {
                "text": "System Monitor Alert"
            }
        }
    ]
}
EOF
)
        
        # Send webhook notification
        curl -s -H "Content-Type: application/json" \
             -X POST \
             -d "$JSON_PAYLOAD" \
             "$WEBHOOK_URL" > /dev/null 2>&1
        
        echo "🚨 ALERT: CPU usage is above 80% (${CPU_USAGE}%) - Discord notification sent"
    fi

    sleep 5
done