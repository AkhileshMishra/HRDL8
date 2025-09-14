#!/bin/bash

# HRDL8 Production Deployment Script
# This script deploys a clean, production-ready Frappe HRMS with HRDL8 branding.

set -eo pipefail

# --- Configuration ---
INSTALL_DIR="/home/ubuntu/hrdl8-production"
SITE_NAME="hrdl8.local"
DB_ROOT_PASSWORD="admin"
ADMIN_PASSWORD="admin"

# --- Helper Functions ---
log() {
    echo "[INFO] $1"
}

error() {
    echo "[ERROR] $1" >&2
    exit 1
}

# --- Main Script ---
log "Starting HRDL8 Production Deployment..."

# 1. System Preparation
log "Step 1: Preparing the system..."
sudo apt-get update -y
sudo apt-get install -y git python3-venv python3-pip curl wget mariadb-server redis-server

# 2. Install Frappe Bench
log "Step 2: Installing Frappe Bench..."
if ! command -v bench &> /dev/null; then
    pip3 install frappe-bench
fi

# 3. Initialize Bench
log "Step 3: Initializing Frappe Bench..."
rm -rf "$INSTALL_DIR"
bench init --frappe-branch version-15 "$INSTALL_DIR"
cd "$INSTALL_DIR"

# 4. Configure Database
log "Step 4: Configuring MariaDB..."
sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PASSWORD';"
sudo mysql -u root -p"$DB_ROOT_PASSWORD" -e "CREATE USER IF NOT EXISTS 'frappe'@'localhost' IDENTIFIED BY 'frappe';"
sudo mysql -u root -p"$DB_ROOT_PASSWORD" -e "GRANT ALL PRIVILEGES ON *.* TO 'frappe'@'localhost' WITH GRANT OPTION;"
sudo mysql -u root -p"$DB_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;"

# 5. Create New Site
log "Step 5: Creating a new site..."
bench new-site "$SITE_NAME" --db-name "${SITE_NAME}_db" --mariadb-root-password "$DB_ROOT_PASSWORD" --admin-password "$ADMIN_PASSWORD" --install-app erpnext

# 6. Get and Install HRMS App
log "Step 6: Getting and installing HRMS app..."
bench get-app hrms
bench --site "$SITE_NAME" install-app hrms

# 7. Apply Customizations
log "Step 7: Applying HRDL8 customizations..."
# (This is where you would apply your customizations from the git repo)
# For now, we will manually apply the login page changes as a proof of concept.

# Main Frappe Login
file_path="apps/frappe/frappe/www/login.html"
if [ -f "$file_path" ]; then
    sed -i 's/Login to Frappe/Login to HRDL8_MAIN/g' "$file_path"
    log "Customized main Frappe login page."
fi

# HRMS Frontend Login
file_path="apps/hrms/hrms/public/js/login.js" # Example path, might need adjustment
if [ -f "$file_path" ]; then
    sed -i 's/Login to Frappe HR/Login to HRDL8/g' "$file_path"
    log "Customized HRMS login page."
fi

# 8. Build Frontend
log "Step 8: Building frontend assets..."
bench build

# 9. Start Services
log "Step 9: Starting services..."
bench start &

log "HRDL8 deployment is complete!"
log "URL: http://$SITE_NAME:8000"
log "Admin user: Administrator"
log "Admin password: $ADMIN_PASSWORD"


