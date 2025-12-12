#!/bin/bash
set -e  

echo "Setup started."

# Make all scripts executable
chmod +x database/setup.sh
chmod +x database/analyze.sh
chmod +x geoserver/setup.sh
chmod +x proxy/setup.sh

# Initialize database
./database/setup.sh
echo "Database initialized."

# Perform analysis
./database/analyze.sh
echo "Eligible roads identified."

# Initialize GeoServer
./geoserver/setup.sh
echo "GeoServer configured."

# Initialize Proxy
./proxy/setup.sh
echo "Proxy initialized."

echo "Full setup completed."
