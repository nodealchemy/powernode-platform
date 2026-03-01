/// <reference types="cypress" />

/**
 * BaaS Usage Metering Tests
 *
 * Tests for BaaS Usage Metering functionality including:
 * - Usage event tracking
 * - Meter configuration
 * - Usage aggregation
 * - Overage calculations
 * - Usage reports
 * - Billing integration
 */

describe('BaaS Usage Metering Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Usage Dashboard', () => {
    it('should navigate to usage dashboard', () => {
      cy.visit('/app/baas/usage');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Usage', 'Metering', 'Consumption']);
    });

    it('should display usage overview', () => {
      cy.visit('/app/baas/usage');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Overview']);
    });

    it('should display current period usage', () => {
      cy.visit('/app/baas/usage');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Current', 'This month', 'Period']);
    });
  });

  describe('Usage Meters', () => {
    it('should navigate to meters configuration', () => {
      cy.visit('/app/baas/usage/meters');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Meter', 'Metric', 'Event']);
    });

    it('should display meter list', () => {
      cy.visit('/app/baas/usage/meters');
      cy.waitForPageLoad();
      cy.assertHasElement(['table', '[data-testid="meters-list"]', '.list']);
    });

    it('should have create meter button', () => {
      cy.visit('/app/baas/usage/meters');
      cy.waitForPageLoad();
      cy.assertHasElement(['button:contains("Create")', 'button:contains("Add")', 'button:contains("New")']);
    });

    it('should display meter types', () => {
      cy.visit('/app/baas/usage/meters');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Sum', 'Count', 'Max', 'Unique']);
    });
  });

  describe('Usage Events', () => {
    it('should navigate to usage events', () => {
      cy.visit('/app/baas/usage/events');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Event', 'Activity', 'Log']);
    });

    it('should display event stream or list', () => {
      cy.visit('/app/baas/usage/events');
      cy.waitForPageLoad();
      cy.assertHasElement(['table', '[data-testid="events-list"]', '.stream']);
    });

    it('should have date range filter', () => {
      cy.visit('/app/baas/usage/events');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Date', 'From', 'To']);
    });

    it('should have event type filter', () => {
      cy.visit('/app/baas/usage/events');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Type', 'Filter']);
    });
  });

  describe('Usage Reports', () => {
    it('should navigate to usage reports', () => {
      cy.visit('/app/baas/usage/reports');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Report', 'Summary', 'Analysis']);
    });

    it('should display usage charts', () => {
      cy.visit('/app/baas/usage/reports');
      cy.waitForPageLoad();
      cy.assertHasElement(['canvas', 'svg', '[data-testid*="chart"]']);
    });

    it('should have export option', () => {
      cy.visit('/app/baas/usage/reports');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Export', 'CSV']);
    });
  });

  describe('Overage Management', () => {
    it('should display overage alerts', () => {
      cy.visit('/app/baas/usage');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Overage', 'Limit', 'Exceeded', 'Warning']);
    });

    it('should display usage thresholds', () => {
      cy.visit('/app/baas/usage');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Threshold', '%']);
    });
  });

  describe('Responsive Design', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display usage metering correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/baas/usage');
        cy.waitForPageLoad();

        cy.assertContainsAny(['Usage', 'Metering', 'BaaS']);
        cy.log(`Usage metering displayed correctly on ${name}`);
      });
    });
  });
});
