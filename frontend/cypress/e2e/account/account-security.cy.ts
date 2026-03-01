/// <reference types="cypress" />

/**
 * Account Security Tests
 *
 * Tests for Account Security functionality including:
 * - Security overview
 * - Password management
 * - Two-factor authentication
 * - Security logs
 * - Trusted devices
 * - API tokens
 */

describe('Account Security Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Security Overview', () => {
    it('should navigate to security page', () => {
      cy.visit('/app/account/security');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Security', 'Password', 'Authentication']);
    });

    it('should display security status', () => {
      cy.visit('/app/account/security');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Strong', 'Good', 'Secure', 'Status']);
    });

    it('should display security recommendations', () => {
      cy.visit('/app/account/security');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Recommend', 'Enable', 'Suggest']);
    });
  });

  describe('Password Management', () => {
    beforeEach(() => {
      cy.visit('/app/account/security/password');
      cy.waitForPageLoad();
    });

    it('should display password section', () => {
      cy.assertContainsAny(['Password', 'Change']);
    });

    it('should have change password button', () => {
      cy.get('button').contains(/Change|Update/i).should('exist');
    });

    it('should display last password change', () => {
      cy.assertContainsAny(['Last changed', 'ago', 'Password updated']);
    });
  });

  describe('Two-Factor Authentication', () => {
    beforeEach(() => {
      cy.visit('/app/account/security/2fa');
      cy.waitForPageLoad();
    });

    it('should display 2FA section', () => {
      cy.assertContainsAny(['Two-factor', '2FA', 'Authenticator']);
    });

    it('should have enable/disable 2FA button', () => {
      cy.get('button').contains(/Enable|Disable|Setup/i).should('exist');
    });

    it('should display 2FA methods', () => {
      cy.assertContainsAny(['Authenticator', 'SMS', 'Email']);
    });

    it('should display backup codes option', () => {
      cy.assertContainsAny(['Backup', 'Recovery', 'Code']);
    });
  });

  describe('Security Logs', () => {
    it('should navigate to security logs', () => {
      cy.visit('/app/account/security/logs');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Log', 'Activity', 'History']);
    });

    it('should display login history', () => {
      cy.visit('/app/account/security/logs');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Login', 'Sign in']);
    });

    it('should display device/location info', () => {
      cy.visit('/app/account/security/logs');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Device', 'Location', 'IP']);
    });
  });

  describe('Trusted Devices', () => {
    it('should navigate to trusted devices', () => {
      cy.visit('/app/account/security/devices');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Device', 'Trusted', 'Browser']);
    });

    it('should display device list', () => {
      cy.visit('/app/account/security/devices');
      cy.waitForPageLoad();
      cy.assertHasElement(['[data-testid="device-list"]', 'table', '.device-card']);
    });

    it('should have remove device option', () => {
      cy.visit('/app/account/security/devices');
      cy.waitForPageLoad();
      cy.get('button').contains(/Remove|Revoke/i).should('exist');
    });
  });

  describe('API Tokens', () => {
    it('should navigate to API tokens', () => {
      cy.visit('/app/account/security/tokens');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Token', 'API', 'Key']);
    });

    it('should have create token button', () => {
      cy.visit('/app/account/security/tokens');
      cy.waitForPageLoad();
      cy.get('button').contains(/Create|Generate|New/i).should('exist');
    });

    it('should display token list', () => {
      cy.visit('/app/account/security/tokens');
      cy.waitForPageLoad();
      cy.assertHasElement(['table', '[data-testid="tokens-list"]']);
    });

    it('should have revoke token option', () => {
      cy.visit('/app/account/security/tokens');
      cy.waitForPageLoad();
      cy.get('button').contains(/Revoke|Delete/i).should('exist');
    });
  });

  describe('Responsive Design', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display security correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/account/security');
        cy.waitForPageLoad();
        cy.assertContainsAny(['Security', 'Password', 'Authentication']);
      });
    });
  });
});
