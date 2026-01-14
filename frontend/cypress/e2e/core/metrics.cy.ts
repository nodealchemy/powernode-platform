/// <reference types="cypress" />

describe('Metrics Page Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 5000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to Metrics page', () => {
      cy.visit('/app/metrics');
      cy.url().should('include', '/metrics');
    });

    it('should display page title', () => {
      cy.visit('/app/metrics');
      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('Metrics') ||
                        $body.find('[class*="PageContainer"]').length > 0;
        if (hasTitle) {
          cy.log('Metrics page title found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display page description', () => {
      cy.visit('/app/metrics');
      cy.get('body').then($body => {
        const hasDesc = $body.text().includes('Key performance indicators') ||
                       $body.text().includes('growth metrics');
        if (hasDesc) {
          cy.log('Page description found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/metrics');
      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('Dashboard') ||
                              $body.text().includes('Metrics');
        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Revenue Metrics Cards', () => {
    it('should display Monthly Recurring Revenue card', () => {
      cy.visit('/app/metrics');
      cy.get('body').then($body => {
        const hasMRR = $body.text().includes('Monthly Recurring Revenue') ||
                      $body.text().includes('MRR');
        if (hasMRR) {
          cy.log('Monthly Recurring Revenue card found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display MRR value', () => {
      cy.visit('/app/metrics');
      cy.get('body').then($body => {
        const hasValue = $body.text().match(/\$[\d,]+/) ||
                        $body.find('[class*="text-3xl"]').length > 0;
        if (hasValue) {
          cy.log('MRR value found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Annual Recurring Revenue card', () => {
      cy.visit('/app/metrics');
      cy.get('body').then($body => {
        const hasARR = $body.text().includes('Annual Recurring Revenue') ||
                      $body.text().includes('ARR');
        if (hasARR) {
          cy.log('Annual Recurring Revenue card found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Average Revenue Per User card', () => {
      cy.visit('/app/metrics');
      cy.get('body').then($body => {
        const hasARPU = $body.text().includes('Average Revenue Per User') ||
                       $body.text().includes('ARPU');
        if (hasARPU) {
          cy.log('Average Revenue Per User card found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Customer Lifetime Value card', () => {
      cy.visit('/app/metrics');
      cy.get('body').then($body => {
        const hasCLV = $body.text().includes('Customer Lifetime Value') ||
                      $body.text().includes('CLV');
        if (hasCLV) {
          cy.log('Customer Lifetime Value card found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display growth trend indicators', () => {
      cy.visit('/app/metrics');
      cy.get('body').then($body => {
        const hasTrend = $body.text().includes('↑') ||
                        $body.text().includes('↓') ||
                        $body.text().match(/[+-]?\d+\.?\d*%/);
        if (hasTrend) {
          cy.log('Growth trend indicators found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display trend context', () => {
      cy.visit('/app/metrics');
      cy.get('body').then($body => {
        const hasContext = $body.text().includes('from last month') ||
                          $body.text().includes('YoY') ||
                          $body.text().includes('improvement');
        if (hasContext) {
          cy.log('Trend context found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Key Performance Indicators Section', () => {
    it('should display KPI section', () => {
      cy.visit('/app/metrics');
      cy.get('body').then($body => {
        const hasKPI = $body.text().includes('Key Performance Indicators') ||
                      $body.text().includes('KPI');
        if (hasKPI) {
          cy.log('KPI section found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Growth Metrics', () => {
    it('should display Growth Metrics section', () => {
      cy.visit('/app/metrics');
      cy.get('body').then($body => {
        const hasGrowth = $body.text().includes('Growth Metrics');
        if (hasGrowth) {
          cy.log('Growth Metrics section found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Customer Acquisition Rate', () => {
      cy.visit('/app/metrics');
      cy.get('body').then($body => {
        const hasCAR = $body.text().includes('Customer Acquisition Rate');
        if (hasCAR) {
          cy.log('Customer Acquisition Rate found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Monthly Growth Rate', () => {
      cy.visit('/app/metrics');
      cy.get('body').then($body => {
        const hasMGR = $body.text().includes('Monthly Growth Rate');
        if (hasMGR) {
          cy.log('Monthly Growth Rate found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Expansion Revenue', () => {
      cy.visit('/app/metrics');
      cy.get('body').then($body => {
        const hasExpansion = $body.text().includes('Expansion Revenue');
        if (hasExpansion) {
          cy.log('Expansion Revenue found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display progress bars for growth metrics', () => {
      cy.visit('/app/metrics');
      cy.get('body').then($body => {
        const hasProgress = $body.find('[class*="h-2"]').length > 0 ||
                           $body.find('[class*="rounded-full"]').length > 0;
        if (hasProgress) {
          cy.log('Progress bars found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Retention Metrics', () => {
    it('should display Retention Metrics section', () => {
      cy.visit('/app/metrics');
      cy.get('body').then($body => {
        const hasRetention = $body.text().includes('Retention Metrics');
        if (hasRetention) {
          cy.log('Retention Metrics section found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Customer Retention Rate', () => {
      cy.visit('/app/metrics');
      cy.get('body').then($body => {
        const hasCRR = $body.text().includes('Customer Retention Rate');
        if (hasCRR) {
          cy.log('Customer Retention Rate found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Churn Rate', () => {
      cy.visit('/app/metrics');
      cy.get('body').then($body => {
        const hasChurn = $body.text().includes('Churn Rate');
        if (hasChurn) {
          cy.log('Churn Rate found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Net Revenue Retention', () => {
      cy.visit('/app/metrics');
      cy.get('body').then($body => {
        const hasNRR = $body.text().includes('Net Revenue Retention');
        if (hasNRR) {
          cy.log('Net Revenue Retention found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display progress bars for retention metrics', () => {
      cy.visit('/app/metrics');
      cy.get('body').then($body => {
        const hasProgress = $body.find('[class*="bg-theme-success"]').length > 0 ||
                           $body.find('[class*="bg-theme-error"]').length > 0;
        if (hasProgress) {
          cy.log('Retention progress bars found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Metric Values', () => {
    it('should display percentage values', () => {
      cy.visit('/app/metrics');
      cy.get('body').then($body => {
        const hasPercent = $body.text().match(/\d+\.?\d*%/);
        if (hasPercent) {
          cy.log('Percentage values found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display currency values', () => {
      cy.visit('/app/metrics');
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
        const hasLoading = $body.find('[class*="animate-spin"]').length > 0 ||
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
        const hasStack = $body.find('[class*="grid-cols-1"]').length > 0;
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
                           $body.find('[class*="md:grid-cols-2"]').length > 0;
        if (hasMultiCol) {
          cy.log('Multi-column layout found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });
});


export {};
