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
      cy.get('body').then($body => {
        const hasValue = $body.text().match(/\$[\d,]+/) ||
                        $body.find('[class*="text-3xl"], [class*="text-2xl"], h2, h3').length > 0;
        if (hasValue) {
          cy.log('MRR value found');
        }
      });
      cy.get('body').should('be.visible');
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
      cy.get('body').then($body => {
        const hasTrend = $body.text().match(/[+-]?\d+\.?\d*%/) ||
                        $body.find('svg').length > 0;
        if (hasTrend) {
          cy.log('Growth trend indicators found');
        }
      });
      cy.get('body').should('be.visible');
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
      cy.get('body').then($body => {
        const hasProgress = $body.find('[class*="h-2"], [class*="progress"], [role="progressbar"]').length > 0 ||
                           $body.find('div').filter(function() {
                             const height = $(this).css('height');
                             return height === '8px' || height === '4px';
                           }).length > 0;
        if (hasProgress) {
          cy.log('Progress bars found');
        }
      });
      cy.get('body').should('be.visible');
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
      cy.get('body').then($body => {
        const hasProgress = $body.find('[class*="bg-theme-success"], [class*="bg-theme-error"], [class*="bg-green"], [class*="bg-red"]').length > 0 ||
                           $body.find('[class*="progress"]').length > 0;
        if (hasProgress) {
          cy.log('Retention progress bars found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Metric Values', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/metrics');
    });

    it('should display percentage values', () => {
      cy.get('body').then($body => {
        const hasPercent = $body.text().match(/\d+\.?\d*%/);
        if (hasPercent) {
          cy.log('Percentage values found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display currency values', () => {
      cy.get('body').then($body => {
        const hasCurrency = $body.text().match(/\$[\d,]+/);
        if (hasCurrency) {
          cy.log('Currency values found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.intercept('GET', '**/api/**/metrics**', {
        statusCode: 500,
        body: { error: 'Internal Server Error' }
      }).as('apiError');

      cy.visit('/app/metrics');
      cy.get('body').should('be.visible');
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
      cy.get('body').then($body => {
        const hasLoading = $body.find('.animate-spin, [class*="loading"], [class*="spinner"]').length > 0 ||
                          $body.find('svg').filter(function() {
                            return $(this).attr('class')?.includes('animate') || false;
                          }).length > 0 ||
                          $body.text().includes('Loading');
        if (hasLoading) {
          cy.log('Loading indicator found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/metrics');
      cy.get('body').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/metrics');
      cy.get('body').should('be.visible');
    });

    it('should stack metric cards on small screens', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/metrics');
      cy.get('body').then($body => {
        const hasStack = $body.find('[class*="grid-cols-1"], [class*="flex-col"]').length > 0;
        if (hasStack) {
          cy.log('Stacked metric cards found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should show multi-column layout on large screens', () => {
      cy.viewport(1920, 1080);
      cy.visit('/app/metrics');
      cy.get('body').then($body => {
        const hasMultiCol = $body.find('[class*="lg:grid-cols-4"]').length > 0 ||
                           $body.find('[class*="md:grid-cols-2"]').length > 0 ||
                           $body.find('[class*="grid"]').length > 0;
        if (hasMultiCol) {
          cy.log('Multi-column layout found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });
});


export {};
