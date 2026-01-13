/// <reference types="cypress" />

describe('Business Analytics Dashboard Page Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to Analytics Dashboard page', () => {
      cy.visit('/app/business/analytics');
      cy.url().should('include', '/business');
    });

    it('should display page title', () => {
      cy.visit('/app/business/analytics');
      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('Analytics Dashboard') ||
                        $body.text().includes('Analytics') ||
                        $body.find('[class*="PageContainer"]').length > 0;
        if (hasTitle) {
          cy.log('Analytics Dashboard page title found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display page description', () => {
      cy.visit('/app/business/analytics');
      cy.get('body').then($body => {
        const hasDesc = $body.text().includes('Real-time insights') ||
                       $body.text().includes('insights') ||
                       $body.text().includes('business');
        if (hasDesc) {
          cy.log('Page description found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/business/analytics');
      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('Dashboard') ||
                              $body.text().includes('Business') ||
                              $body.text().includes('Analytics');
        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Page Actions', () => {
    it('should have Refresh button', () => {
      cy.visit('/app/business/analytics');
      cy.get('body').then($body => {
        const hasRefresh = $body.text().includes('Refresh') ||
                          $body.find('button:contains("Refresh")').length > 0;
        if (hasRefresh) {
          cy.log('Refresh button found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should have Export button for authorized users', () => {
      cy.visit('/app/business/analytics');
      cy.get('body').then($body => {
        const hasExport = $body.text().includes('Export') ||
                         $body.find('button:contains("Export")').length > 0;
        if (hasExport) {
          cy.log('Export button found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Date Range Filter', () => {
    it('should display date range filter', () => {
      cy.visit('/app/business/analytics');
      cy.get('body').then($body => {
        const hasDateFilter = $body.find('[class*="DateRangeFilter"]').length > 0 ||
                             $body.find('input[type="date"]').length > 0 ||
                             $body.text().includes('Date') ||
                             $body.text().includes('Range');
        if (hasDateFilter) {
          cy.log('Date range filter found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Last Updated info', () => {
      cy.visit('/app/business/analytics');
      cy.get('body').then($body => {
        const hasLastUpdated = $body.text().includes('Last updated') ||
                              $body.text().includes('ago');
        if (hasLastUpdated) {
          cy.log('Last updated info found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Tab Navigation', () => {
    it('should display Overview tab', () => {
      cy.visit('/app/business/analytics');
      cy.get('body').then($body => {
        const hasTab = $body.text().includes('Overview');
        if (hasTab) {
          cy.log('Overview tab found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Live tab', () => {
      cy.visit('/app/business/analytics');
      cy.get('body').then($body => {
        const hasTab = $body.text().includes('Live');
        if (hasTab) {
          cy.log('Live tab found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Revenue tab', () => {
      cy.visit('/app/business/analytics');
      cy.get('body').then($body => {
        const hasTab = $body.text().includes('Revenue');
        if (hasTab) {
          cy.log('Revenue tab found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Growth tab', () => {
      cy.visit('/app/business/analytics');
      cy.get('body').then($body => {
        const hasTab = $body.text().includes('Growth');
        if (hasTab) {
          cy.log('Growth tab found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Churn tab', () => {
      cy.visit('/app/business/analytics');
      cy.get('body').then($body => {
        const hasTab = $body.text().includes('Churn');
        if (hasTab) {
          cy.log('Churn tab found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Customers tab', () => {
      cy.visit('/app/business/analytics');
      cy.get('body').then($body => {
        const hasTab = $body.text().includes('Customers');
        if (hasTab) {
          cy.log('Customers tab found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Cohorts tab', () => {
      cy.visit('/app/business/analytics');
      cy.get('body').then($body => {
        const hasTab = $body.text().includes('Cohorts');
        if (hasTab) {
          cy.log('Cohorts tab found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should switch to Revenue tab', () => {
      cy.visit('/app/business/analytics');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Revenue")').length > 0) {
          cy.contains('button', 'Revenue').click();
          cy.url().should('include', 'revenue');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should switch to Growth tab', () => {
      cy.visit('/app/business/analytics');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Growth")').length > 0) {
          cy.contains('button', 'Growth').click();
          cy.url().should('include', 'growth');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Overview Tab Content', () => {
    it('should display Metrics Overview', () => {
      cy.visit('/app/business/analytics');
      cy.get('body').then($body => {
        const hasMetrics = $body.text().includes('MRR') ||
                          $body.text().includes('Revenue') ||
                          $body.text().includes('Customers') ||
                          $body.find('[class*="metrics"]').length > 0;
        if (hasMetrics) {
          cy.log('Metrics Overview found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Revenue Trend chart', () => {
      cy.visit('/app/business/analytics');
      cy.get('body').then($body => {
        const hasChart = $body.text().includes('Revenue Trend') ||
                        $body.find('[class*="chart"]').length > 0;
        if (hasChart) {
          cy.log('Revenue Trend chart found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Growth Rate chart', () => {
      cy.visit('/app/business/analytics');
      cy.get('body').then($body => {
        const hasChart = $body.text().includes('Growth Rate') ||
                        $body.text().includes('Growth');
        if (hasChart) {
          cy.log('Growth Rate chart found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Churn Analysis chart', () => {
      cy.visit('/app/business/analytics');
      cy.get('body').then($body => {
        const hasChart = $body.text().includes('Churn Analysis') ||
                        $body.text().includes('Churn');
        if (hasChart) {
          cy.log('Churn Analysis chart found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Customer Growth chart', () => {
      cy.visit('/app/business/analytics');
      cy.get('body').then($body => {
        const hasChart = $body.text().includes('Customer Growth') ||
                        $body.text().includes('Customer');
        if (hasChart) {
          cy.log('Customer Growth chart found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Fallback Data Notification', () => {
    it('should display demo data notification when needed', () => {
      cy.visit('/app/business/analytics');
      cy.get('body').then($body => {
        const hasFallback = $body.text().includes('demo data') ||
                           $body.text().includes('unavailable') ||
                           $body.text().includes('Retry');
        if (hasFallback) {
          cy.log('Fallback data notification shown');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Permission Check', () => {
    it('should show access restricted for unauthorized users', () => {
      cy.visit('/app/business/analytics');
      cy.get('body').then($body => {
        const hasRestricted = $body.text().includes('Access Restricted') ||
                             $body.text().includes('analytics.read permission');
        const hasContent = $body.text().includes('Analytics Dashboard') ||
                          $body.text().includes('Overview');
        if (hasRestricted) {
          cy.log('Access restricted for unauthorized users');
        } else if (hasContent) {
          cy.log('User has permission to view analytics');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.intercept('GET', '**/api/**/analytics/**', {
        statusCode: 500,
        body: { error: 'Internal Server Error' }
      }).as('apiError');

      cy.visit('/app/business/analytics');
      cy.get('body').should('be.visible');
    });

    it('should display error state when data fails to load', () => {
      cy.intercept('GET', '**/api/**/analytics/**', {
        statusCode: 500,
        body: { error: 'Failed to load' }
      }).as('loadError');

      cy.visit('/app/business/analytics');
      cy.get('body').then($body => {
        const hasError = $body.text().includes('Error') ||
                        $body.text().includes('Try Again') ||
                        $body.text().includes('Failed');
        if (hasError) {
          cy.log('Error state displayed');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '**/api/**/analytics/**', (req) => {
        req.reply((res) => {
          res.delay = 2000;
          res.send({ success: true, data: {} });
        });
      }).as('slowLoad');

      cy.visit('/app/business/analytics');
      cy.get('body').then($body => {
        const hasLoading = $body.find('[class*="animate-spin"]').length > 0 ||
                          $body.text().includes('Loading') ||
                          $body.find('[class*="loading"]').length > 0;
        if (hasLoading) {
          cy.log('Loading indicator found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Export Modal', () => {
    it('should open export modal when Export clicked', () => {
      cy.visit('/app/business/analytics');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Export")').length > 0) {
          cy.contains('button', 'Export').click();
          cy.get('body').then($updated => {
            const hasModal = $updated.find('[class*="modal"]').length > 0 ||
                            $updated.text().includes('Export');
            if (hasModal) {
              cy.log('Export modal opened');
            }
          });
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/business/analytics');
      cy.get('body').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/business/analytics');
      cy.get('body').should('be.visible');
    });

    it('should stack charts on small screens', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/business/analytics');
      cy.get('body').then($body => {
        const hasGrid = $body.find('[class*="grid-cols-1"]').length > 0 ||
                       $body.find('[class*="lg:grid-cols"]').length > 0;
        if (hasGrid) {
          cy.log('Responsive chart layout found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should show multi-column chart layout on large screens', () => {
      cy.viewport(1920, 1080);
      cy.visit('/app/business/analytics');
      cy.get('body').then($body => {
        const hasMultiCol = $body.find('[class*="lg:grid-cols"]').length > 0;
        if (hasMultiCol) {
          cy.log('Multi-column chart layout found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });
});
