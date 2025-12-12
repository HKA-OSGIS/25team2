#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# -----------------------------------------------
# Start PostgreSQL if not running
# -----------------------------------------------
if ! systemctl is-active --quiet postgresql; then
    echo "PostgreSQL is not running. Starting service..."
    sudo systemctl start postgresql
    echo "PostgreSQL started."
fi

# -----------------------------------------------
# Locate PBF file in data/ folder
# -----------------------------------------------
DATA_DIR="$SCRIPT_DIR/data"

PBF_FILE=$(find "$DATA_DIR" -maxdepth 1 -type f -name "*.osm.pbf" | head -n 1)

if [ -z "$PBF_FILE" ]; then
    echo "No .osm.pbf file found in $DATA_DIR"
    exit 1
fi

PBF_FILE_NAME=$(basename "$PBF_FILE")
PBF_PATH="$PBF_FILE"

echo "Using PBF file: $PBF_FILE_NAME"

# Copy to /tmp
TMP_PBF="/tmp/$PBF_FILE_NAME"
echo "Copying PBF file to temporary location for database import..."
cp "$PBF_PATH" "$TMP_PBF"
chmod 644 "$TMP_PBF"

# -----------------------------------------------
# Create PostGIS database and import OSM PBF data
# -----------------------------------------------
DB_NAME="tempo30-eligibility"
DB_OWNER="postgres"

DB_EXISTS=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'")
if [ "$DB_EXISTS" != "1" ]; then
    echo "Creating database $DB_NAME..."
    sudo -u postgres psql -c "CREATE DATABASE \"$DB_NAME\" OWNER \"$DB_OWNER\";"
else
    echo "Database $DB_NAME already exists."
fi

sudo -u postgres psql -d "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS postgis;"
sudo -u postgres psql -d "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS hstore;"

echo "Importing OSM data from $TMP_PBF..."
sudo -u postgres osm2pgsql --create --hstore -d "$DB_NAME" "$TMP_PBF"

echo "Create GeoServer user"
USER_EXISTS=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='geoserver_user'")

if [ "$USER_EXISTS" != "1" ]; then
    sudo -u postgres createuser geoserver_user
fi

sudo -u postgres psql -c "ALTER USER geoserver_user WITH PASSWORD 'geoserver';"
sudo -u postgres psql -d tempo30-eligibility -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO geoserver_user;"
sudo -u postgres psql -d tempo30-eligibility -c "GRANT USAGE ON SCHEMA public TO geoserver_user;"

rm "$TMP_PBF"

echo "Database setup completed."
