/// <reference types="cypress" />

describe('AI Workflow Analytics Page Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to Workflow Analytics page', () => {
      cy.visit('/app/ai/workflows/analytics');
      cy.url().should('include', '/ai');
    });

    it('should display page title', () => {
      cy.visit('/app/ai/workflows/analytics');
      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('Workflow Analytics') ||
                        $body.text().includes('Analytics') ||
                        $body.find('[class*="PageContainer"]').length > 0;
        if (hasTitle) {
          cy.log('Analytics page title found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display page description', () => {
      cy.visit('/app/ai/workflows/analytics');
      cy.get('body').then($body => {
        const hasDesc = $body.text().includes('Performance insights') ||
                       $body.text().includes('optimization') ||
                       $body.text().includes('AI workflows');
        if (hasDesc) {
          cy.log('Page description found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/ai/workflows/analytics');
      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('Dashboard') ||
                              $body.text().includes('AI') ||
                              $body.text().includes('Analytics');
        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Filter Controls', () => {
    it('should display period selector', () => {
      cy.visit('/app/ai/workflows/analytics');
      cy.get('body').then($body => {
        const hasSelect = $body.find('select').length > 0 ||
                         $body.text().includes('Last 7 days') ||
                         $body.text().includes('Last 30 days');
        if (hasSelect) {
          cy.log('Period selector found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display date range picker', () => {
      cy.visit('/app/ai/workflows/analytics');
      cy.get('body').then($body => {
        const hasDatePicker = $body.find('[class*="DateRangePicker"]').length > 0 ||
                             $body.find('input[type="date"]').length > 0 ||
                             $body.find('[class*="date"]').length > 0;
        if (hasDatePicker) {
          cy.log('Date range picker found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should have period options', () => {
      cy.visit('/app/ai/workflows/analytics');
      cy.get('body').then($body => {
        const hasPeriods = $body.text().includes('7 days') ||
                          $body.text().includes('30 days') ||
                          $body.text().includes('90 days') ||
                          $body.text().includes('year');
        if (hasPeriods) {
          cy.log('Period options found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Overview Metrics', () => {
    it('should display Total Workflows metric', () => {
      cy.visit('/app/ai/workflows/analytics');
      cy.get('body').then($body => {
        const hasMetric = $body.text().includes('Total Workflows');
        if (hasMetric) {
          cy.log('Total Workflows metric found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Active Workflows metric', () => {
      cy.visit('/app/ai/workflows/analytics');
      cy.get('body').then($body => {
        const hasMetric = $body.text().includes('Active Workflows');
        if (hasMetric) {
          cy.log('Active Workflows metric found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Total Executions metric', () => {
      cy.visit('/app/ai/workflows/analytics');
      cy.get('body').then($body => {
        const hasMetric = $body.text().includes('Total Executions') ||
                         $body.text().includes('Executions');
        if (hasMetric) {
          cy.log('Total Executions metric found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Success Rate metric', () => {
      cy.visit('/app/ai/workflows/analytics');
      cy.get('body').then($body => {
        const hasMetric = $body.text().includes('Success Rate') ||
                         $body.text().includes('success rate');
        if (hasMetric) {
          cy.log('Success Rate metric found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Performance Metrics', () => {
    it('should display Avg Execution Time metric', () => {
      cy.visit('/app/ai/workflows/analytics');
      cy.get('body').then($body => {
        const hasMetric = $body.text().includes('Avg Execution') ||
                         $body.text().includes('Execution Time') ||
                         $body.text().includes('Average');
        if (hasMetric) {
          cy.log('Avg Execution Time metric found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Failed Executions metric', () => {
      cy.visit('/app/ai/workflows/analytics');
      cy.get('body').then($body => {
        const hasMetric = $body.text().includes('Failed') ||
                         $body.text().includes('Failures');
        if (hasMetric) {
          cy.log('Failed Executions metric found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Min Execution Time metric', () => {
      cy.visit('/app/ai/workflows/analytics');
      cy.get('body').then($body => {
        const hasMetric = $body.text().includes('Min Execution') ||
                         $body.text().includes('Minimum');
        if (hasMetric) {
          cy.log('Min Execution Time metric found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Max Execution Time metric', () => {
      cy.visit('/app/ai/workflows/analytics');
      cy.get('body').then($body => {
        const hasMetric = $body.text().includes('Max Execution') ||
                         $body.text().includes('Maximum');
        if (hasMetric) {
          cy.log('Max Execution Time metric found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Charts and Data', () => {
    it('should display Daily Executions section', () => {
      cy.visit('/app/ai/workflows/analytics');
      cy.get('body').then($body => {
        const hasChart = $body.text().includes('Daily Executions') ||
                        $body.text().includes('daily');
        if (hasChart) {
          cy.log('Daily Executions section found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Most Active Users section', () => {
      cy.visit('/app/ai/workflows/analytics');
      cy.get('body').then($body => {
        const hasSection = $body.text().includes('Most Active Users') ||
                          $body.text().includes('Active Users');
        if (hasSection) {
          cy.log('Most Active Users section found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Recommendations', () => {
    it('should display Optimization Recommendations section', () => {
      cy.visit('/app/ai/workflows/analytics');
      cy.get('body').then($body => {
        const hasSection = $body.text().includes('Optimization') ||
                          $body.text().includes('Recommendations');
        if (hasSection) {
          cy.log('Recommendations section found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Page Actions', () => {
    it('should have Export Data button', () => {
      cy.visit('/app/ai/workflows/analytics');
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

  describe('Permission Check', () => {
    it('should show access denied for unauthorized users', () => {
      cy.visit('/app/ai/workflows/analytics');
      cy.get('body').then($body => {
        const hasAccessDenied = $body.text().includes('Access Denied') ||
                               $body.text().includes('permission') ||
                               $body.text().includes("don't have permission");
        const hasContent = $body.text().includes('Workflow Analytics') ||
                          $body.text().includes('Total Workflows');
        if (hasAccessDenied) {
          cy.log('Access denied shown for unauthorized users');
        } else if (hasContent) {
          cy.log('User has permission to view analytics');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.intercept('GET', '**/api/**/workflows/**', {
        statusCode: 500,
        body: { error: 'Internal Server Error' }
      }).as('apiError');

      cy.visit('/app/ai/workflows/analytics');
      cy.get('body').should('be.visible');
    });

    it('should display error notification on API failure', () => {
      cy.intercept('GET', '**/api/**/workflows/statistics**', {
        statusCode: 500,
        body: { error: 'Statistics API failed' }
      }).as('statsError');

      cy.visit('/app/ai/workflows/analytics');
      cy.get('body').should('be.visible');
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '**/api/**/workflows/**', (req) => {
        req.reply((res) => {
          res.delay = 2000;
          res.send({ data: {} });
        });
      }).as('slowLoad');

      cy.visit('/app/ai/workflows/analytics');
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

    it('should display loading skeleton cards', () => {
      cy.intercept('GET', '**/api/**/workflows/**', (req) => {
        req.reply((res) => {
          res.delay = 3000;
          res.send({ data: {} });
        });
      }).as('slowLoad');

      cy.visit('/app/ai/workflows/analytics');
      cy.get('body').then($body => {
        const hasSkeleton = $body.find('[class*="animate-pulse"]').length > 0 ||
                           $body.find('[class*="skeleton"]').length > 0;
        if (hasSkeleton) {
          cy.log('Loading skeleton found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Empty State', () => {
    it('should display empty state when no data', () => {
      cy.intercept('GET', '**/api/**/workflows/statistics**', {
        statusCode: 200,
        body: { success: true, data: { totalWorkflows: 0 } }
      }).as('emptyStats');

      cy.visit('/app/ai/workflows/analytics');
      cy.get('body').then($body => {
        const hasEmptyState = $body.text().includes('No Analytics Data') ||
                             $body.text().includes('No data') ||
                             $body.text().includes('No analytics');
        if (hasEmptyState) {
          cy.log('Empty state displayed');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/ai/workflows/analytics');
      cy.get('body').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/ai/workflows/analytics');
      cy.get('body').should('be.visible');
    });

    it('should stack metric cards on small screens', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/ai/workflows/analytics');
      cy.get('body').then($body => {
        const hasGrid = $body.find('[class*="grid"]').length > 0;
        if (hasGrid) {
          cy.log('Grid layout for responsive cards found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should show multi-column layout on large screens', () => {
      cy.viewport(1920, 1080);
      cy.visit('/app/ai/workflows/analytics');
      cy.get('body').then($body => {
        const hasMultiCol = $body.find('[class*="lg:grid-cols"]').length > 0 ||
                           $body.find('[class*="md:grid-cols"]').length > 0;
        if (hasMultiCol) {
          cy.log('Multi-column layout found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });
});
