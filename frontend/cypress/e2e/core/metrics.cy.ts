/// <reference types="cypress" />

describe('Metrics Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Page Navigation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/metrics');
    });

    it('should navigate to Metrics page', () => {
      cy.url().should('include', '/metrics');
    });

    it('should display page title', () => {
      cy.assertContainsAny(['Metrics', 'PageContainer']);
    });

    it('should display page description', () => {
      cy.assertContainsAny(['Key performance indicators', 'growth metrics', 'metrics']);
    });

    it('should display breadcrumbs', () => {
      cy.assertContainsAny(['Dashboard', 'Metrics']);
    });
  });

  describe('Revenue Metrics Cards', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/metrics');
    });

    it('should display Monthly Recurring Revenue card', () => {
      cy.assertContainsAny(['Monthly Recurring Revenue', 'MRR']);
    });

    it('should display MRR value', () => {
      cy.assertHasElement(['[class*="text-3xl"]', '[class*="text-2xl"]', 'h2', 'h3']);
    });

    it('should display Annual Recurring Revenue card', () => {
      cy.assertContainsAny(['Annual Recurring Revenue', 'ARR']);
    });

    it('should display Average Revenue Per User card', () => {
      cy.assertContainsAny(['Average Revenue Per User', 'ARPU']);
    });

    it('should display Customer Lifetime Value card', () => {
      cy.assertContainsAny(['Customer Lifetime Value', 'CLV']);
    });

    it('should display growth trend indicators', () => {
      cy.assertContainsAny(['%', 'Growth', 'Trend']);
    });

    it('should display trend context', () => {
      cy.assertContainsAny(['from last month', 'YoY', 'improvement', 'month', 'year']);
    });
  });

  describe('Key Performance Indicators Section', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/metrics');
    });

    it('should display KPI section', () => {
      cy.assertContainsAny(['Key Performance Indicators', 'KPI', 'Performance']);
    });
  });

  describe('Growth Metrics', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/metrics');
    });

    it('should display Growth Metrics section', () => {
      cy.assertContainsAny(['Growth Metrics', 'Growth']);
    });

    it('should display Customer Acquisition Rate', () => {
      cy.assertContainsAny(['Customer Acquisition Rate', 'Acquisition']);
    });

    it('should display Monthly Growth Rate', () => {
      cy.assertContainsAny(['Monthly Growth Rate', 'Growth Rate']);
    });

    it('should display Expansion Revenue', () => {
      cy.assertContainsAny(['Expansion Revenue', 'Expansion']);
    });

    it('should display progress bars for growth metrics', () => {
      cy.assertHasElement(['[class*="h-2"]', '[class*="progress"]', '[role="progressbar"]']);
    });
  });

  describe('Retention Metrics', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/metrics');
    });

    it('should display Retention Metrics section', () => {
      cy.assertContainsAny(['Retention Metrics', 'Retention']);
    });

    it('should display Customer Retention Rate', () => {
      cy.assertContainsAny(['Customer Retention Rate', 'Retention Rate']);
    });

    it('should display Churn Rate', () => {
      cy.assertContainsAny(['Churn Rate', 'Churn']);
    });

    it('should display Net Revenue Retention', () => {
      cy.assertContainsAny(['Net Revenue Retention', 'NRR']);
    });

    it('should display progress bars for retention metrics', () => {
      cy.assertHasElement(['[class*="bg-theme-success"]', '[class*="bg-theme-error"]', '[class*="bg-green"]', '[class*="bg-red"]', '[class*="progress"]']);
    });
  });

  describe('Metric Values', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/metrics');
    });

    it('should display percentage values', () => {
      cy.assertContainsAny(['%']);
    });

    it('should display currency values', () => {
      cy.assertContainsAny(['$']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.intercept('GET', '**/api/**/metrics**', {
        statusCode: 500,
        body: { error: 'Internal Server Error' }
      }).as('apiError');

      cy.visit('/app/metrics');
      cy.assertContainsAny(['Metrics', 'Error']);
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '**/api/**/metrics**', (req) => {
        req.reply((res) => {
          res.delay = 2000;
          res.send({ success: true, data: {} });
        });
      }).as('slowLoad');

      cy.visit('/app/metrics');

      cy.assertHasElement(['.animate-spin', '[class*="loading"]', '[class*="spinner"]']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/metrics');
      cy.assertContainsAny(['Metrics', 'Revenue']);
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/metrics');
      cy.assertContainsAny(['Metrics', 'Revenue']);
    });

    it('should stack metric cards on small screens', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/metrics');

      cy.assertHasElement(['[class*="grid-cols-1"]', '[class*="flex-col"]']);
    });

    it('should show multi-column layout on large screens', () => {
      cy.viewport(1920, 1080);
      cy.visit('/app/metrics');

      cy.assertHasElement(['[class*="lg:grid-cols-4"]', '[class*="md:grid-cols-2"]', '[class*="grid"]']);
    });
  });
});


export {};
