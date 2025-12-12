#!/bin/bash
set -e

# ------------------------
# Configuration
# ------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GEOSERVER_HOME="/usr/local/lib/geoserver-2.22.2"
GEOSERVER_REST_URL="http://localhost:8082/geoserver/rest/about/version.json"
GEOSERVER_USER="admin"
GEOSERVER_PASS="geoserver"
HTML_FILE="$SCRIPT_DIR/frontend/map.html"
PROXY_SCRIPT="$SCRIPT_DIR/proxy/proxy.js" 

# -----------------------------------------------
# Start PostgreSQL 
# -----------------------------------------------
if ! systemctl is-active --quiet postgresql; then
    echo "Starting PostgreSQL..."
    sudo systemctl start postgresql
    echo "PostgreSQL started"
else
    echo "PostgreSQL is already running."
fi

# ------------------------
# Start GeoServer
# ------------------------
if pgrep -f "geoserver" > /dev/null; then
    echo "GeoServer is already running."
else
    echo "Starting GeoServer..."
    nohup "$GEOSERVER_HOME/bin/startup.sh" > /dev/null 2>&1 &
fi

# ------------------------
# Wait for GeoServer
# ------------------------
echo "Waiting for GeoServer..."
MAX_WAIT=120
COUNTER=0
while [ $COUNTER -lt $MAX_WAIT ]; do
    if curl -s -u "$GEOSERVER_USER:$GEOSERVER_PASS" "$GEOSERVER_REST_URL" > /dev/null 2>&1; then
        echo "GeoServer is ready!"
        break
    fi
    echo "Waiting... ($COUNTER seconds)"
    sleep 5
    COUNTER=$((COUNTER + 5))
done
if [ $COUNTER -ge $MAX_WAIT ]; then
    echo "GeoServer could not be started."
    exit 1
fi

# ------------------------
# Start Proxy
# ------------------------
echo "Starting GeoServer Proxy..."
if pgrep -f "node proxy.js" > /dev/null; then
    echo "Proxy is already running."
else
    cd "$SCRIPT_DIR"
    nohup node "$PROXY_SCRIPT" > /dev/null 2>&1 &
    sleep 2
    echo "GeoServer Proxy started"
fi

# ------------------------
# Open HTML Map
# ------------------------
echo "Opening map in browser..."

if [ -f "$HTML_FILE" ]; then
    firefox --new-tab "file://$HTML_FILE" 2>/dev/null &
else
    echo "HTML file not found: $HTML_FILE"
fi

echo "Firefox will open and display the map"
