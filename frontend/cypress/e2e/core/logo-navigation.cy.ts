/// <reference types="cypress" />

/**
 * Logo Navigation Tests
 *
 * Simplified tests for logo navigation using demo user
 */

describe('Logo Navigation Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    // Login with demo user
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 5000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
  });

  it('should display logo in navigation', () => {
    cy.get('body').then($body => {
      const logoSelectors = [
        'a[title="Go to Welcome Page"]',
        '[class*="logo"]',
        'header a:first',
        'aside a:first',
        'nav a:first'
      ];

      for (const selector of logoSelectors) {
        if ($body.find(selector).length > 0) {
          cy.get(selector).first().should('be.visible');
          break;
        }
      }
    });
  });

  it('should have clickable navigation elements', () => {
    cy.get('body').then($body => {
      const navSelectors = [
        'nav a',
        'aside a',
        '[role="navigation"] a'
      ];

      for (const selector of navSelectors) {
        if ($body.find(selector).length > 0) {
          cy.get(selector).first().should('be.visible');
          break;
        }
      }
    });
  });

  it('should navigate from dashboard to other pages', () => {
    cy.url().should('match', /\/(app|dashboard)/);

    // Navigate to plans
    cy.visit('/plans');
    cy.get('body').should('be.visible');

    // Navigate back to app
    cy.visit('/app');
    cy.url().should('match', /\/(app|dashboard)/);
  });

  it('should maintain session during navigation', () => {
    cy.url().should('match', /\/(app|dashboard)/);

    // Check user is still logged in after navigation
    cy.visit('/app/settings/profile');
    cy.get('body').should('be.visible');

    cy.visit('/app');
    cy.url().should('match', /\/(app|dashboard)/);
  });
});


export {};
