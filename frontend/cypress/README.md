# Cypress Configuration Guide

This document explains the dynamic Cypress configuration setup for the Powernode platform frontend.

## Overview

The Cypress configuration has been enhanced to support dynamic baseUrl and environment-specific settings, eliminating the TypeScript compilation warning about missing `baseUrl` in `compilerOptions`.

## Configuration Files

### Core Configuration Files

1. **`cypress.config.ts`** - Main Cypress configuration with dynamic URL resolution
2. **`cypress/tsconfig.json`** - Cypress-specific TypeScript configuration
3. **`cypress.env.json`** - Environment-specific URL configurations
4. **`cypress/support/config.ts`** - Utility functions for dynamic configuration

### TypeScript Configuration

- **Main TypeScript Config**: `tsconfig.json` includes `baseUrl: "."` and path mappings
- **Cypress TypeScript Config**: `cypress/tsconfig.json` extends main config with Cypress-specific settings

## Environment Configuration

### Environment Variables

The configuration supports multiple levels of environment variables:

```bash
# Cypress-specific environment variables (highest priority)
CYPRESS_ENV=development|staging|production
CYPRESS_BASE_URL=http://localhost:3001
CYPRESS_API_URL=http://localhost:3000/api/v1

# React app environment variables (fallback)
REACT_APP_URL=http://localhost:3001
REACT_APP_API_URL=http://localhost:3000/api/v1

# Node environment (lowest priority)
NODE_ENV=development|staging|production
```

### Environment Configuration Files

**`cypress.env.json`**:
```json
{
  "development": {
    "baseUrl": "http://localhost:3001",
    "apiUrl": "http://localhost:3000/api/v1"
  },
  "staging": {
    "baseUrl": "https://staging.powernode.com",
    "apiUrl": "https://staging-api.powernode.com/api/v1"
  },
  "production": {
    "baseUrl": "https://powernode.com",
    "apiUrl": "https://api.powernode.com/api/v1"
  }
}
```

## Running Cypress Tests

### npm Scripts

```bash
# Standard Cypress commands
npm run cypress:open        # Open Cypress GUI
npm run cypress:run         # Run tests headless
npm run cypress:headless    # Run with environment variables

# Environment-specific scripts
npm run cypress:dev         # Development environment
npm run cypress:staging     # Staging environment  
npm run cypress:prod        # Production environment

# Run specific test file
npm run cypress:spec -- "cypress/e2e/auth-tests.cy.ts"
```

### Shell Scripts

```bash
# Development environment
./scripts/cypress-dev.sh

# Staging environment
./scripts/cypress-staging.sh

# Production environment
./scripts/cypress-prod.sh

# With custom spec file
./scripts/cypress-dev.sh --spec "cypress/e2e/auth-tests.cy.ts"
```

### Direct Commands

```bash
# With environment variables
CYPRESS_ENV=development cypress run --headless

# With custom URLs
CYPRESS_BASE_URL=http://localhost:3001 CYPRESS_API_URL=http://localhost:3000/api/v1 cypress run

# Multiple environments
CYPRESS_ENV=staging cypress run --headless
```

## Configuration Priority

The configuration follows this priority order (highest to lowest):

1. **Environment Variables**: `CYPRESS_BASE_URL`, `CYPRESS_API_URL`
2. **React App Variables**: `REACT_APP_URL`, `REACT_APP_API_URL`  
3. **Cypress Config**: Values set in `cypress.config.ts`
4. **Environment Files**: Values from `cypress.env.json`
5. **Defaults**: Hardcoded fallback values

## Dynamic Features

### Configuration Logging

The configuration is automatically logged at test startup:

```
=== Cypress Configuration ===
Environment: development
Base URL: http://localhost:3001
API URL: http://localhost:3000/api/v1
Actual Base URL: http://localhost:3001
Actual API URL: http://localhost:3000/api/v1
============================
```

### Service Health Checks

The configuration includes utility functions to wait for services:

```typescript
import { waitForServices, getBaseUrl, getApiUrl } from '../support/config';

// Wait for both frontend and backend to be ready
waitForServices();

// Get current URLs
const baseUrl = getBaseUrl();
const apiUrl = getApiUrl();
```

### Environment-Specific Timeouts

Different environments can have different timeout settings:

- **Development**: Standard timeouts (10s)
- **Production**: Extended timeouts (15s) for slower networks

## Troubleshooting

### Common Issues

1. **"Missing baseUrl in compilerOptions" warning**:
   - ✅ **Resolved**: Added `baseUrl: "."` to both main and Cypress tsconfig files

2. **Wrong URLs being used**:
   - Check environment variable precedence
   - Verify `cypress.env.json` environment names match `CYPRESS_ENV`
   - Review configuration logging output

3. **TypeScript import errors**:
   - Ensure path mappings are correct in `cypress/tsconfig.json`
   - Verify the Cypress tsconfig extends the main tsconfig

### Debugging Configuration

1. **View Current Configuration**:
   ```typescript
   import { logConfiguration } from '../support/config';
   logConfiguration(); // Logs all current settings
   ```

2. **Check Environment Variables**:
   ```bash
   echo "CYPRESS_ENV: $CYPRESS_ENV"
   echo "CYPRESS_BASE_URL: $CYPRESS_BASE_URL" 
   echo "CYPRESS_API_URL: $CYPRESS_API_URL"
   ```

3. **Verify Configuration Load**:
   - Configuration is logged automatically at test startup
   - Check the Cypress console output for configuration details

## Best Practices

### Environment Management

1. **Use environment-specific scripts** for consistent configuration
2. **Set environment variables** in CI/CD pipelines
3. **Keep sensitive URLs** out of committed files when possible
4. **Use the development environment** for local testing

### Test Organization

1. **Use configuration utilities** from `cypress/support/config.ts`
2. **Check service availability** with `waitForServices()`
3. **Log configuration** when debugging environment issues
4. **Use environment-specific test data** when appropriate

### CI/CD Integration

```yaml
# Example GitHub Actions configuration
- name: Run Cypress Tests
  run: |
    export CYPRESS_ENV=staging
    export CYPRESS_BASE_URL=https://staging.powernode.com
    export CYPRESS_API_URL=https://staging-api.powernode.com/api/v1
    npm run cypress:headless
```

This configuration provides a robust, flexible foundation for running Cypress tests across different environments while maintaining clean TypeScript compilation and proper path resolution.