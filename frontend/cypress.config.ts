import { defineConfig } from 'cypress';
import cypressSplit from 'cypress-split';

export default defineConfig({
  e2e: {
    baseUrl: 'http://localhost:3001',
    viewportWidth: 1280,
    viewportHeight: 720,
    video: false,
    screenshotOnRunFailure: true,
    // Optimized timeouts for faster test execution
    defaultCommandTimeout: 5000,
    requestTimeout: 8000,
    responseTimeout: 8000,
    pageLoadTimeout: 15000,
    retries: {
      runMode: process.env.CI ? 2 : 0,  // No retries in dev for faster feedback
      openMode: 0,
    },
    // Parallelization settings
    // Run tests in parallel: npm run cypress:parallel:4 (splits across 4 processes)
    experimentalRunAllSpecs: true, // Enables running multiple spec files more efficiently
    async setupNodeEvents(on, config) {
      // Enable cypress-split for local parallelization
      cypressSplit(on, config);

      // Assemble extension e2e specs/support into core cypress/ before spec
      // discovery. Source-of-truth lives in extensions/*/frontend/cypress/;
      // the copied outputs are gitignored. See cypress/assemble-extensions.cjs.
      // eslint-disable-next-line @typescript-eslint/no-var-requires
      const assembleExtensionE2E = require('./cypress/assemble-extensions.cjs');
      const assembledSlugs: string[] = assembleExtensionE2E(__dirname);
      if (assembledSlugs.length) {
        // eslint-disable-next-line no-console
        console.log(`[cypress] assembled extension e2e: ${assembledSlugs.join(', ')}`);
      }

      // Provision per-run test-user passwords via the real reset endpoint
      // (scripts/e2e/provision-test-logins.cjs) — no credentials file on disk.
      // The env keys (DEMO_EMAIL/DEMO_PASSWORD, ...) are unchanged, so
      // login-commands.ts and every existing Cypress.env() call site are
      // untouched. Honors a pre-set E2E_LOGINS env for cypress-split parallel
      // runs (provision once, share) — see the helper's header.
      // eslint-disable-next-line @typescript-eslint/no-var-requires
      const { provisionTestLogins } = require('../scripts/e2e/provision-test-logins.cjs');
      try {
        const logins: Record<string, { email: string; password: string }> = await provisionTestLogins();
        const flat: Record<string, string> = {};
        for (const [role, cred] of Object.entries(logins)) {
          const prefix = role.toUpperCase();
          flat[`${prefix}_EMAIL`] = cred.email;
          flat[`${prefix}_PASSWORD`] = cred.password;
        }
        config.env = { ...config.env, ...flat };
        // eslint-disable-next-line no-console
        console.log(`✅ Provisioned per-run test logins: ${Object.keys(logins).join(', ')}`);
      } catch (err) {
        // eslint-disable-next-line no-console
        console.warn('⚠️ Failed to provision test logins:', err instanceof Error ? err.message : err);
        // eslint-disable-next-line no-console
        console.warn('   Ensure the backend is up and demo users are seeded (POWERNODE_SEED_DEMO=true rails db:seed).');
      }

      return config;
    },
    env: {
      apiUrl: 'http://localhost:3000/api/v1',
      // Note: test-user credentials are provisioned per run (no file on disk) —
      // setupNodeEvents calls scripts/e2e/provision-test-logins.cjs, which mints
      // an admin JWT and resets each seeded user via the real reset endpoint,
      // populating *_EMAIL/*_PASSWORD in config.env.
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