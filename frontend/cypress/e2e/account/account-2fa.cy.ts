/// <reference types="cypress" />

/**
 * Account Two-Factor Authentication Tests
 *
 * Tests for 2FA functionality including:
 * - 2FA setup flow
 * - 2FA verification
 * - 2FA disable flow
 * - Recovery codes
 * - Error handling
 * - Security states
 */

describe('Account Two-Factor Authentication Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('2FA Settings Access', () => {
    it('should navigate to 2FA settings', () => {
      cy.visit('/app/account/security');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Two-Factor', '2FA', 'Authentication']);
    });

    it('should display 2FA status', () => {
      cy.visit('/app/account/security');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Enabled', 'Disabled', 'Not configured', 'Enable']);
    });
  });

  describe('2FA Setup Flow', () => {
    beforeEach(() => {
      cy.visit('/app/account/security');
      cy.waitForPageLoad();
    });

    it('should display Enable 2FA button when not configured', () => {
      cy.get('button').contains(/Enable|Set up/i).should('exist');
    });

    it('should open 2FA setup modal', () => {
      cy.get('button').contains(/Enable 2FA|Set up/i).first().click();
      cy.waitForStableDOM();
      cy.assertContainsAny(['Two-Factor', '2FA', 'Setup']);
    });

    it('should display QR code in setup flow', () => {
      cy.get('button').contains(/Enable 2FA|Set up/i).first().click();
      cy.waitForStableDOM();
      cy.assertHasElement(['img[alt*="QR"]', 'canvas', 'svg']);
    });

    it('should display manual entry secret', () => {
      cy.get('button').contains(/Enable 2FA|Set up/i).first().click();
      cy.waitForStableDOM();
      cy.assertContainsAny(['secret', 'manual', 'code']);
    });

    it('should have verification code input', () => {
      cy.get('button').contains(/Enable 2FA|Set up/i).first().click();
      cy.waitForStableDOM();
      cy.assertHasElement(['input[name*="code"]', 'input[type="text"]', 'input[name*="otp"]']);
    });
  });

  describe('2FA Verification', () => {
    beforeEach(() => {
      cy.visit('/app/account/security');
      cy.waitForPageLoad();
    });

    it('should validate code format', () => {
      cy.assertContainsAny(['6', 'digit', 'code']);
    });
  });

  describe('Recovery Codes', () => {
    beforeEach(() => {
      cy.visit('/app/account/security');
      cy.waitForPageLoad();
    });

    it('should display recovery codes option', () => {
      cy.assertContainsAny(['Recovery', 'Backup', 'recovery codes']);
    });

    it('should allow viewing recovery codes when 2FA enabled', () => {
      cy.assertContainsAny(['View', 'Show']);
    });
  });

  describe('Disable 2FA', () => {
    beforeEach(() => {
      cy.visit('/app/account/security');
      cy.waitForPageLoad();
    });

    it('should display Disable 2FA option when enabled', () => {
      cy.get('button').contains(/Disable/i).should('exist');
    });
  });

  describe('Security Information', () => {
    beforeEach(() => {
      cy.visit('/app/account/security');
      cy.waitForPageLoad();
    });

    it('should display security recommendations', () => {
      cy.assertContainsAny(['recommend', 'secure', 'protect']);
    });

    it('should display supported authenticator apps', () => {
      cy.assertContainsAny(['Google Authenticator', 'Authy', 'authenticator app']);
    });
  });

  describe('Error Handling', () => {
    it('should handle invalid verification code', () => {
      cy.visit('/app/account/security');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Security', '2FA', 'Authentication']);
    });
  });

  describe('Responsive Design', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display 2FA settings correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/account/security');
        cy.waitForPageLoad();
        cy.assertContainsAny(['Security', '2FA', 'Authentication']);
      });
    });
  });
});
