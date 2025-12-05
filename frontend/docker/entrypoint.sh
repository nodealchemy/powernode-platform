#!/bin/bash
set -e

# Function to handle shutdown gracefully
shutdown() {
    echo "Received SIGTERM, shutting down gracefully..."
    nginx -s quit
    wait $!
}

# Trap SIGTERM
trap shutdown SIGTERM

# Ensure nginx directories exist with proper permissions
mkdir -p /var/cache/nginx /var/run /var/log/nginx
chown -R appuser:appuser /var/cache/nginx /var/run /var/log/nginx

# Test nginx configuration
nginx -t

echo "Starting nginx..."
exec "$@" &
wait $!