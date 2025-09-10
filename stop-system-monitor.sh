#!/bin/bash

# Stop System Monitor Script
# This script stops the running system-monitor.sh process

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="$SCRIPT_DIR/system-monitor.pid"

echo "Stopping System Monitor..."

# Check if PID file exists
if [[ ! -f "$PID_FILE" ]]; then
    echo "❌ System Monitor is not running (no PID file found)"
    echo "PID file location: $PID_FILE"
    exit 1
fi

# Read PID from file
PID=$(cat "$PID_FILE")

# Check if process is actually running
if ! kill -0 "$PID" 2>/dev/null; then
    echo "❌ Process with PID $PID is not running"
    echo "Cleaning up stale PID file..."
    rm -f "$PID_FILE"
    exit 1
fi

# Attempt graceful shutdown
echo "🔄 Sending TERM signal to process $PID..."
kill "$PID"

# Wait a moment for graceful shutdown
sleep 2

# Check if process is still running
if kill -0 "$PID" 2>/dev/null; then
    echo "⚠️  Process still running, forcing shutdown..."
    kill -9 "$PID"
    sleep 1
fi

# Clean up PID file
if [[ -f "$PID_FILE" ]]; then
    rm -f "$PID_FILE"
    echo "🧹 Cleaned up PID file"
fi

# Verify process is stopped
if kill -0 "$PID" 2>/dev/null; then
    echo "❌ Failed to stop process $PID"
    exit 1
else
    echo "✅ System Monitor stopped successfully"
    echo "💡 To start again, run: ./system-monitor.sh"
fi
