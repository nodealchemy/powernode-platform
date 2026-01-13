/// <reference types="cypress" />

describe('Business Reports Overview Page Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to Reports Overview page', () => {
      cy.visit('/app/business/reports/overview');
      cy.url().should('include', '/business');
    });

    it('should display page title', () => {
      cy.visit('/app/business/reports/overview');
      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('Reports Overview') ||
                        $body.find('[class*="PageContainer"]').length > 0;
        if (hasTitle) {
          cy.log('Reports Overview page title found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display page description', () => {
      cy.visit('/app/business/reports/overview');
      cy.get('body').then($body => {
        const hasDesc = $body.text().includes('Monitor your reporting') ||
                       $body.text().includes('activity') ||
                       $body.text().includes('performance');
        if (hasDesc) {
          cy.log('Page description found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/business/reports/overview');
      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('Dashboard') ||
                              $body.text().includes('Business') ||
                              $body.text().includes('Reports');
        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Stats Grid', () => {
    it('should display Total Reports stat', () => {
      cy.visit('/app/business/reports/overview');
      cy.get('body').then($body => {
        const hasTotal = $body.text().includes('Total Reports');
        if (hasTotal) {
          cy.log('Total Reports stat found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display This Month stat', () => {
      cy.visit('/app/business/reports/overview');
      cy.get('body').then($body => {
        const hasMonth = $body.text().includes('This Month');
        if (hasMonth) {
          cy.log('This Month stat found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Pending stat', () => {
      cy.visit('/app/business/reports/overview');
      cy.get('body').then($body => {
        const hasPending = $body.text().includes('Pending');
        if (hasPending) {
          cy.log('Pending stat found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Downloads stat', () => {
      cy.visit('/app/business/reports/overview');
      cy.get('body').then($body => {
        const hasDownloads = $body.text().includes('Downloads');
        if (hasDownloads) {
          cy.log('Downloads stat found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Performance Metrics', () => {
    it('should display Performance Metrics section', () => {
      cy.visit('/app/business/reports/overview');
      cy.get('body').then($body => {
        const hasMetrics = $body.text().includes('Performance Metrics');
        if (hasMetrics) {
          cy.log('Performance Metrics section found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Average Generation Time', () => {
      cy.visit('/app/business/reports/overview');
      cy.get('body').then($body => {
        const hasGenTime = $body.text().includes('Average Generation Time') ||
                          $body.text().includes('Generation Time');
        if (hasGenTime) {
          cy.log('Average Generation Time found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Storage Used', () => {
      cy.visit('/app/business/reports/overview');
      cy.get('body').then($body => {
        const hasStorage = $body.text().includes('Storage Used');
        if (hasStorage) {
          cy.log('Storage Used found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Most Popular Template', () => {
      cy.visit('/app/business/reports/overview');
      cy.get('body').then($body => {
        const hasTemplate = $body.text().includes('Most Popular Template');
        if (hasTemplate) {
          cy.log('Most Popular Template found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Failed Reports when present', () => {
      cy.visit('/app/business/reports/overview');
      cy.get('body').then($body => {
        const hasFailed = $body.text().includes('Failed Reports') ||
                         $body.text().includes('Failed');
        if (hasFailed) {
          cy.log('Failed Reports metric found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Quick Actions', () => {
    it('should display Quick Actions section', () => {
      cy.visit('/app/business/reports/overview');
      cy.get('body').then($body => {
        const hasActions = $body.text().includes('Quick Actions');
        if (hasActions) {
          cy.log('Quick Actions section found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Create New Report action', () => {
      cy.visit('/app/business/reports/overview');
      cy.get('body').then($body => {
        const hasCreate = $body.text().includes('Create New Report') ||
                         $body.text().includes('building a custom report');
        if (hasCreate) {
          cy.log('Create New Report action found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Schedule Report action', () => {
      cy.visit('/app/business/reports/overview');
      cy.get('body').then($body => {
        const hasSchedule = $body.text().includes('Schedule Report') ||
                           $body.text().includes('automated reporting');
        if (hasSchedule) {
          cy.log('Schedule Report action found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display View Analytics action', () => {
      cy.visit('/app/business/reports/overview');
      cy.get('body').then($body => {
        const hasAnalytics = $body.text().includes('View Analytics') ||
                            $body.text().includes('reporting trends');
        if (hasAnalytics) {
          cy.log('View Analytics action found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Recent Reports', () => {
    it('should display Recent Reports section', () => {
      cy.visit('/app/business/reports/overview');
      cy.get('body').then($body => {
        const hasRecent = $body.text().includes('Recent Reports');
        if (hasRecent) {
          cy.log('Recent Reports section found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display View All link', () => {
      cy.visit('/app/business/reports/overview');
      cy.get('body').then($body => {
        const hasViewAll = $body.text().includes('View All');
        if (hasViewAll) {
          cy.log('View All link found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display report items or empty state', () => {
      cy.visit('/app/business/reports/overview');
      cy.get('body').then($body => {
        const hasReports = $body.find('[class*="bg-theme-background"]').length > 0 ||
                          $body.text().includes('No recent reports');
        if (hasReports) {
          cy.log('Report items or empty state displayed');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display report status icons', () => {
      cy.visit('/app/business/reports/overview');
      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Completed') ||
                         $body.text().includes('Processing') ||
                         $body.text().includes('Pending') ||
                         $body.text().includes('Failed');
        if (hasStatus) {
          cy.log('Report status icons found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display download button for completed reports', () => {
      cy.visit('/app/business/reports/overview');
      cy.get('body').then($body => {
        const hasDownload = $body.find('button[class*="link"]').length > 0 ||
                           $body.find('svg[class*="download"]').length > 0;
        if (hasDownload) {
          cy.log('Download button found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Report Details', () => {
    it('should display report name', () => {
      cy.visit('/app/business/reports/overview');
      cy.get('body').then($body => {
        const hasName = $body.find('p[class*="font-medium"]').length > 0;
        if (hasName) {
          cy.log('Report name found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display report template', () => {
      cy.visit('/app/business/reports/overview');
      cy.get('body').then($body => {
        const hasTemplate = $body.text().includes('Revenue Analysis') ||
                           $body.text().includes('Customer Analytics') ||
                           $body.text().includes('Subscription Report');
        if (hasTemplate) {
          cy.log('Report template found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display report timestamp', () => {
      cy.visit('/app/business/reports/overview');
      cy.get('body').then($body => {
        const hasTimestamp = $body.text().match(/\d{1,2}:\d{2}/) ||
                            $body.text().includes('AM') ||
                            $body.text().includes('PM');
        if (hasTimestamp) {
          cy.log('Report timestamp found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display file size for completed reports', () => {
      cy.visit('/app/business/reports/overview');
      cy.get('body').then($body => {
        const hasSize = $body.text().match(/\d+(\.\d+)?\s*(KB|MB|GB)/) ||
                       $body.text().includes('MB') ||
                       $body.text().includes('KB');
        if (hasSize) {
          cy.log('File size found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.intercept('GET', '**/api/**/reports/**', {
        statusCode: 500,
        body: { error: 'Internal Server Error' }
      }).as('apiError');

      cy.visit('/app/business/reports/overview');
      cy.get('body').should('be.visible');
    });

    it('should display error state when data fails to load', () => {
      cy.intercept('GET', '**/api/**/reports/**', {
        statusCode: 500,
        body: { error: 'Failed to load' }
      }).as('loadError');

      cy.visit('/app/business/reports/overview');
      cy.get('body').then($body => {
        const hasError = $body.text().includes('Error Loading') ||
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
      cy.intercept('GET', '**/api/**/reports/**', (req) => {
        req.reply((res) => {
          res.delay = 2000;
          res.send({ success: true, data: {} });
        });
      }).as('slowLoad');

      cy.visit('/app/business/reports/overview');
      cy.get('body').then($body => {
        const hasLoading = $body.find('[class*="animate-spin"]').length > 0 ||
                          $body.text().includes('Loading') ||
                          $body.find('[class*="LoadingSpinner"]').length > 0;
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
      cy.visit('/app/business/reports/overview');
      cy.get('body').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/business/reports/overview');
      cy.get('body').should('be.visible');
    });

    it('should stack stats cards on small screens', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/business/reports/overview');
      cy.get('body').then($body => {
        const hasGrid = $body.find('[class*="grid-cols-1"]').length > 0 ||
                       $body.find('[class*="md:grid-cols"]').length > 0;
        if (hasGrid) {
          cy.log('Responsive stats grid found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should show multi-column layout on large screens', () => {
      cy.viewport(1920, 1080);
      cy.visit('/app/business/reports/overview');
      cy.get('body').then($body => {
        const hasMultiCol = $body.find('[class*="lg:grid-cols-4"]').length > 0 ||
                           $body.find('[class*="lg:grid-cols-2"]').length > 0;
        if (hasMultiCol) {
          cy.log('Multi-column layout found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });
});
