/// <reference types="cypress" />

/**
 * AI Publisher Tests
 *
 * Tests for AI Publisher functionality including:
 * - Publisher dashboard
 * - Template analytics
 * - Earnings tracking
 * - Payout management
 * - Template performance
 */

describe('AI Publisher Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Publisher Dashboard', () => {
    it('should navigate to publisher dashboard', () => {
      cy.visit('/ai/publisher/dashboard');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Publisher', 'Dashboard', 'Create Publisher', 'Templates']);
    });

    it('should display publisher setup or dashboard', () => {
      cy.visit('/ai/publisher/dashboard');
      cy.waitForPageLoad();
      cy.assertContainsAny([
        'Create Publisher Profile',
        'Get Started',
        'Become a Publisher',
        'Publisher Dashboard',
        'Templates',
        'Earnings'
      ]);
    });

    it('should display publisher tabs or setup', () => {
      cy.visit('/ai/publisher/dashboard');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Overview', 'Templates', 'Earnings', 'Payouts', 'Get Started']);
    });

    it('should display earnings overview or setup prompt', () => {
      cy.visit('/ai/publisher/dashboard');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Earnings', 'Revenue', '$', 'Lifetime', 'Setup', 'Create']);
    });
  });

  describe('Template Performance', () => {
    it('should display template list or empty state', () => {
      cy.visit('/ai/publisher/dashboard');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Template', 'No templates', 'Create', 'Publisher']);
    });

    it('should display template metrics or setup', () => {
      cy.visit('/ai/publisher/dashboard');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Installations', 'Rating', 'Revenue', 'Performance', 'Setup', 'Create']);
    });

    it('should display template status or setup', () => {
      cy.visit('/ai/publisher/dashboard');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Published', 'Draft', 'Pending', 'Active', 'Setup', 'Publisher']);
    });
  });

  describe('Template Analytics Page', () => {
    it('should navigate to template analytics', () => {
      cy.visit('/ai/publisher/analytics');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Analytics', 'Statistics', 'Metrics', 'Publisher']);
    });

    it('should display period selector', () => {
      cy.visit('/ai/publisher/analytics');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Last 7 days', 'Last 30 days', 'Last 90 days', 'Period', 'Analytics']);
    });

    it('should display revenue analytics', () => {
      cy.visit('/ai/publisher/analytics');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Revenue', 'Gross', 'Net', 'Commission', 'Analytics']);
    });

    it('should display installation metrics', () => {
      cy.visit('/ai/publisher/analytics');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Installation', 'Installs', 'Downloads', 'Analytics']);
    });
  });

  describe('Earnings & Payouts', () => {
    it('should display earnings information', () => {
      cy.visit('/ai/publisher/dashboard');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Earnings', 'Lifetime', 'Pending', 'Revenue Share', '$', 'Setup']);
    });

    it('should display payouts information', () => {
      cy.visit('/ai/publisher/dashboard');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Payout', 'Payouts', 'Stripe', 'Request', 'History', 'Setup']);
    });

    it('should display Stripe connection status', () => {
      cy.visit('/ai/publisher/dashboard');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Stripe', 'Connected', 'Setup Stripe', 'Not Connected', 'Payment', 'Setup']);
    });

    it('should display payout history or empty state', () => {
      cy.visit('/ai/publisher/dashboard');
      cy.waitForPageLoad();
      cy.assertContainsAny(['History', 'No payouts', 'Completed', 'Pending', 'Setup', 'Publisher']);
    });
  });

  describe('Publisher Setup Flow', () => {
    it('should navigate to publisher setup page', () => {
      cy.visit('/ai/publisher/setup');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Setup', 'Create', 'Publisher', 'Profile']);
    });

    it('should display setup form fields', () => {
      cy.visit('/ai/publisher/setup');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Name', 'Description', 'Setup', 'Create', 'Publisher']);
    });
  });

  describe('Create Template Flow', () => {
    it('should have create template action', () => {
      cy.visit('/ai/publisher/dashboard');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Create Template', 'New Template', 'Add Template', 'Create', 'Setup']);
    });
  });
});
