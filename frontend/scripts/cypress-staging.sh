#!/bin/bash
# Run Cypress tests in staging environment

export CYPRESS_ENV=staging
export CYPRESS_BASE_URL=https://staging.powernode.com
export CYPRESS_API_URL=https://staging-api.powernode.com/api/v1

echo "Running Cypress tests in STAGING mode"
echo "Base URL: $CYPRESS_BASE_URL"
echo "API URL: $CYPRESS_API_URL"

npx cypress run --headless "$@"