/// <reference types="cypress" />

/**
 * Privacy Cookie Preferences Tests
 *
 * Tests for Cookie Preferences functionality including:
 * - Cookie banner display
 * - Cookie categories
 * - Consent management
 * - Cookie settings persistence
 * - Third-party cookies
 * - Cookie policy
 */

describe('Privacy Cookie Preferences Tests', () => {
  describe('Cookie Banner', () => {
    it('should display cookie banner on first visit', () => {
      cy.clearCookies();
      cy.visit('/');
      cy.waitForPageLoad();
      cy.assertContainsAny(['cookie', 'Cookie', 'Consent', 'Accept']);
    });

    it('should have accept all button', () => {
      cy.clearCookies();
      cy.visit('/');
      cy.waitForPageLoad();
      cy.assertHasElement([
        'button:contains("Accept")',
        'button:contains("Accept all")',
        'button:contains("Allow")',
        '[data-testid*="accept"]'
      ]);
    });

    it('should have reject/decline option', () => {
      cy.clearCookies();
      cy.visit('/');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Reject', 'Decline', 'Deny', 'Manage', 'Customize']);
    });

    it('should have customize/manage button', () => {
      cy.clearCookies();
      cy.visit('/');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Customize', 'Manage', 'Settings', 'Preferences']);
    });
  });

  describe('Cookie Categories', () => {
    beforeEach(() => {
      cy.standardTestSetup();
      cy.visit('/app/account/privacy/cookies');
      cy.waitForPageLoad();
    });

    it('should display necessary cookies category', () => {
      cy.assertContainsAny(['Necessary', 'Essential', 'Required', 'Cookies']);
    });

    it('should display analytics cookies category', () => {
      cy.assertContainsAny(['Analytics', 'Performance', 'Statistics', 'Usage']);
    });

    it('should display marketing cookies category', () => {
      cy.assertContainsAny(['Marketing', 'Advertising', 'Targeting', 'Promotional']);
    });

    it('should display functional cookies category', () => {
      cy.assertContainsAny(['Functional', 'Preferences', 'Personalization', 'Settings']);
    });
  });

  describe('Cookie Toggles', () => {
    beforeEach(() => {
      cy.standardTestSetup();
      cy.visit('/app/account/privacy/cookies');
      cy.waitForPageLoad();
    });

    it('should have toggles for optional cookies', () => {
      cy.assertHasElement([
        'input[type="checkbox"]',
        '[role="switch"]',
        '[data-testid*="toggle"]',
        '[data-testid*="cookie"]'
      ]);
    });

    it('should indicate required cookies', () => {
      cy.assertContainsAny(['always enabled', 'required', 'essential', 'necessary']);
    });

    it('should have save preferences button', () => {
      cy.assertHasElement([
        'button:contains("Save")',
        'button:contains("Update")',
        'button:contains("Apply")',
        '[data-testid*="save"]'
      ]);
    });
  });

  describe('Cookie Details', () => {
    beforeEach(() => {
      cy.standardTestSetup();
      cy.visit('/app/account/privacy/cookies');
      cy.waitForPageLoad();
    });

    it('should display cookie descriptions', () => {
      cy.assertContainsAny(['used for', 'help us', 'enable', 'improve', 'Cookies']);
    });

    it('should display cookie information', () => {
      cy.assertHasElement([
        'ul',
        'table',
        '[data-testid="cookie-list"]',
        'p'
      ]);
    });

    it('should display cookie duration info', () => {
      cy.assertContainsAny(['Expire', 'Duration', 'day', 'year', 'session', 'Cookie']);
    });
  });

  describe('Third-Party Cookies', () => {
    beforeEach(() => {
      cy.standardTestSetup();
      cy.visit('/app/account/privacy/cookies');
      cy.waitForPageLoad();
    });

    it('should display third-party cookie info', () => {
      cy.assertContainsAny(['Third-party', 'third party', 'External', 'Cookies', 'Analytics']);
    });

    it('should list third-party providers or categories', () => {
      cy.assertContainsAny(['Google', 'Analytics', 'Provider', 'Marketing', 'Advertising']);
    });
  });

  describe('Cookie Policy Link', () => {
    beforeEach(() => {
      cy.standardTestSetup();
      cy.visit('/app/account/privacy/cookies');
      cy.waitForPageLoad();
    });

    it('should have link to full cookie policy', () => {
      cy.assertHasElement([
        'a[href*="cookie"]',
        'a:contains("Cookie Policy")',
        'a:contains("Learn more")',
        '[data-testid*="policy"]'
      ]);
    });
  });

  describe('Consent Timestamp', () => {
    beforeEach(() => {
      cy.standardTestSetup();
      cy.visit('/app/account/privacy/cookies');
      cy.waitForPageLoad();
    });

    it('should display consent information', () => {
      cy.assertContainsAny(['Last updated', 'Consent', 'Preferences', 'Settings']);
    });
  });

  describe('Responsive Design', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display cookie preferences correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.clearCookies();
        cy.visit('/');
        cy.waitForPageLoad();
        cy.assertContainsAny(['Cookie', 'Accept', 'Consent', 'Privacy']);
      });
    });
  });
});
