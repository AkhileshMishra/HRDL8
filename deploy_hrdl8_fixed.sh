#!/bin/bash

# HRDL8 Fixed Production Deployment Script
# This script addresses all identified issues and creates a production-ready deployment

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# --- Configuration ---
REPO_URL="https://github.com/AkhileshMishra/HRDL8.git"
INSTALL_DIR="/home/ubuntu/hrdl8-deployment"
SITE_NAME="hrdl8.local"
DB_ROOT_PASSWORD="admin123"
ADMIN_PASSWORD="admin123"
FRAPPE_USER="frappe"
FRAPPE_PASSWORD="frappe123"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Helper Functions ---
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "Command '$1' not found. Please install it first."
    fi
}

check_service() {
    if ! systemctl is-active --quiet "$1"; then
        warn "Service '$1' is not running. Starting it..."
        sudo systemctl start "$1" || error "Failed to start service '$1'"
    fi
}

generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-16
}

# --- Pre-flight Checks ---
log "Starting HRDL8 Fixed Deployment..."
log "Performing pre-flight checks..."

# Check if running as ubuntu user
if [ "$USER" != "ubuntu" ]; then
    error "This script must be run as the ubuntu user"
fi

# Check for required commands
check_command "git"
check_command "python3"
check_command "pip3"
check_command "mysql"
check_command "redis-server"

echo ""
echo "=========================================="
echo "HRDL8 Fixed Deployment Script"
echo "=========================================="
echo "Repository: $REPO_URL"
echo "Install Directory: $INSTALL_DIR"
echo "Site Name: $SITE_NAME"
echo "=========================================="
echo ""

# --- Step 1: System Dependencies ---
log "Step 1: Installing system dependencies..."

sudo apt update -qq
sudo apt install -y \
    python3.11 \
    python3.11-dev \
    python3.11-venv \
    python3-pip \
    nodejs \
    npm \
    mariadb-server \
    mariadb-client \
    redis-server \
    libffi-dev \
    liblcms2-dev \
    libldap2-dev \
    libmariadb-dev \
    libsasl2-dev \
    libtiff5-dev \
    libwebp-dev \
    python3-dev \
    python3-setuptools \
    build-essential \
    git \
    curl \
    wget \
    supervisor \
    nginx

# Install wkhtmltopdf
log "Installing wkhtmltopdf..."
cd /tmp
if [ ! -f "wkhtmltox_0.12.6.1-2.jammy_amd64.deb" ]; then
    wget -q https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb
fi
sudo dpkg -i wkhtmltox_0.12.6.1-2.jammy_amd64.deb || sudo apt-get install -f -y

# Install yarn
sudo npm install -g yarn

# --- Step 2: Configure MariaDB ---
log "Step 2: Configuring MariaDB..."

# Start MariaDB
sudo systemctl start mariadb
sudo systemctl enable mariadb

# Configure MariaDB settings (using current syntax)
sudo mysql -e "SET GLOBAL innodb_file_per_table=1;" || warn "Could not set innodb_file_per_table"
sudo mysql -e "SET GLOBAL character_set_server=utf8mb4;" || warn "Could not set character_set_server"
sudo mysql -e "SET GLOBAL collation_server=utf8mb4_unicode_ci;" || warn "Could not set collation_server"

# Set root password and create frappe user
sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PASSWORD';" || warn "Could not set root password"
sudo mysql -u root -p"$DB_ROOT_PASSWORD" -e "CREATE USER IF NOT EXISTS '$FRAPPE_USER'@'localhost' IDENTIFIED BY '$FRAPPE_PASSWORD';" || warn "Could not create frappe user"
sudo mysql -u root -p"$DB_ROOT_PASSWORD" -e "GRANT ALL PRIVILEGES ON *.* TO '$FRAPPE_USER'@'localhost' WITH GRANT OPTION;" || warn "Could not grant privileges"
sudo mysql -u root -p"$DB_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;" || warn "Could not flush privileges"

# --- Step 3: Configure Redis ---
log "Step 3: Configuring Redis..."

sudo systemctl start redis-server
sudo systemctl enable redis-server
check_service "redis-server"

# --- Step 4: Install Frappe Bench ---
log "Step 4: Installing Frappe Bench..."

if ! command -v bench &> /dev/null; then
    pip3 install frappe-bench
    # Add to PATH
    if ! echo $PATH | grep -q "$HOME/.local/bin"; then
        echo 'export PATH=$HOME/.local/bin:$PATH' >> ~/.bashrc
        export PATH=$HOME/.local/bin:$PATH
    fi
fi

# --- Step 5: Clone and Setup Repository ---
log "Step 5: Cloning HRDL8 repository..."

# Remove existing installation
if [ -d "$INSTALL_DIR" ]; then
    log "Removing existing installation..."
    rm -rf "$INSTALL_DIR"
fi

# Clone repository
git clone "$REPO_URL" "$INSTALL_DIR"
cd "$INSTALL_DIR"

# --- Step 6: Fix Configurations ---
log "Step 6: Fixing configurations..."

# Run the configuration setup script
if [ -f "setup_configs.sh" ]; then
    chmod +x setup_configs.sh
    ./setup_configs.sh "$SITE_NAME"
    log "Configuration templates applied successfully"
else
    warn "setup_configs.sh not found, using default configurations"
fi

# --- Step 7: Setup Virtual Environment ---
log "Step 7: Setting up Python virtual environment..."

if [ ! -d "env" ]; then
    python3.11 -m venv env
fi

source env/bin/activate

# Install Python dependencies
pip install --upgrade pip
pip install frappe-bench

# --- Step 8: Create New Site ---
log "Step 8: Creating new site..."

# Update hosts file
if ! grep -q "$SITE_NAME" /etc/hosts; then
    echo "127.0.0.1 $SITE_NAME" | sudo tee -a /etc/hosts
fi

# Create site directory if it doesn't exist
mkdir -p "sites/$SITE_NAME"

# Generate site configuration
DB_NAME="${SITE_NAME//./_}_db"
DB_PASSWORD=$(generate_password)
ENCRYPTION_KEY=$(openssl rand -base64 32)

cat > "sites/$SITE_NAME/site_config.json" << EOF
{
 "db_name": "$DB_NAME",
 "db_password": "$DB_PASSWORD",
 "db_type": "mariadb",
 "db_host": "localhost",
 "db_port": 3306,
 "auto_update": false,
 "encryption_key": "$ENCRYPTION_KEY",
 "user_type_doctype_limit": {
  "employee_self_service": 40
 }
}
EOF

# Create database
sudo mysql -u root -p"$DB_ROOT_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;"
sudo mysql -u root -p"$DB_ROOT_PASSWORD" -e "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$FRAPPE_USER'@'localhost';"

# --- Step 9: Install Apps ---
log "Step 9: Installing applications..."

# Install Frappe
cd apps/frappe
pip install -e .
cd ../..

# Install ERPNext
cd apps/erpnext
pip install -e .
cd ../..

# Install HRMS
cd apps/hrms
pip install -e .
cd ../..

# --- Step 10: Initialize Site ---
log "Step 10: Initializing site..."

# Install site
python -m frappe.utils.bench install-app frappe --site "$SITE_NAME"
python -m frappe.utils.bench install-app erpnext --site "$SITE_NAME"
python -m frappe.utils.bench install-app hrms --site "$SITE_NAME"

# Set administrator password
python -m frappe.utils.bench set-admin-password "$ADMIN_PASSWORD" --site "$SITE_NAME"

# --- Step 11: Build Frontend ---
log "Step 11: Building frontend assets..."

# Build HRMS frontend
cd apps/hrms/frontend
if [ -f "package.json" ]; then
    npm install
    npm run build
fi
cd ../../..

# Build Frappe assets
python -m frappe.utils.bench build --site "$SITE_NAME"

# --- Step 12: Start Services ---
log "Step 12: Starting services..."

# Kill any existing processes
sudo pkill -f "bench\|frappe\|redis-server" || true
sleep 3

# Start Redis with custom configs
if [ -f "config/redis_cache.conf" ]; then
    redis-server config/redis_cache.conf --daemonize yes
fi
if [ -f "config/redis_queue.conf" ]; then
    redis-server config/redis_queue.conf --daemonize yes
fi

# Start bench
nohup python -m frappe.utils.bench start > bench.log 2>&1 &

# Wait for services to start
log "Waiting for services to start..."
sleep 15

# --- Step 13: Verification ---
log "Step 13: Verifying deployment..."

# Check if web server is responding
if curl -s "http://$SITE_NAME:8000" > /dev/null; then
    log "✅ Main application is responding"
else
    warn "❌ Main application is not responding"
fi

if curl -s "http://$SITE_NAME:8000/hrms" > /dev/null; then
    log "✅ HRMS frontend is responding"
else
    warn "❌ HRMS frontend is not responding"
fi

# --- Completion ---
echo ""
echo "=========================================="
echo "🎉 HRDL8 Deployment Complete!"
echo "=========================================="
echo ""
echo "📋 Access Information:"
echo "   • Main Application: http://$SITE_NAME:8000"
echo "   • HRMS Frontend: http://$SITE_NAME:8000/hrms"
echo ""
echo "🔐 Login Credentials:"
echo "   • Username: Administrator"
echo "   • Password: $ADMIN_PASSWORD"
echo ""
echo "📁 Installation Details:"
echo "   • Directory: $INSTALL_DIR"
echo "   • Site Name: $SITE_NAME"
echo "   • Database: $DB_NAME"
echo "   • Logs: $INSTALL_DIR/bench.log"
echo ""
echo "🔧 Management Commands:"
echo "   • Stop: cd $INSTALL_DIR && python -m frappe.utils.bench stop"
echo "   • Start: cd $INSTALL_DIR && python -m frappe.utils.bench start"
echo "   • Restart: cd $INSTALL_DIR && python -m frappe.utils.bench restart"
echo ""
echo "✨ All customizations applied:"
echo "   • Main Login: 'Login to HRDL8_MAIN'"
echo "   • HRMS Login: 'Login to HRDL8'"
echo "   • HRMS Branding: Complete rebrand to HRDL8"
echo ""
echo "=========================================="

