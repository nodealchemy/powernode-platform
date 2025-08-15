#!/bin/bash
# Run Cypress tests in production environment

export CYPRESS_ENV=production
export CYPRESS_BASE_URL=https://powernode.com
export CYPRESS_API_URL=https://api.powernode.com/api/v1

echo "Running Cypress tests in PRODUCTION mode"
echo "Base URL: $CYPRESS_BASE_URL"
echo "API URL: $CYPRESS_API_URL"

npx cypress run --headless "$@"