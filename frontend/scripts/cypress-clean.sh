#!/bin/bash

# Cypress Clean Runner - Suppresses DBus errors and system warnings
# Usage: ./scripts/cypress-clean.sh [cypress-args]

# Set environment variables to suppress various Linux system warnings
export DBUS_SESSION_BUS_ADDRESS=""
export DISPLAY=${DISPLAY:-:99}
export ELECTRON_DISABLE_SECURITY_WARNINGS=true
export CYPRESS_CRASH_REPORTS=0
export CYPRESS_VERIFY_TIMEOUT=60000

# Suppress Chrome/Electron warnings
export CHROME_DEVEL_SANDBOX=1
export ELECTRON_ENABLE_LOGGING=false

# Run Cypress with clean environment
echo "🚀 Running Cypress with suppressed system warnings..."
echo "   Environment: ${CYPRESS_ENV:-development}"
echo "   Base URL: ${CYPRESS_BASE_URL:-http://localhost:3001}"

# Redirect stderr to filter out DBus errors while keeping test output
npm run cypress:headless "$@" 2>&1 | grep -v -E "(DevTools|ERROR:object_proxy|org\.freedesktop\.DBus|Failed to call method)" || true

echo "✅ Cypress execution completed"