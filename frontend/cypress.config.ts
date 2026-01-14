import { defineConfig } from 'cypress';
import cypressSplit from 'cypress-split';

export default defineConfig({
  e2e: {
    baseUrl: 'http://localhost:3001',
    viewportWidth: 1280,
    viewportHeight: 720,
    video: false,
    screenshotOnRunFailure: true,
    defaultCommandTimeout: 15000,
    requestTimeout: 15000,
    responseTimeout: 15000,
    pageLoadTimeout: 30000,
    retries: {
      runMode: 2,
      openMode: 0,
    },
    // Parallelization settings
    // Run tests in parallel: npm run cypress:parallel:4 (splits across 4 processes)
    experimentalRunAllSpecs: true, // Enables running multiple spec files more efficiently
    setupNodeEvents(on, config) {
      // Enable cypress-split for local parallelization
      cypressSplit(on, config);

      return config;
    },
    env: {
      apiUrl: 'http://localhost:3000/api/v1',
      adminEmail: 'admin@example.com',
      adminPassword: 'Qx7#mK9@pL2$nZ6!',
      billingManagerEmail: 'billing@example.com',
      billingManagerPassword: 'Rw8$jN4#vX3@qM5!',
    },
    supportFile: 'cypress/support/e2e.ts',
    specPattern: 'cypress/e2e/**/*.cy.{js,jsx,ts,tsx}',
  },
  component: {
    devServer: {
      framework: 'create-react-app',
      bundler: 'webpack',
    },
    setupNodeEvents(on, config) {
      // implement node event listeners here
    },
    supportFile: 'cypress/support/component.ts',
    specPattern: 'cypress/component/**/*.cy.{js,jsx,ts,tsx}',
  },
});