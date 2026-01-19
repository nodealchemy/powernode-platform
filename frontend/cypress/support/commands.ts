/// <reference types="cypress" />

// Custom commands for Powernode application testing

// Import specialized command modules
import './billing-commands';
import './admin-commands';

declare global {
  namespace Cypress {
    interface Chainable {
      /**
       * Custom command to login with email and password
       * @example cy.login('user@example.com', 'password123')
       */
      login(email: string, password: string): Chainable<void>;

      /**
       * Custom command to login using API token
       * @example cy.loginWithToken('jwt-token')
       */
      loginWithToken(token: string): Chainable<void>;

      /**
       * Custom command to register a new user
       * @example cy.register({ email: 'user@example.com', password: 'password123', name: 'John Doe', accountName: 'Test Co' })
       */
      register(userData: {
        email: string;
        password: string;
        name: string;
        accountName: string;
      }): Chainable<void>;

      /**
       * Custom command to clear all application data
       * @example cy.clearAppData()
       */
      clearAppData(): Chainable<void>;

      /**
       * Custom command to seed test data via API
       * @example cy.seedTestData()
       */
      seedTestData(): Chainable<void>;

      /**
       * Custom command to wait for API call to complete
       * @example cy.waitForApi('@getUserData')
       */
      waitForApi(alias: string): Chainable<void>;

      /**
       * Custom command to check notification message
       * @example cy.checkNotification('Success!', 'success')
       */
      checkNotification(message: string, type?: 'success' | 'error' | 'warning' | 'info'): Chainable<void>;

      /**
       * Custom command to logout from the application
       * @example cy.logout()
       */
      logout(): Chainable<void>;
    }
  }
}

// Login command using the UI
Cypress.Commands.add('login', (email: string, password: string) => {
  cy.visit('/login');
  // Wait for form to be ready
  cy.get('[data-testid="email-input"]', { timeout: 10000 }).should('be.visible').clear().type(email);
  cy.get('[data-testid="password-input"]').clear().type(password);
  cy.get('[data-testid="login-submit-btn"]').should('not.be.disabled').click();
  // Wait for redirect to complete (may go to /app or /dashboard)
  cy.url({ timeout: 15000 }).should('not.include', '/login');
});

// Login using API token (bypasses UI)
Cypress.Commands.add('loginWithToken', (token: string) => {
  window.localStorage.setItem('accessToken', token);
  cy.visit('/dashboard');
});

// Register command using the UI - handles plan selection flow
Cypress.Commands.add('register', (userData) => {
  // First, select a plan (registration requires plan selection)
  cy.visit('/plans');
  cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 }).first().click();
  cy.get('[data-testid="continue-to-registration"]', { timeout: 10000 }).click();

  // Wait for registration page to load with plan
  cy.url().should('include', '/register');

  // Use standard form field selectors (name attributes)
  cy.get('input[name="accountName"]', { timeout: 10000 }).should('not.be.disabled').clear().type(userData.accountName);
  cy.get('input[name="name"]').clear().type(userData.name);
  cy.get('input[name="email"]').clear().type(userData.email);
  cy.get('input[name="password"]').clear().type(userData.password);
  cy.get('button[type="submit"]').should('not.be.disabled').click();

  // Wait for redirect to app, dashboard, or verify-email (if email verification required)
  cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard|verify-email)/);
});

// Clear all application data
Cypress.Commands.add('clearAppData', () => {
  cy.clearLocalStorage();
  cy.clearCookies();

  // Clear any persisted Redux state
  indexedDB.deleteDatabase('persist:powernode');

  // Reset API state if needed
  cy.request({
    method: 'POST',
    url: `${Cypress.env('apiUrl')}/test/reset`,
    failOnStatusCode: false,
  });
});

// Logout command - clicks user menu and signs out
Cypress.Commands.add('logout', () => {
  // Click the user menu button in the header (has aria-haspopup="true")
  cy.get('button[aria-haspopup="true"]', { timeout: 10000 }).first().click();

  // Wait for dropdown to appear and click Sign Out
  cy.contains('Sign Out', { timeout: 5000 }).should('be.visible').click();

  // Verify redirect to login page
  cy.url({ timeout: 10000 }).should('include', '/login');
});

// Seed test data via API
Cypress.Commands.add('seedTestData', () => {
  cy.request({
    method: 'POST',
    url: `${Cypress.env('apiUrl')}/test/seed`,
    body: {
      users: [
        {
          email: 'admin@example.com',
          password: 'password123',
          name: 'Admin User',
          role: 'admin',
          accountName: 'Test Company',
        },
        {
          email: 'member@example.com',
          password: 'password123',
          name: 'Member User',
          role: 'member',
          accountName: 'Test Company',
        },
      ],
      plans: [
        {
          name: 'Test Plan',
          price_cents: 1999,
          billing_cycle: 'monthly',
        },
      ],
    },
    failOnStatusCode: false,
  });
});

// Wait for API call with enhanced error handling
Cypress.Commands.add('waitForApi', (alias: string) => {
  cy.wait(alias, { timeout: 15000 }).then((interception) => {
    if (interception.response) {
      expect(interception.response.statusCode).to.be.lessThan(400);
    }
  });
});

// Check notification message
Cypress.Commands.add('checkNotification', (message: string, type = 'success') => {
  cy.get('[data-testid="notification-container"]', { timeout: 10000 })
    .should('be.visible')
    .and('contain', message);
  
  if (type) {
    cy.get('[data-testid="notification-container"]')
      .should('have.class', `notification-${type}`);
  }
});