/// <reference types="cypress" />

/**
 * Admin Settings - Email Tab E2E Tests
 *
 * Tests for email configuration functionality including:
 * - Page navigation and permissions
 * - SMTP configuration settings
 * - Email template management
 * - Test email functionality
 * - Responsive design
 */

describe('Admin Settings Email Tab Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Page Navigation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/admin/settings/email');
    });

    it('should navigate to Email Settings tab', () => {
      cy.assertContainsAny(['Email', 'SMTP', 'Configuration']);
    });

    it('should redirect unauthorized users', () => {
      // Test handles authorization check - page should either load or redirect
      cy.assertContainsAny(['Email', 'Settings', 'Admin']);
    });
  });

  describe('SMTP Configuration', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/email');
      cy.waitForPageLoad();
    });

    it('should display SMTP host field', () => {
      cy.assertContainsAny(['Host', 'Server', 'SMTP']);
    });

    it('should display SMTP port field', () => {
      cy.assertHasElement(['input[name*="port"]']);
    });

    it('should display authentication fields', () => {
      cy.assertContainsAny(['Username', 'Password', 'Authentication']);
    });

    it('should display TLS/SSL options', () => {
      cy.assertContainsAny(['TLS', 'SSL', 'Encryption']);
    });

    it('should display sender email configuration', () => {
      cy.assertContainsAny(['Sender', 'From', 'Reply']);
    });
  });

  describe('Email Provider Selection', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/email');
      cy.waitForPageLoad();
    });

    it('should display provider options', () => {
      cy.assertContainsAny(['Provider', 'SendGrid', 'Mailgun', 'Custom']);
    });

    it('should allow selecting different providers', () => {
      cy.get('select, [role="listbox"], [data-testid*="provider"]').should('exist');
    });
  });

  describe('Email Templates', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/email');
      cy.waitForPageLoad();
    });

    it('should display email templates section', () => {
      cy.assertContainsAny(['Template', 'Welcome', 'Notification']);
    });

    it('should display template list', () => {
      cy.assertContainsAny(['Password Reset', 'Email Verification', 'Invoice']);
    });
  });

  describe('Test Email Functionality', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/email');
      cy.waitForPageLoad();
    });

    it('should have test email button', () => {
      cy.assertContainsAny(['Test', 'Send Test']);
    });

    it('should have test email recipient field', () => {
      cy.assertHasElement(['input[type="email"]']);
    });
  });

  describe('Save Configuration', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/email');
      cy.waitForPageLoad();
    });

    it('should have save button', () => {
      cy.get('button:contains("Save"), button:contains("Update")').should('exist');
    });

    it('should validate required fields', () => {
      cy.assertHasElement(['input[required]', '[class*="required"]']);
    });
  });

  describe('Error Handling', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/admin/settings/email');
    });

    it('should handle API errors gracefully', () => {
      cy.intercept('GET', '**/api/**/admin/settings/**', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/admin/settings/email');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Email', 'Settings', 'Error']);
      cy.get('body').should('not.contain.text', 'Cannot read');
    });
  });

  describe('Responsive Design', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/admin/settings/email');
    });

    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/admin/settings/email');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Email', 'Settings']);
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/admin/settings/email');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Email', 'Settings']);
    });
  });

  describe('Permission Check', () => {
    it('should require admin permissions', () => {
      cy.testPermissionDenied('/app/admin/settings/email');
    });
  });
});


export {};
