#!/bin/bash
set -e
# -----------------------------------------------
# GeoServer Setup Script (Workspace, DataStores, Layer)
# -----------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ------------------------
# Configuration
# ------------------------
GEOSERVER_HOME="/usr/local/lib/geoserver-2.22.2"
GEOSERVER_REST_URL="http://localhost:8082/geoserver/rest"
GEOSERVER_USER="admin"
GEOSERVER_PASS="geoserver"

WORKSPACE="roads_ws"
DATASTORE="roads_store"
DB_NAME="tempo30-eligibility"
DB_USER="geoserver_user"
DB_PASS="geoserver"
DB_HOST="localhost"
DB_PORT="5432"

LAYER1="planet_osm_roads"
LAYER2="tempo30_analysis_result"

# ------------------------
# Check if GeoServer is already running
# ------------------------
if pgrep -f "geoserver" > /dev/null; then
    echo "GeoServer is already running."
else
    echo "Starting GeoServer..."
    nohup "$GEOSERVER_HOME/bin/startup.sh" > "$SCRIPT_DIR/geoserver.log" 2>&1 &
fi

# ------------------------
# Wait for GeoServer to be ready
# ------------------------
echo "Waiting for GeoServer..."
MAX_WAIT=300
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

# Set correct permissions
sudo chown -R $USER:$USER "$GEOSERVER_HOME/data_dir"
echo "Permissions set."

# ------------------------
# Create Workspace
# ------------------------
echo "Creating Workspace: $WORKSPACE"
curl -u "$GEOSERVER_USER:$GEOSERVER_PASS" -XPOST \
  -H "Content-type: application/json" \
  -d "{\"workspace\": {\"name\": \"$WORKSPACE\"}}" \
  "$GEOSERVER_REST_URL/workspaces" || echo "Workspace might already exist"

# ------------------------
# Create PostGIS DataStore
# ------------------------
echo "Creating DataStore: $DATASTORE"
curl -u "$GEOSERVER_USER:$GEOSERVER_PASS" -XPOST \
  -H "Content-type: application/json" \
  -d "{
    \"dataStore\": {
      \"name\": \"$DATASTORE\",
      \"connectionParameters\": {
        \"entry\": [
          {\"@key\":\"host\",\"$\":\"$DB_HOST\"},
          {\"@key\":\"port\",\"$\":\"$DB_PORT\"},
          {\"@key\":\"database\",\"$\":\"$DB_NAME\"},
          {\"@key\":\"user\",\"$\":\"$DB_USER\"},
          {\"@key\":\"passwd\",\"$\":\"$DB_PASS\"},
          {\"@key\":\"dbtype\",\"$\":\"postgis\"}
        ]
      }
    }
  }" \
  "$GEOSERVER_REST_URL/workspaces/$WORKSPACE/datastores" || echo "DataStore might already exist"

# ------------------------
# Create FeatureTypes
# ------------------------
for LAYER in "$LAYER1" "$LAYER2"; do
    echo "Creating FeatureType: $LAYER"
    curl -u "$GEOSERVER_USER:$GEOSERVER_PASS" -XPOST \
      -H "Content-type: application/json" \
      -d "{
            \"featureType\": {
                \"name\": \"$LAYER\",
                \"nativeName\": \"$LAYER\"
            }
          }" \
      "$GEOSERVER_REST_URL/workspaces/$WORKSPACE/datastores/$DATASTORE/featuretypes" \
      || echo "Layer $LAYER might already exist"
done

echo ""
echo "========================================="
echo "GeoServer setup completed."
echo "========================================="
echo "Workspace: $WORKSPACE"
echo "DataStore: $DATASTORE"
echo "Feature Layers: $LAYER1, $LAYER2"
echo "GeoServer URL: http://localhost:8082/geoserver"
echo "========================================="
