// Dynamic Cypress configuration utilities

interface EnvironmentConfig {
  baseUrl: string;
  apiUrl: string;
}

interface CypressEnvironments {
  development: EnvironmentConfig;
  staging: EnvironmentConfig;
  production: EnvironmentConfig;
}

// Load environment configuration from cypress.env.json
const loadEnvironmentConfig = (): CypressEnvironments => {
  try {
    return require('../../cypress.env.json');
  } catch (error) {
    console.warn('cypress.env.json not found, using default configuration');
    return {
      development: {
        baseUrl: 'http://localhost:3001',
        apiUrl: 'http://localhost:3000/api/v1'
      },
      staging: {
        baseUrl: 'https://staging.powernode.com',
        apiUrl: 'https://staging-api.powernode.com/api/v1'
      },
      production: {
        baseUrl: 'https://powernode.com',
        apiUrl: 'https://api.powernode.com/api/v1'
      }
    };
  }
};

// Get current environment
export const getCurrentEnvironment = (): keyof CypressEnvironments => {
  return (process.env.CYPRESS_ENV || 
          process.env.NODE_ENV || 
          'development') as keyof CypressEnvironments;
};

// Get environment configuration
export const getEnvironmentConfig = (): EnvironmentConfig => {
  const environments = loadEnvironmentConfig();
  const currentEnv = getCurrentEnvironment();
  return environments[currentEnv] || environments.development;
};

// Get base URL with fallback
export const getBaseUrl = (): string => {
  return process.env.CYPRESS_BASE_URL || 
         process.env.REACT_APP_URL || 
         Cypress.config('baseUrl') ||
         getEnvironmentConfig().baseUrl;
};

// Get API URL with fallback  
export const getApiUrl = (): string => {
  return process.env.CYPRESS_API_URL || 
         process.env.REACT_APP_API_URL || 
         Cypress.env('apiUrl') ||
         getEnvironmentConfig().apiUrl;
};

// Utility to wait for services to be ready
export const waitForServices = () => {
  const baseUrl = getBaseUrl();
  const apiUrl = getApiUrl();
  
  cy.log(`Waiting for services to be ready...`);
  cy.log(`Base URL: ${baseUrl}`);
  cy.log(`API URL: ${apiUrl}`);
  
  // Check frontend is ready
  cy.request({
    url: baseUrl,
    timeout: 30000,
    retryOnStatusCodeFailure: true,
    failOnStatusCode: false
  }).then((response) => {
    expect([200, 304]).to.include(response.status);
  });
  
  // Check API is ready
  cy.request({
    url: `${apiUrl.replace('/api/v1', '')}/health`,
    timeout: 30000,
    retryOnStatusCodeFailure: true,
    failOnStatusCode: false
  }).then((response) => {
    if (response.status !== 200) {
      cy.log(`API health check failed, but continuing tests...`);
    }
  });
};

// Log current configuration
export const logConfiguration = () => {
  const config = getEnvironmentConfig();
  const currentEnv = getCurrentEnvironment();
  
  cy.log('=== Cypress Configuration ===');
  cy.log(`Environment: ${currentEnv}`);
  cy.log(`Base URL: ${config.baseUrl}`);
  cy.log(`API URL: ${config.apiUrl}`);
  cy.log(`Actual Base URL: ${getBaseUrl()}`);
  cy.log(`Actual API URL: ${getApiUrl()}`);
  cy.log('============================');
};