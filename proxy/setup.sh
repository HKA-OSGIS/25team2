#!/bin/bash
set -e

echo "Starting setup..."

# Function to get Node.js major version
get_node_version() {
    if command -v node &> /dev/null; then
        node -v | cut -d'v' -f2 | cut -d'.' -f1
    else
        echo "0"
    fi
}

# Function to wait for apt lock
wait_for_apt() {
    echo "Waiting for other package managers to finish..."
    while sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
          sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1; do
        echo "Waiting for apt lock to be released..."
        sleep 3
    done
    echo "Lock released, continuing..."
}

# Check Node.js version and install/update if needed
CURRENT_VERSION=$(get_node_version)
REQUIRED_VERSION=20

if [ "$CURRENT_VERSION" -lt "$REQUIRED_VERSION" ]; then
    if [ "$CURRENT_VERSION" -eq "0" ]; then
        echo "Node.js not found. Installing Node.js 20..."
    else
        echo "Node.js version $CURRENT_VERSION detected. Upgrading to Node.js 20..."
        # Remove old Node.js first
        echo "Removing old Node.js version..."
        wait_for_apt
        sudo apt-get remove -y nodejs npm || true
        sudo apt-get autoremove -y || true
    fi
    
    # Wait for any running apt processes
    wait_for_apt
    
    # Remove old NodeSource repository if exists
    sudo rm -f /etc/apt/sources.list.d/nodesource.list
    sudo rm -f /etc/apt/keyrings/nodesource.gpg
    
    # Clean apt cache
    sudo apt-get clean
    
    # Install Node.js 20 using NodeSource
    echo "Downloading NodeSource setup script..."
    curl -fsSL https://deb.nodesource.com/setup_20.x -o /tmp/nodesource_setup.sh
    
    wait_for_apt
    echo "Running NodeSource setup..."
    sudo bash /tmp/nodesource_setup.sh
    
    wait_for_apt
    echo "Installing Node.js..."
    sudo apt-get update
    sudo apt-get install -y nodejs
    
    # Clean up
    rm -f /tmp/nodesource_setup.sh
    
    NEW_VERSION=$(get_node_version)
    echo "Node.js $NEW_VERSION successfully installed!"
    
    # Verify npm is also installed
    if ! command -v npm &> /dev/null; then
        echo "Warning: npm not found, installing..."
        wait_for_apt
        sudo apt-get install -y npm
    fi
else
    echo "Node.js version $CURRENT_VERSION is already installed (>= $REQUIRED_VERSION required)."
fi

# Verify installation
echo "Verifying installation..."
echo "Node.js version: $(node -v)"
echo "npm version: $(npm -v)"

# Change to script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Create package.json if not present
if [ ! -f package.json ]; then
    echo "Creating package.json..."
    npm init -y
fi

# Install required libraries
echo "Installing dependencies..."
rm -rf node_modules 
npm install express node-fetch@2

echo "Proxy setup complete"
