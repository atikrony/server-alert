#!/bin/bash

WEBHOOK_URL="https://discord.com/api/webhooks/1415215763479986256/gZpP7GOD1dFSAh8EWy7H8DAz9C-Ne9p_casmGvZYHHjdtuTE8fYx9Jo1OQJUsgsmTUVE"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="$SCRIPT_DIR/system-monitor.pid"
LOG_FILE="$SCRIPT_DIR/system-monitor.log"

THRESHOLD=80          # percent
SUSTAINED_SEC=5       # require >=80% for 5 seconds
CHECK_INTERVAL=1      # seconds between samples
MIN_ALERT_GAP=10     # don't alert more than once per 120s

# Clean up PID file on exit
cleanup() { rm -f "$PID_FILE"; }
trap cleanup EXIT

start_background_monitoring() {
  if [[ -f "$PID_FILE" ]]; then
    local pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      echo "System Monitor is already running (PID: $pid)"
      echo "To stop: kill \$pid"
      exit 1
    else
      rm -f "$PID_FILE"
    fi
  fi

  echo "Starting System Monitor in background..."
  nohup "$0" --monitor > "$LOG_FILE" 2>&1 &
  echo $! > "$PID_FILE"
  echo "PID: $(cat "$PID_FILE")  | Logs: $LOG_FILE"
  exit 0
}

# Read CPU usage using /proc/stat deltas (total-idle / total)
read_cpu_percent() {
  # Read first snapshot
  read cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
  local prev_idle=$((idle + iowait))
  local prev_non_idle=$((user + nice + system + irq + softirq + steal))
  local prev_total=$((prev_idle + prev_non_idle))

  sleep "$CHECK_INTERVAL"

  # Read second snapshot
  read cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
  local idle2=$((idle + iowait))
  local non_idle2=$((user + nice + system + irq + softirq + steal))
  local total2=$((idle2 + non_idle2))

  local totald=$((total2 - prev_total))
  local idled=$((idle2 - prev_idle))

  # CPU busy percent over the interval
  # avoid division by zero
  if [[ $totald -le 0 ]]; then
    echo 0
  else
    # scale to integer percent
    echo $(( (100*(totald - idled)) / totald ))
  fi
}

send_discord() {
  local cpu="$1" ram_percent="$2" ram_used="$3" ram_total="$4" disk_percent="$5" disk_info="$6"
  local host ts
  host=$(hostname)
  ts=$(date '+%Y-%b-%d %H:%M:%S')

  read -r -d '' JSON_PAYLOAD <<EOF
{
  "username": "RubizCode RND Sever",
  "content": "High Usage Alert (Resolve Now)",
  "embeds": [
    {
      "title": "🚨 High CPU Usage Alert",
      "description": "CPU usage has met/exceeded the ${THRESHOLD}% threshold for ${SUSTAINED_SEC}s.",
      "color": 15158332,
      "fields": [
        { "name": "🖥️ Server", "value": "${host}", "inline": true },
        { "name": "📊 CPU Usage", "value": "${cpu}% (avg over ${SUSTAINED_SEC}s)", "inline": true },
        { "name": "💾 RAM Usage", "value": "${ram_used}MB / ${ram_total}MB (${ram_percent}%)", "inline": true },
        { "name": "💽 Disk (/)", "value": "${disk_info} (${disk_percent}%)", "inline": true },
        { "name": "🕒 Timestamp", "value": "${ts}", "inline": false }
      ],
      "footer": { "text": "System Monitor Alert" }
    }
  ]
}
EOF

  # Capture HTTP status and response body for debugging
  http_status=$(curl -sS -o /tmp/discord_resp.txt -w "%{http_code}" \
    -H "Content-Type: application/json" \
    -X POST \
    --data "$JSON_PAYLOAD" \
    "$WEBHOOK_URL" || echo "000")

  echo "[Webhook] HTTP $http_status | $(date '+%F %T')" >> "$LOG_FILE"
  if [[ "$http_status" != "204" ]]; then
    echo "[Webhook] Response: $(cat /tmp/discord_resp.txt)" >> "$LOG_FILE"
  fi
  rm -f /tmp/discord_resp.txt
}

run_monitor() {
  echo "System Monitor Started - $(date)"
  echo "Threshold: ${THRESHOLD}% for ${SUSTAINED_SEC}s; check every ${CHECK_INTERVAL}s"
  echo "Discord alerts enabled. Success = HTTP 204."
  echo "============================================="

  local consec=0
  local last_alert_epoch=0

  while true; do
    # CPU
    CPU_PERCENT=$(read_cpu_percent)

    # RAM
    RAM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
    RAM_USED=$(free -m | awk '/Mem:/ {print $3}')
    RAM_PERCENT=$(( RAM_USED * 100 / RAM_TOTAL ))

    # Disk
    DISK_PERCENT=$(df -h / | awk 'NR==2 {gsub("%","",$5); print $5}')
    DISK_INFO=$(df -h / | awk 'NR==2 {print $3 "/" $2}')

    # Log line
    echo "$(date '+%F %T') | CPU: ${CPU_PERCENT}% | RAM: ${RAM_USED}/${RAM_TOTAL}MB (${RAM_PERCENT}%) | DISK: ${DISK_INFO} (${DISK_PERCENT}%)" >> "$LOG_FILE"

    # Count consecutive seconds ≥ threshold
    if (( CPU_PERCENT >= THRESHOLD )); then
      ((consec++))
    else
      consec=0
    fi

    # If sustained high CPU and alert gap passed, send alert
    now=$(date +%s)
    if (( consec >= SUSTAINED_SEC )) && (( now - last_alert_epoch >= MIN_ALERT_GAP )); then
      # Compute average CPU over the sustained window (best-effort: reuse current reading)
      AVG_CPU=$CPU_PERCENT
      send_discord "$AVG_CPU" "$RAM_PERCENT" "$RAM_USED" "$RAM_TOTAL" "$DISK_PERCENT" "$DISK_INFO"
      last_alert_epoch=$now
      consec=0
    fi
  done
}

if [[ "$1" == "--monitor" ]]; then
  echo $$ > "$PID_FILE"
  run_monitor
else
  start_background_monitoring
fi