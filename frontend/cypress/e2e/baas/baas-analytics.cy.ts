/// <reference types="cypress" />

/**
 * BaaS Analytics Tests
 *
 * Tests for BaaS Analytics functionality including:
 * - Analytics dashboard
 * - Tenant metrics
 * - Revenue analytics
 * - Usage statistics
 * - Performance metrics
 * - Custom reports
 */

describe('BaaS Analytics Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Analytics Dashboard', () => {
    it('should navigate to BaaS analytics', () => {
      cy.visit('/app/baas/analytics');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Analytics', 'Dashboard', 'Metrics']);
    });

    it('should display overview metrics', () => {
      cy.visit('/app/baas/analytics');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Total', 'Revenue', 'Tenants']);
    });

    it('should display time range selector', () => {
      cy.visit('/app/baas/analytics');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Today', 'Week', 'Month', 'Custom']);
    });

    it('should display trend charts', () => {
      cy.visit('/app/baas/analytics');
      cy.waitForPageLoad();
      cy.assertHasElement(['canvas', 'svg', '[data-testid="analytics-chart"]']);
    });
  });

  describe('Tenant Metrics', () => {
    beforeEach(() => {
      cy.visit('/app/baas/analytics/tenants');
      cy.waitForPageLoad();
    });

    it('should display tenant count', () => {
      cy.assertContainsAny(['Tenant']);
    });

    it('should display active vs inactive tenants', () => {
      cy.assertContainsAny(['Active', 'Inactive', 'Status']);
    });

    it('should display tenant growth chart', () => {
      cy.assertContainsAny(['Growth']);
    });

    it('should display churn rate', () => {
      cy.assertContainsAny(['Churn', 'Retention', '%']);
    });

    it('should display top tenants by usage', () => {
      cy.assertContainsAny(['Top', 'Usage']);
    });
  });

  describe('Revenue Analytics', () => {
    beforeEach(() => {
      cy.visit('/app/baas/analytics/revenue');
      cy.waitForPageLoad();
    });

    it('should display MRR', () => {
      cy.assertContainsAny(['MRR', 'Monthly', 'Revenue']);
    });

    it('should display ARR', () => {
      cy.assertContainsAny(['ARR', 'Annual']);
    });

    it('should display revenue breakdown', () => {
      cy.assertContainsAny(['Breakdown', 'By plan', 'By tier']);
    });

    it('should display expansion revenue', () => {
      cy.assertContainsAny(['Expansion', 'Upgrade', 'Upsell']);
    });

    it('should display ARPU', () => {
      cy.assertContainsAny(['ARPU', 'Average revenue per']);
    });
  });

  describe('Usage Statistics', () => {
    beforeEach(() => {
      cy.visit('/app/baas/analytics/usage');
      cy.waitForPageLoad();
    });

    it('should display API call volume', () => {
      cy.assertContainsAny(['API', 'Calls', 'Requests']);
    });

    it('should display storage usage', () => {
      cy.assertContainsAny(['Storage', 'GB', 'MB']);
    });

    it('should display bandwidth usage', () => {
      cy.assertContainsAny(['Bandwidth', 'Transfer', 'Data']);
    });

    it('should display usage by tenant', () => {
      cy.assertContainsAny(['By tenant', 'Tenant']);
    });
  });

  describe('Performance Metrics', () => {
    beforeEach(() => {
      cy.visit('/app/baas/analytics/performance');
      cy.waitForPageLoad();
    });

    it('should display API latency', () => {
      cy.assertContainsAny(['Latency', 'Response time', 'ms']);
    });

    it('should display error rates', () => {
      cy.assertContainsAny(['Error', '4xx', '5xx']);
    });

    it('should display uptime', () => {
      cy.assertContainsAny(['Uptime', '99.', 'Availability']);
    });

    it('should display request success rate', () => {
      cy.assertContainsAny(['Success', '2xx', '%']);
    });
  });

  describe('Custom Reports', () => {
    it('should navigate to custom reports', () => {
      cy.visit('/app/baas/analytics/reports');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Report', 'Custom', 'Create']);
    });

    it('should have create report button', () => {
      cy.visit('/app/baas/analytics/reports');
      cy.waitForPageLoad();
      cy.assertHasElement(['button:contains("Create")', 'button:contains("New")']);
    });

    it('should display saved reports', () => {
      cy.visit('/app/baas/analytics/reports');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Saved']);
    });

    it('should have export report option', () => {
      cy.visit('/app/baas/analytics/reports');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Export']);
    });

    it('should have schedule report option', () => {
      cy.visit('/app/baas/analytics/reports');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Schedule']);
    });
  });

  describe('Comparison Tools', () => {
    beforeEach(() => {
      cy.visit('/app/baas/analytics');
      cy.waitForPageLoad();
    });

    it('should have period comparison', () => {
      cy.assertContainsAny(['Compare', 'vs', 'Previous']);
    });

    it('should display percentage changes', () => {
      cy.assertContainsAny(['%', 'increase', 'decrease']);
    });

    it('should have benchmark comparison', () => {
      cy.assertContainsAny(['Benchmark', 'Industry', 'Average']);
    });
  });

  describe('Responsive Design', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display BaaS analytics correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/baas/analytics');
        cy.waitForPageLoad();

        cy.assertContainsAny(['BaaS', 'Analytics', 'Dashboard']);
        cy.log(`BaaS analytics displayed correctly on ${name}`);
      });
    });
  });
});
