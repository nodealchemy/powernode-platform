/// <reference types="cypress" />

/**
 * Unified Login Commands
 *
 * Standardized login commands to replace duplicated login code across test files.
 * Uses Cypress session caching for performance optimization.
 */

export interface LoginOptions {
  /** Skip navigation to dashboard after login (default: false) */
  skipDashboardNav?: boolean;
  /** Custom URL to visit after login (default: /app/dashboard) */
  redirectUrl?: string;
  /** Wait for page load after redirect (default: true) */
  waitForLoad?: boolean;
}

export interface RoleCredentials {
  email: string;
  password: string;
}

declare global {
  namespace Cypress {
    interface Chainable {
      /**
       * Login as the demo user (most common use case)
       * Uses session caching for faster test execution
       * @example cy.loginAsDemo()
       * @example cy.loginAsDemo({ skipDashboardNav: true })
       */
      loginAsDemo(options?: LoginOptions): Chainable<void>;

      /**
       * Login as a specific role
       * @example cy.loginAsRole('admin')
       * @example cy.loginAsRole('billing.manager')
       */
      loginAsRole(role: string, options?: LoginOptions): Chainable<void>;

      /**
       * Login via API (bypasses UI for faster tests)
       * @example cy.loginViaAPI('user@example.com', 'password')
       */
      loginViaAPI(email: string, password: string): Chainable<void>;

      /**
       * Login via UI with any credentials
       * @example cy.loginViaUI('user@example.com', 'password')
       */
      loginViaUI(email: string, password: string, options?: LoginOptions): Chainable<void>;

      /**
       * Standard test setup: clear data, setup intercepts, login
       * @example cy.standardTestSetup()
       * @example cy.standardTestSetup({ role: 'admin' })
       */
      standardTestSetup(options?: { role?: string; intercepts?: string[] }): Chainable<void>;
    }
  }
}

// Get credentials from environment or use defaults
const getCredentials = (role?: string): RoleCredentials => {
  if (role) {
    const roleKey = role.toUpperCase().replace('.', '_');
    const envCredentials = Cypress.env(`${roleKey}_CREDENTIALS`);
    if (envCredentials) {
      return envCredentials;
    }
  }

  // Default demo credentials
  return {
    email: Cypress.env('DEMO_EMAIL') || 'demo@democompany.com',
    password: Cypress.env('DEMO_PASSWORD') || 'DemoSecure456!@#$%',
  };
};

// Login as demo user with session caching
Cypress.Commands.add('loginAsDemo', (options: LoginOptions = {}) => {
  const { skipDashboardNav = false, redirectUrl, waitForLoad = true } = options;
  const credentials = getCredentials();

  cy.session(
    ['demo-user', credentials.email],
    () => {
      // Perform UI login
      cy.visit('/login');
      cy.get('[data-testid="email-input"]', { timeout: 10000 })
        .should('be.visible')
        .clear()
        .type(credentials.email);
      cy.get('[data-testid="password-input"]').clear().type(credentials.password);
      cy.get('[data-testid="login-submit-btn"]').should('not.be.disabled').click();
      cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
    },
    {
      validate: () => {
        // Validate session by checking localStorage
        cy.window().then((win) => {
          const token = win.localStorage.getItem('access_token');
          expect(token).to.exist;
        });
      },
    }
  );

  // Navigate after session restoration
  if (!skipDashboardNav) {
    const targetUrl = redirectUrl || '/app/dashboard';
    cy.visit(targetUrl);
    if (waitForLoad) {
      cy.waitForPageLoad();
    }
  }
});

// Login as specific role
Cypress.Commands.add('loginAsRole', (role: string, options: LoginOptions = {}) => {
  const { skipDashboardNav = false, redirectUrl, waitForLoad = true } = options;
  const credentials = getCredentials(role);

  cy.session(
    ['role-user', role, credentials.email],
    () => {
      cy.visit('/login');
      cy.get('[data-testid="email-input"]', { timeout: 10000 })
        .should('be.visible')
        .clear()
        .type(credentials.email);
      cy.get('[data-testid="password-input"]').clear().type(credentials.password);
      cy.get('[data-testid="login-submit-btn"]').should('not.be.disabled').click();
      cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
    },
    {
      validate: () => {
        cy.window().then((win) => {
          const token = win.localStorage.getItem('access_token');
          expect(token).to.exist;
        });
      },
    }
  );

  if (!skipDashboardNav) {
    const targetUrl = redirectUrl || '/app/dashboard';
    cy.visit(targetUrl);
    if (waitForLoad) {
      cy.waitForPageLoad();
    }
  }
});

// Login via API (fastest, bypasses UI)
Cypress.Commands.add('loginViaAPI', (email: string, password: string) => {
  const apiUrl = Cypress.env('apiUrl') || 'http://localhost:3000/api/v1';

  cy.request({
    method: 'POST',
    url: `${apiUrl}/auth/login`,
    body: { email, password },
    failOnStatusCode: false,
  }).then((response) => {
    if (response.status === 200 && response.body?.data?.access_token) {
      cy.window().then((win) => {
        win.localStorage.setItem('access_token', response.body.data.access_token);
        if (response.body.data.refresh_token) {
          win.localStorage.setItem('refresh_token', response.body.data.refresh_token);
        }
      });
    } else {
      // Fallback to UI login if API fails
      cy.loginViaUI(email, password);
    }
  });
});

// Login via UI with any credentials
Cypress.Commands.add('loginViaUI', (email: string, password: string, options: LoginOptions = {}) => {
  const { skipDashboardNav = false, redirectUrl, waitForLoad = true } = options;

  cy.visit('/login');
  cy.get('[data-testid="email-input"]', { timeout: 10000 })
    .should('be.visible')
    .clear()
    .type(email);
  cy.get('[data-testid="password-input"]').clear().type(password);
  cy.get('[data-testid="login-submit-btn"]').should('not.be.disabled').click();
  cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);

  if (!skipDashboardNav && redirectUrl) {
    cy.visit(redirectUrl);
    if (waitForLoad) {
      cy.waitForPageLoad();
    }
  }
});

// Standard test setup (combines common beforeEach operations)
Cypress.Commands.add('standardTestSetup', (options = {}) => {
  const { role, intercepts = [] } = options;

  // Clear application data
  cy.clearAppData();

  // Setup common API intercepts
  cy.setupApiIntercepts();

  // Setup feature-specific intercepts
  intercepts.forEach((interceptType) => {
    switch (interceptType) {
      case 'ai':
        cy.setupAiIntercepts();
        break;
      case 'admin':
        cy.setupAdminIntercepts();
        break;
      case 'devops':
        cy.setupDevopsIntercepts();
        break;
      case 'system':
        cy.setupSystemIntercepts();
        break;
      case 'marketplace':
        cy.setupMarketplaceIntercepts();
        break;
      case 'content':
        cy.setupContentIntercepts();
        break;
      case 'privacy':
        cy.setupPrivacyIntercepts();
        break;
    }
  });

  // Login with appropriate role
  if (role) {
    cy.loginAsRole(role);
  } else {
    cy.loginAsDemo();
  }
});

export {};
