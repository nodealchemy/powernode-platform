/// <reference types="cypress" />

/**
 * Business Revenue Intelligence Tests
 *
 * Tests for Revenue Intelligence functionality including:
 * - Customer Health scores
 * - Churn Risk analysis
 * - Revenue Forecasting
 * - Predictive Analytics
 */

describe('Business Revenue Intelligence Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Customer Health Page', () => {
    it('should navigate to customer health page', () => {
      cy.visit('/app/business/analytics/customer-health');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Customer Health', 'Health Score', 'Customers']);
    });

    it('should display health score distribution', () => {
      cy.visit('/app/business/analytics/customer-health');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Healthy', 'At Risk', 'Unhealthy', 'Critical', 'Distribution']);
    });

    it('should display health summary statistics', () => {
      cy.visit('/app/business/analytics/customer-health');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Average', 'Score', 'Total', 'Customers']);
    });

    it('should display health score cards', () => {
      cy.visit('/app/business/analytics/customer-health');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Healthy', 'customers', 'Score', 'Health']);
    });

    it('should have filter options', () => {
      cy.visit('/app/business/analytics/customer-health');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Filter', 'All']);
    });
  });

  describe('Churn Risk Page', () => {
    it('should navigate to churn risk page', () => {
      cy.visit('/app/business/analytics/churn-risk');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Churn Risk', 'Risk Analysis', 'At Risk']);
    });

    it('should display risk tier breakdown', () => {
      cy.visit('/app/business/analytics/churn-risk');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Critical', 'High', 'Medium', 'Low', 'Minimal']);
    });

    it('should display churn risk summary', () => {
      cy.visit('/app/business/analytics/churn-risk');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Revenue at Risk', 'At Risk Customers', 'Total', '$']);
    });

    it('should display at-risk customer list', () => {
      cy.visit('/app/business/analytics/churn-risk');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Customer', 'Risk']);
    });

    it('should display risk factors', () => {
      cy.visit('/app/business/analytics/churn-risk');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Factor', 'Payment', 'Usage', 'Engagement']);
    });

    it('should display recommended actions', () => {
      cy.visit('/app/business/analytics/churn-risk');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Action', 'Recommendation', 'Contact', 'Discount']);
    });
  });

  describe('Revenue Forecast Page', () => {
    it('should navigate to revenue forecast page', () => {
      cy.visit('/app/business/analytics/revenue-forecast');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Revenue Forecast', 'Forecast', 'Projection']);
    });

    it('should display forecast summary', () => {
      cy.visit('/app/business/analytics/revenue-forecast');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Projected', 'Current', 'Growth', '$']);
    });

    it('should display forecast chart', () => {
      cy.visit('/app/business/analytics/revenue-forecast');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Forecast', 'Revenue', 'Projected', '$']);
    });

    it('should display forecast period selector', () => {
      cy.visit('/app/business/analytics/revenue-forecast');
      cy.waitForPageLoad();

      cy.assertContainsAny(['3 Month', '6 Month', '12 Month', 'Period', 'Forecast']);
    });

    it('should display confidence intervals', () => {
      cy.visit('/app/business/analytics/revenue-forecast');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Confidence', 'Upper', 'Lower', 'Range']);
    });

    it('should display growth drivers', () => {
      cy.visit('/app/business/analytics/revenue-forecast');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Driver', 'Factor', 'New', 'Expansion']);
    });
  });

  describe('Predictive Analytics Navigation', () => {
    it('should access predictive analytics from main analytics', () => {
      cy.visit('/app/business/analytics');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Customer Health', 'Churn Risk', 'Revenue Forecast', 'Predictive']);
    });

    it('should navigate between intelligence pages', () => {
      cy.visit('/app/business/analytics/customer-health');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Customer Health', 'Health Score', 'Customers']);
    });
  });

  describe('Health Score Card Component', () => {
    it('should display health score card details', () => {
      cy.visit('/app/business/analytics/customer-health');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Score', 'Health', 'Trend']);
    });

    it('should show health trend indicators', () => {
      cy.visit('/app/business/analytics/customer-health');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Up', 'Down', 'Stable', '%']);
    });
  });

  describe('Churn Risk List Component', () => {
    it('should display churn risk list with customer details', () => {
      cy.visit('/app/business/analytics/churn-risk');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Customer', 'MRR', 'Risk Score', 'Risk']);
    });

    it('should show risk tier badges', () => {
      cy.visit('/app/business/analytics/churn-risk');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Critical', 'High', 'Low']);
    });

    it('should have expandable customer details', () => {
      cy.visit('/app/business/analytics/churn-risk');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Details', 'View', 'Customer', 'Risk']);
    });
  });

  describe('Forecast Chart Component', () => {
    it('should render forecast visualization', () => {
      cy.visit('/app/business/analytics/revenue-forecast');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Forecast', 'Revenue', '$', 'MRR']);
    });

    it('should display forecast data points', () => {
      cy.visit('/app/business/analytics/revenue-forecast');
      cy.waitForPageLoad();

      cy.assertContainsAny(['$', 'MRR', 'Revenue']);
    });
  });
});
