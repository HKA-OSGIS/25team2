#!/bin/bash
set -e

DB_NAME="tempo30-eligibility"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SQL_FILE="$SCRIPT_DIR/analysis.sql"

if [ ! -f "$SQL_FILE" ]; then
    echo "SQL file not found: $SQL_FILE"
    exit 1
fi

# Run SQL via STDIN to avoid permission issues
sudo -u postgres psql -d "$DB_NAME" < "$SQL_FILE"

echo "Analysis completed."
