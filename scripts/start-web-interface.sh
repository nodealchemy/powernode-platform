#!/bin/bash

# Standalone Web Interface Starter for Powernode Worker
# This script starts the Sidekiq web interface with daemon-style detachment

set -euo pipefail

WORKER_DIR="/home/rett/Projects/powernode-platform/worker"
WEB_PID_FILE="/var/tmp/powernode-worker-web.pid"
WEB_LOG_FILE="/home/rett/Projects/powernode-platform/logs/worker-web.log"

cd "$WORKER_DIR"

# Load environment
if [[ -f .env ]]; then
    source .env
fi

# Create a minimal Ruby wrapper script to avoid bundler overhead
cat > /tmp/start_sidekiq_web.rb <<'EOF'
#!/usr/bin/env ruby

require 'bundler/setup'
require_relative './config/application'

# Initialize application
PowernodeWorker.application

# Start Puma server directly
require 'puma'
require 'rack'

app = Rack::Builder.parse_file('./config.ru')

server = Puma::Server.new(app)
server.add_tcp_listener(ENV.fetch('SIDEKIQ_WEB_HOST', '0.0.0.0'), ENV.fetch('SIDEKIQ_WEB_PORT', '4567').to_i)

# Detach from terminal
Process.daemon(true, false)

# Run server
server.run.join
EOF

# Start the Ruby script directly
ruby /tmp/start_sidekiq_web.rb &
web_pid=$!

# Save PID
echo "$web_pid" > "$WEB_PID_FILE"

echo "Sidekiq web interface started (PID: $web_pid, Host: ${SIDEKIQ_WEB_HOST:-0.0.0.0}, Port: ${SIDEKIQ_WEB_PORT:-4567})"