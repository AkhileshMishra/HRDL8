#!/bin/bash

# Configuration Setup Script for HRDL8
# This script generates configuration files from templates with correct paths

set -e

# Default values
DEFAULT_SITE=${1:-"hrdl8.local"}
DB_PASSWORD=${2:-$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-16)}
ENCRYPTION_KEY=${3:-$(openssl rand -base64 32)}

# Get the current directory (bench directory)
BENCH_DIR=$(pwd)

echo "Setting up configurations for: $BENCH_DIR"
echo "Default site: $DEFAULT_SITE"

# Create necessary directories
mkdir -p "$BENCH_DIR/config/pids"
mkdir -p "$BENCH_DIR/sites/$DEFAULT_SITE"

# Generate Redis cache configuration
if [ -f "$BENCH_DIR/config/redis_cache.conf.template" ]; then
    sed "s|{{BENCH_DIR}}|$BENCH_DIR|g" "$BENCH_DIR/config/redis_cache.conf.template" > "$BENCH_DIR/config/redis_cache.conf"
    echo "✅ Generated redis_cache.conf"
else
    echo "❌ Template redis_cache.conf.template not found"
fi

# Generate Redis queue configuration
if [ -f "$BENCH_DIR/config/redis_queue.conf.template" ]; then
    sed "s|{{BENCH_DIR}}|$BENCH_DIR|g" "$BENCH_DIR/config/redis_queue.conf.template" > "$BENCH_DIR/config/redis_queue.conf"
    echo "✅ Generated redis_queue.conf"
else
    echo "❌ Template redis_queue.conf.template not found"
fi

# Generate common site configuration
if [ -f "$BENCH_DIR/sites/common_site_config.json.template" ]; then
    sed "s|{{DEFAULT_SITE}}|$DEFAULT_SITE|g" "$BENCH_DIR/sites/common_site_config.json.template" > "$BENCH_DIR/sites/common_site_config.json"
    echo "✅ Generated common_site_config.json"
else
    echo "❌ Template common_site_config.json.template not found"
fi

# Generate site-specific configuration template (for deployment script to use)
if [ -f "$BENCH_DIR/sites/site_config.json.template" ]; then
    # Create a deployment-ready template with placeholders
    cp "$BENCH_DIR/sites/site_config.json.template" "$BENCH_DIR/sites/site_config_deploy.json.template"
    echo "✅ Prepared site configuration template for deployment"
else
    echo "❌ Template site_config.json.template not found"
fi

# Set default site
echo "$DEFAULT_SITE" > "$BENCH_DIR/sites/currentsite.txt"
echo "✅ Set default site to: $DEFAULT_SITE"

echo "Configuration setup complete!"
echo "Database password: $DB_PASSWORD"
echo "Encryption key: $ENCRYPTION_KEY"

