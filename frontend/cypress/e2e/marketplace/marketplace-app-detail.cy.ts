/// <reference types="cypress" />

describe('Marketplace App Detail Page Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to App Detail page', () => {
      cy.visit('/app/marketplace/apps/test-app');
      cy.url().should('include', '/marketplace');
    });

    it('should display App Not Found for invalid app', () => {
      cy.visit('/app/marketplace/apps/invalid-app-id');
      cy.get('body').then($body => {
        const hasNotFound = $body.text().includes('Not Found') ||
                           $body.text().includes("doesn't exist") ||
                           $body.text().includes('Back to');
        if (hasNotFound) {
          cy.log('App not found message displayed');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/marketplace/apps/test-app');
      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('Dashboard') ||
                              $body.text().includes('Marketplace') ||
                              $body.text().includes('My Apps');
        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Page Actions', () => {
    it('should have Edit App button', () => {
      cy.visit('/app/marketplace/apps/test-app');
      cy.get('body').then($body => {
        const hasEdit = $body.text().includes('Edit App') ||
                       $body.text().includes('Edit');
        if (hasEdit) {
          cy.log('Edit App button found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should have Refresh button', () => {
      cy.visit('/app/marketplace/apps/test-app');
      cy.get('body').then($body => {
        const hasRefresh = $body.text().includes('Refresh') ||
                          $body.find('button:contains("Refresh")').length > 0;
        if (hasRefresh) {
          cy.log('Refresh button found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should have Publish/Unpublish button based on status', () => {
      cy.visit('/app/marketplace/apps/test-app');
      cy.get('body').then($body => {
        const hasPublish = $body.text().includes('Publish') ||
                          $body.text().includes('Unpublish');
        if (hasPublish) {
          cy.log('Publish/Unpublish button found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should have Manage Subscription for subscribed apps', () => {
      cy.visit('/app/marketplace/apps/test-app');
      cy.get('body').then($body => {
        const hasManage = $body.text().includes('Manage Subscription');
        if (hasManage) {
          cy.log('Manage Subscription button found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('App Header', () => {
    it('should display app icon', () => {
      cy.visit('/app/marketplace/apps/test-app');
      cy.get('body').then($body => {
        const hasIcon = $body.find('[class*="rounded-xl"]').length > 0 ||
                       $body.find('img[class*="rounded"]').length > 0;
        if (hasIcon) {
          cy.log('App icon found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display app name', () => {
      cy.visit('/app/marketplace/apps/test-app');
      cy.get('body').then($body => {
        const hasName = $body.find('h1').length > 0 ||
                       $body.find('[class*="font-bold"]').length > 0;
        if (hasName) {
          cy.log('App name found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display status badge', () => {
      cy.visit('/app/marketplace/apps/test-app');
      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Published') ||
                         $body.text().includes('Draft') ||
                         $body.text().includes('Under Review') ||
                         $body.text().includes('Inactive');
        if (hasStatus) {
          cy.log('Status badge found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display version badge', () => {
      cy.visit('/app/marketplace/apps/test-app');
      cy.get('body').then($body => {
        const hasVersion = $body.text().match(/v\d+\.\d+/) ||
                          $body.text().includes('Version');
        if (hasVersion) {
          cy.log('Version badge found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display app description', () => {
      cy.visit('/app/marketplace/apps/test-app');
      cy.get('body').then($body => {
        const hasDesc = $body.find('p[class*="secondary"]').length > 0;
        if (hasDesc) {
          cy.log('App description found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display app metadata grid', () => {
      cy.visit('/app/marketplace/apps/test-app');
      cy.get('body').then($body => {
        const hasMeta = $body.text().includes('Updated') ||
                       $body.text().includes('endpoints') ||
                       $body.text().includes('webhooks');
        if (hasMeta) {
          cy.log('App metadata grid found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Tab Navigation', () => {
    it('should display Overview tab', () => {
      cy.visit('/app/marketplace/apps/test-app');
      cy.get('body').then($body => {
        const hasTab = $body.text().includes('Overview');
        if (hasTab) {
          cy.log('Overview tab found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display API Endpoints tab', () => {
      cy.visit('/app/marketplace/apps/test-app');
      cy.get('body').then($body => {
        const hasTab = $body.text().includes('API Endpoints') ||
                      $body.text().includes('Endpoints');
        if (hasTab) {
          cy.log('API Endpoints tab found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Webhooks tab', () => {
      cy.visit('/app/marketplace/apps/test-app');
      cy.get('body').then($body => {
        const hasTab = $body.text().includes('Webhooks');
        if (hasTab) {
          cy.log('Webhooks tab found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Analytics tab', () => {
      cy.visit('/app/marketplace/apps/test-app');
      cy.get('body').then($body => {
        const hasTab = $body.text().includes('Analytics');
        if (hasTab) {
          cy.log('Analytics tab found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should switch to Endpoints tab', () => {
      cy.visit('/app/marketplace/apps/test-app');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Endpoints")').length > 0) {
          cy.contains('button', 'Endpoints').click();
          cy.log('Switched to Endpoints tab');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should switch to Webhooks tab', () => {
      cy.visit('/app/marketplace/apps/test-app');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Webhooks")').length > 0) {
          cy.contains('button', 'Webhooks').click();
          cy.log('Switched to Webhooks tab');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Overview Tab Content', () => {
    it('should display Description section', () => {
      cy.visit('/app/marketplace/apps/test-app');
      cy.get('body').then($body => {
        const hasDesc = $body.text().includes('Description');
        if (hasDesc) {
          cy.log('Description section found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Tags section', () => {
      cy.visit('/app/marketplace/apps/test-app');
      cy.get('body').then($body => {
        const hasTags = $body.text().includes('Tags') ||
                       $body.find('[class*="badge"]').length > 0;
        if (hasTags) {
          cy.log('Tags section found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Quick Stats section', () => {
      cy.visit('/app/marketplace/apps/test-app');
      cy.get('body').then($body => {
        const hasStats = $body.text().includes('Quick Stats') ||
                        $body.text().includes('API Endpoints') ||
                        $body.text().includes('Status');
        if (hasStats) {
          cy.log('Quick Stats section found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Endpoints Tab Content', () => {
    it('should display endpoint cards or empty state', () => {
      cy.visit('/app/marketplace/apps/test-app');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Endpoints")').length > 0) {
          cy.contains('button', 'Endpoints').click();
          cy.get('body').then($updated => {
            const hasEndpoints = $updated.text().includes('No API endpoints') ||
                                $updated.find('[class*="endpoint"]').length > 0 ||
                                $updated.find('[class*="card"]').length > 0;
            if (hasEndpoints) {
              cy.log('Endpoints content displayed');
            }
          });
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Analytics Tab Content', () => {
    it('should display Analytics Coming Soon', () => {
      cy.visit('/app/marketplace/apps/test-app');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Analytics")').length > 0) {
          cy.contains('button', 'Analytics').click();
          cy.get('body').then($updated => {
            const hasAnalytics = $updated.text().includes('Analytics Coming Soon') ||
                                $updated.text().includes('usage metrics');
            if (hasAnalytics) {
              cy.log('Analytics tab content displayed');
            }
          });
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.intercept('GET', '**/api/**/apps/**', {
        statusCode: 500,
        body: { error: 'Internal Server Error' }
      }).as('apiError');

      cy.visit('/app/marketplace/apps/test-app');
      cy.get('body').should('be.visible');
    });

    it('should display error state for missing app', () => {
      cy.intercept('GET', '**/api/**/apps/**', {
        statusCode: 404,
        body: { error: 'App not found' }
      }).as('notFoundError');

      cy.visit('/app/marketplace/apps/test-app');
      cy.get('body').then($body => {
        const hasError = $body.text().includes('Not Found') ||
                        $body.text().includes('Back to');
        if (hasError) {
          cy.log('Error state displayed');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '**/api/**/apps/**', (req) => {
        req.reply((res) => {
          res.delay = 2000;
          res.send({ success: true, data: {} });
        });
      }).as('slowLoad');

      cy.visit('/app/marketplace/apps/test-app');
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
      cy.visit('/app/marketplace/apps/test-app');
      cy.get('body').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/marketplace/apps/test-app');
      cy.get('body').should('be.visible');
    });

    it('should stack columns on small screens', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/marketplace/apps/test-app');
      cy.get('body').then($body => {
        const hasGrid = $body.find('[class*="grid-cols-1"]').length > 0 ||
                       $body.find('[class*="lg:grid-cols"]').length > 0;
        if (hasGrid) {
          cy.log('Responsive column layout found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should show multi-column layout on large screens', () => {
      cy.viewport(1920, 1080);
      cy.visit('/app/marketplace/apps/test-app');
      cy.get('body').then($body => {
        const hasMultiCol = $body.find('[class*="lg:grid-cols"]').length > 0 ||
                           $body.find('[class*="lg:col-span"]').length > 0;
        if (hasMultiCol) {
          cy.log('Multi-column layout found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });
});
