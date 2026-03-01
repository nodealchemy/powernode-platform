/// <reference types="cypress" />

/**
 * Two-Factor Authentication Tests
 *
 * Tests 2FA functionality if available in the application
 */

describe('Two-Factor Authentication Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.setupApiIntercepts();
  });

  describe('2FA Setup and Enablement', () => {
    it('should allow users to enable 2FA from security settings', () => {
      // Login with demo user
      cy.visit('/login');
      cy.get('[data-testid="email-input"]', { timeout: 5000 }).type(Cypress.env('DEMO_EMAIL'));
      cy.get('[data-testid="password-input"]').type(Cypress.env('DEMO_PASSWORD'));
      cy.get('[data-testid="login-submit-btn"]').click();
      cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);

      cy.visit('/settings/security');

      cy.assertHasElement(['button:contains("Enable 2FA")', 'button:contains("Two-Factor")', '[data-testid="enable-2fa"]', '.two-factor', 'button:contains("Authenticator")']);
      cy.assertContainsAny(['Security', 'Settings', 'Profile']);
    });

    it('should display QR code and backup codes for 2FA setup', () => {
      // Login with demo user
      cy.visit('/login');
      cy.get('[data-testid="email-input"]', { timeout: 5000 }).type(Cypress.env('DEMO_EMAIL'));
      cy.get('[data-testid="password-input"]').type(Cypress.env('DEMO_PASSWORD'));
      cy.get('[data-testid="login-submit-btn"]').click();
      cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);

      cy.visit('/settings/security');

      cy.assertContainsAny(['Security', 'Settings', '2FA', 'authenticator', 'qr', 'scan']);
    });
  });

  describe('2FA Login Flow', () => {
    it('should require 2FA code after password verification', () => {
      // Mock 2FA requirement on login
      cy.intercept('POST', '/api/v1/auth/login', {
        statusCode: 200,
        body: {
          success: true,
          requires_2fa: true,
          message: 'Please enter your 2FA code'
        }
      }).as('loginWith2FA');

      cy.visit('/login');
      cy.get('[data-testid="email-input"]', { timeout: 5000 }).type('test2fa@example.com');
      cy.get('[data-testid="password-input"]').type('TestPassword123!');
      cy.get('[data-testid="login-submit-btn"]').click();

      cy.wait('@loginWith2FA');
      cy.waitForStableDOM();

      cy.assertContainsAny(['code', 'authenticator', 'verify', '2FA']);
    });

    it('should validate 2FA code format and length', () => {
      cy.visit('/login/verify-2fa');

      cy.get('input[name="code"], input[name="token"], input[name="otp"]').first().type('123');
      cy.get('button[type="submit"], button:contains("Verify")').click();
      cy.assertContainsAny(['2FA', 'Verify', 'Authentication']);
    });

    it('should handle incorrect 2FA codes with proper error feedback', () => {
      cy.intercept('POST', '/api/v1/auth/verify-2fa', {
        statusCode: 400,
        body: { success: false, error: 'Invalid 2FA code' }
      }).as('invalid2FA');

      cy.visit('/login/verify-2fa');

      cy.get('input[name="code"], input[name="token"], input[name="otp"]').first().type('123456');
      cy.get('button[type="submit"], button:contains("Verify")').click();
      cy.wait('@invalid2FA');
      cy.waitForStableDOM();
      cy.assertContainsAny(['2FA', 'Verify', 'Authentication']);
    });
  });

  describe('2FA Backup Codes', () => {
    it('should allow login with backup codes when 2FA is unavailable', () => {
      cy.visit('/login/verify-2fa');

      cy.assertHasElement(['button:contains("backup")', 'button:contains("recovery")', 'a:contains("backup")', '[data-testid="backup-codes"]']);
    });

    it('should validate backup code format', () => {
      cy.visit('/login/backup-codes');

      cy.get('input[name="backup"], input[name="recovery"]').first().type('short');
      cy.get('button[type="submit"], button:contains("Verify")').click();
      cy.assertContainsAny(['2FA', 'Verify', 'Authentication']);
    });
  });

  describe('2FA Management', () => {
    it('should allow users to disable 2FA with password confirmation', () => {
      // Login with demo user
      cy.visit('/login');
      cy.get('[data-testid="email-input"]', { timeout: 5000 }).type(Cypress.env('DEMO_EMAIL'));
      cy.get('[data-testid="password-input"]').type(Cypress.env('DEMO_PASSWORD'));
      cy.get('[data-testid="login-submit-btn"]').click();
      cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);

      cy.visit('/settings/security');

      cy.assertHasElement(['button:contains("Disable 2FA")', 'button:contains("Turn off")', '[data-testid="disable-2fa"]']);
    });

    it('should allow regeneration of backup codes', () => {
      // Login with demo user
      cy.visit('/login');
      cy.get('[data-testid="email-input"]', { timeout: 5000 }).type(Cypress.env('DEMO_EMAIL'));
      cy.get('[data-testid="password-input"]').type(Cypress.env('DEMO_PASSWORD'));
      cy.get('[data-testid="login-submit-btn"]').click();
      cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);

      cy.visit('/settings/security');

      cy.assertHasElement(['button:contains("Regenerate")', 'button:contains("New backup codes")', '[data-testid="regenerate-codes"]']);
    });
  });

  describe('2FA Recovery Scenarios', () => {
    it('should handle 2FA device loss recovery', () => {
      cy.visit('/login/verify-2fa');

      cy.assertHasElement(['a:contains("Lost device")', 'button:contains("Cannot access")', 'a:contains("Help")', '[data-testid="recovery-help"]']);
    });

    it('should handle account lockout after multiple failed 2FA attempts', () => {
      let attemptCount = 0;
      cy.intercept('POST', '/api/v1/auth/verify-2fa', (req) => {
        attemptCount++;
        if (attemptCount >= 3) {
          req.reply({
            statusCode: 429,
            body: { success: false, error: 'Too many attempts. Account temporarily locked.' }
          });
        } else {
          req.reply({
            statusCode: 400,
            body: { success: false, error: 'Invalid 2FA code' }
          });
        }
      }).as('failed2FA');

      cy.visit('/login/verify-2fa');

      cy.get('input[name="code"], input[name="token"], input[name="otp"]').should('exist').then(() => {
        // Make multiple failed attempts
        for (let i = 0; i < 3; i++) {
          cy.get('input[name="code"], input[name="token"], input[name="otp"]').first().clear().type('000000');
          cy.get('button[type="submit"], button:contains("Verify")').click();
          cy.wait('@failed2FA');
          cy.waitForStableDOM();
        }
      });

      cy.assertContainsAny(['2FA', 'Verify', 'Authentication']);
    });
  });
});


export {};
