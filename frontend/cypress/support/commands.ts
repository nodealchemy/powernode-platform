/// <reference types="cypress" />

// Custom commands for Powernode application testing

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
       * @example cy.register({ email: 'user@example.com', password: 'password123', firstName: 'John', lastName: 'Doe', accountName: 'Test Co' })
       */
      register(userData: {
        email: string;
        password: string;
        firstName: string;
        lastName: string;
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
    }
  }
}

// Login command using the UI
Cypress.Commands.add('login', (email: string, password: string) => {
  cy.visit('/login');
  cy.get('input[placeholder="Email address"]').type(email);
  cy.get('input[placeholder="Password"]').type(password);
  cy.get('button[type="submit"]').click();
  cy.url().should('include', '/dashboard');
});

// Login using API token (bypasses UI)
Cypress.Commands.add('loginWithToken', (token: string) => {
  window.localStorage.setItem('accessToken', token);
  cy.visit('/dashboard');
});

// Register command using the UI
Cypress.Commands.add('register', (userData) => {
  cy.visit('/register');
  cy.get('input[name="firstName"]').type(userData.firstName);
  cy.get('input[name="lastName"]').type(userData.lastName);
  cy.get('input[name="accountName"]').type(userData.accountName);
  cy.get('input[name="email"]').type(userData.email);
  cy.get('input[name="password"]').type(userData.password);
  cy.get('button[type="submit"]').click();
  cy.url().should('include', '/dashboard');
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
          firstName: 'Admin',
          lastName: 'User',
          roles: ['admin'],
          accountName: 'Test Company',
        },
        {
          email: 'member@example.com',
          password: 'password123',
          firstName: 'Member',
          lastName: 'User',
          roles: ['member'],
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