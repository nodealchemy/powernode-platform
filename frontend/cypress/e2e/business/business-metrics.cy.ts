/// <reference types="cypress" />

/**
 * Business Metrics Page Tests
 *
 * Tests for Business Metrics functionality including:
 * - Page navigation and load
 * - Revenue metrics display (MRR, ARR, ARPU, CLV)
 * - Growth metrics display
 * - Retention metrics display
 * - Responsive design
 */

describe('Business Metrics Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Page Navigation', () => {
    it('should navigate to Metrics page', () => {
      cy.assertPageReady('/app/metrics', 'Metrics');
    });

    it('should display page title and description', () => {
      cy.navigateTo('/app/metrics');
      cy.verifyPageTitle('Metrics');
      cy.assertContainsAny(['Key performance indicators', 'growth metrics', 'KPI', 'performance']);
    });

    it('should display breadcrumbs', () => {
      cy.navigateTo('/app/metrics');
      cy.assertContainsAny(['Dashboard', 'Metrics']);
    });
  });

  describe('Revenue Metrics Display', () => {
    beforeEach(() => {
      cy.navigateTo('/app/metrics');
    });

    it('should display core revenue metrics', () => {
      cy.assertContainsAny(['Monthly Recurring Revenue', 'MRR', 'Annual Recurring Revenue', 'ARR']);
    });

    it('should display per-user metrics', () => {
      cy.assertContainsAny(['Average Revenue Per User', 'ARPU', 'Customer Lifetime Value', 'CLV']);
    });

    it('should display currency values and growth percentages', () => {
      cy.assertContainsAny(['$', '%']);
    });
  });

  describe('KPI Section', () => {
    beforeEach(() => {
      cy.navigateTo('/app/metrics');
    });

    it('should display KPI sections', () => {
      cy.assertContainsAny(['Key Performance Indicators', 'Growth Metrics', 'Retention Metrics', 'Revenue']);
    });
  });

  describe('Growth Metrics', () => {
    beforeEach(() => {
      cy.navigateTo('/app/metrics');
    });

    it('should display growth metrics', () => {
      cy.assertContainsAny([
        'Customer Acquisition Rate',
        'Monthly Growth Rate',
        'Expansion Revenue',
        'Growth',
      ]);
    });
  });

  describe('Retention Metrics', () => {
    beforeEach(() => {
      cy.navigateTo('/app/metrics');
    });

    it('should display retention metrics', () => {
      cy.assertContainsAny([
        'Customer Retention Rate',
        'Churn Rate',
        'Net Revenue Retention',
        'Retention',
      ]);
    });
  });

  describe('Metric Cards Layout', () => {
    beforeEach(() => {
      cy.navigateTo('/app/metrics');
    });

    it('should display metrics in grid layout with cards', () => {
      // Check for grid layout or surface elements
      cy.get('body').then(($body) => {
        const hasGrid = $body.find('[class*="grid"]').length > 0;
        const hasRounded = $body.find('[class*="rounded-lg"]').length > 0;
        const hasSurface = $body.find('[class*="surface"]').length > 0;
        expect(hasGrid || hasRounded || hasSurface, 'Should have grid layout elements').to.be.true;
      });
    });

    it('should display metric values with proper styling', () => {
      // Check for styled metric text elements
      cy.get('body').then(($body) => {
        const hasLargeText = $body.find('[class*="text-3xl"], [class*="text-2xl"]').length > 0;
        const hasBold = $body.find('[class*="font-bold"], [class*="font-semibold"]').length > 0;
        expect(hasLargeText || hasBold, 'Should have styled metric values').to.be.true;
      });
    });
  });

  describe('Trend Indicators', () => {
    beforeEach(() => {
      cy.navigateTo('/app/metrics');
    });

    it('should display trend comparison text', () => {
      cy.assertContainsAny([
        'from last month',
        'YoY',
        'improvement',
        'increase',
        'decrease',
        '%',
      ]);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly across viewports', () => {
      cy.testResponsiveDesign('/app/metrics', {
        checkContent: 'Metrics',
      });
    });
  });
});

export {};
