#!/bin/bash
# Run Cypress tests in development environment

export CYPRESS_ENV=development
export CYPRESS_BASE_URL=http://localhost:3001
export CYPRESS_API_URL=http://localhost:3000/api/v1

echo "Running Cypress tests in DEVELOPMENT mode"
echo "Base URL: $CYPRESS_BASE_URL"
echo "API URL: $CYPRESS_API_URL"

npx cypress run --headless "$@"