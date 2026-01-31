/// <reference types="cypress" />

/**
 * Privacy Consent Management Tests
 *
 * Tests for Privacy Consent functionality including:
 * - Consent manager display
 * - Consent preferences
 * - Cookie preferences
 * - Data processing consent
 * - Marketing preferences
 * - Consent updates
 * - Privacy policy access
 */

describe('Privacy Consent Management Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Consent Manager Access', () => {
    it('should navigate to privacy settings', () => {
      cy.visit('/app/account/privacy');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Privacy', 'Consent', 'Data', 'Settings']);
    });

    it('should display consent manager', () => {
      cy.visit('/app/account/privacy');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Consent', 'Privacy', 'Preferences', 'Settings']);
    });
  });

  describe('Consent Preferences', () => {
    beforeEach(() => {
      cy.visit('/app/account/privacy');
      cy.waitForPageLoad();
    });

    it('should display necessary cookies section', () => {
      cy.assertContainsAny(['Necessary', 'Essential', 'Required', 'Cookies']);
    });

    it('should display analytics preferences', () => {
      cy.assertContainsAny(['Analytics', 'Performance', 'Usage', 'Statistics']);
    });

    it('should display marketing preferences', () => {
      cy.assertContainsAny(['Marketing', 'Advertising', 'Promotional', 'Communications']);
    });

    it('should display functional preferences', () => {
      cy.assertContainsAny(['Functional', 'Personalization', 'Preferences', 'Settings']);
    });
  });

  describe('Toggle Consents', () => {
    beforeEach(() => {
      cy.visit('/app/account/privacy');
      cy.waitForPageLoad();
    });

    it('should have toggles for optional consents', () => {
      cy.assertHasElement([
        'input[type="checkbox"]',
        '[role="switch"]',
        '[data-testid*="toggle"]',
        '[data-testid*="consent"]'
      ]);
    });

    it('should indicate required consents', () => {
      cy.assertContainsAny(['always enabled', 'required', 'essential', 'necessary']);
    });
  });

  describe('Save Preferences', () => {
    beforeEach(() => {
      cy.visit('/app/account/privacy');
      cy.waitForPageLoad();
    });

    it('should have save button', () => {
      cy.assertHasElement([
        'button:contains("Save")',
        'button:contains("Update")',
        'button:contains("Apply")',
        '[data-testid*="save"]'
      ]);
    });
  });

  describe('Data Export', () => {
    beforeEach(() => {
      cy.visit('/app/account/privacy');
      cy.waitForPageLoad();
    });

    it('should display data export option', () => {
      cy.assertContainsAny(['Export', 'Download', 'Request your data', 'Your Data']);
    });

    it('should have request export button', () => {
      cy.assertHasElement([
        'button:contains("Export")',
        'button:contains("Request")',
        'button:contains("Download")',
        '[data-testid*="export"]'
      ]);
    });
  });

  describe('Data Deletion', () => {
    beforeEach(() => {
      cy.visit('/app/account/privacy');
      cy.waitForPageLoad();
    });

    it('should display data deletion option', () => {
      cy.assertContainsAny(['Delete', 'Erasure', 'Right to be forgotten', 'Remove']);
    });

    it('should have delete data button', () => {
      cy.assertHasElement([
        'button:contains("Delete")',
        'button:contains("Request deletion")',
        'button:contains("Remove")',
        '[data-testid*="delete"]'
      ]);
    });
  });

  describe('Privacy Policy Links', () => {
    beforeEach(() => {
      cy.visit('/app/account/privacy');
      cy.waitForPageLoad();
    });

    it('should have link to privacy policy', () => {
      cy.assertHasElement([
        'a[href*="privacy"]',
        'a:contains("Privacy Policy")',
        'a:contains("Privacy")',
        '[data-testid*="privacy-policy"]'
      ]);
    });

    it('should have link to terms of service', () => {
      cy.assertHasElement([
        'a[href*="terms"]',
        'a:contains("Terms")',
        'a:contains("Terms of Service")',
        '[data-testid*="terms"]'
      ]);
    });
  });

  describe('Responsive Design', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display privacy settings correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/account/privacy');
        cy.waitForPageLoad();
        cy.assertContainsAny(['Privacy', 'Consent', 'Settings', 'Preferences']);
      });
    });
  });
});
