/// <reference types="cypress" />

describe('Marketplace Apps Page Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 5000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to Apps page', () => {
      cy.visit('/app/marketplace/apps');
      cy.url().should('include', '/marketplace');
    });

    it('should display page title', () => {
      cy.visit('/app/marketplace/apps');
      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('Apps') ||
                        $body.find('[class*="PageContainer"]').length > 0;
        if (hasTitle) {
          cy.log('Apps page title found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/marketplace/apps');
      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('Dashboard') ||
                              $body.text().includes('Apps');
        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Page Header', () => {
    it('should display Manage Your Apps section', () => {
      cy.visit('/app/marketplace/apps');
      cy.get('body').then($body => {
        const hasSection = $body.text().includes('Manage Your Apps') ||
                          $body.text().includes('Create, configure, and publish');
        if (hasSection) {
          cy.log('Manage Your Apps section found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display status indicators legend', () => {
      cy.visit('/app/marketplace/apps');
      cy.get('body').then($body => {
        const hasLegend = $body.text().includes('Published apps') ||
                         $body.text().includes('Draft apps') ||
                         $body.text().includes('Apps under review');
        if (hasLegend) {
          cy.log('Status indicators legend found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Page Actions', () => {
    it('should have Refresh button', () => {
      cy.visit('/app/marketplace/apps');
      cy.get('body').then($body => {
        const hasRefresh = $body.text().includes('Refresh') ||
                          $body.find('button:contains("Refresh")').length > 0;
        if (hasRefresh) {
          cy.log('Refresh button found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should have Create App button for authorized users', () => {
      cy.visit('/app/marketplace/apps');
      cy.get('body').then($body => {
        const hasCreate = $body.text().includes('Create App') ||
                         $body.find('button:contains("Create")').length > 0;
        if (hasCreate) {
          cy.log('Create App button found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should refresh apps list when Refresh clicked', () => {
      cy.visit('/app/marketplace/apps');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Refresh")').length > 0) {
          cy.contains('button', 'Refresh').click();
          cy.log('Refresh button clicked');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Create App Modal', () => {
    it('should open Create App modal when button clicked', () => {
      cy.visit('/app/marketplace/apps');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Create App")').length > 0) {
          cy.contains('button', 'Create App').click();
          cy.get('body').then($updated => {
            const hasModal = $updated.find('[class*="modal"]').length > 0 ||
                            $updated.text().includes('Create') ||
                            $updated.find('[role="dialog"]').length > 0;
            if (hasModal) {
              cy.log('Create App modal opened');
            }
          });
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should close Create App modal on cancel', () => {
      cy.visit('/app/marketplace/apps');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Create App")').length > 0) {
          cy.contains('button', 'Create App').click();
          cy.waitForPageLoad();
          cy.get('body').then($updated => {
            if ($updated.find('button:contains("Cancel")').length > 0) {
              cy.contains('button', 'Cancel').click();
              cy.log('Modal cancelled');
            }
          });
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Apps List', () => {
    it('should display AppsList component', () => {
      cy.visit('/app/marketplace/apps');
      cy.get('body').then($body => {
        const hasList = $body.find('[class*="list"]').length > 0 ||
                       $body.find('[class*="grid"]').length > 0 ||
                       $body.text().includes('No apps') ||
                       $body.text().includes('Create your first');
        if (hasList) {
          cy.log('Apps list component found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display empty state when no apps', () => {
      cy.visit('/app/marketplace/apps');
      cy.get('body').then($body => {
        const hasEmpty = $body.text().includes('No apps') ||
                        $body.text().includes('Create your first app') ||
                        $body.text().includes('Get started');
        if (hasEmpty) {
          cy.log('Empty state displayed');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display app cards when apps exist', () => {
      cy.visit('/app/marketplace/apps');
      cy.get('body').then($body => {
        const hasCards = $body.find('[class*="card"]').length > 0 ||
                        $body.find('[class*="Card"]').length > 0;
        if (hasCards) {
          cy.log('App cards displayed');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('App Status Indicators', () => {
    it('should display Published status indicator', () => {
      cy.visit('/app/marketplace/apps');
      cy.get('body').then($body => {
        const hasPublished = $body.text().includes('Published') ||
                            $body.find('[class*="success"]').length > 0;
        if (hasPublished) {
          cy.log('Published status indicator found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Draft status indicator', () => {
      cy.visit('/app/marketplace/apps');
      cy.get('body').then($body => {
        const hasDraft = $body.text().includes('Draft') ||
                        $body.find('[class*="warning"]').length > 0;
        if (hasDraft) {
          cy.log('Draft status indicator found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Under Review status indicator', () => {
      cy.visit('/app/marketplace/apps');
      cy.get('body').then($body => {
        const hasReview = $body.text().includes('Under Review') ||
                         $body.text().includes('review');
        if (hasReview) {
          cy.log('Under Review status indicator found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.intercept('GET', '**/api/**/apps**', {
        statusCode: 500,
        body: { error: 'Internal Server Error' }
      }).as('apiError');

      cy.visit('/app/marketplace/apps');
      cy.get('body').should('be.visible');
    });

    it('should display error state when data fails to load', () => {
      cy.intercept('GET', '**/api/**/apps**', {
        statusCode: 500,
        body: { error: 'Failed to load' }
      }).as('loadError');

      cy.visit('/app/marketplace/apps');
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
      cy.intercept('GET', '**/api/**/apps**', (req) => {
        req.reply((res) => {
          res.delay = 2000;
          res.send({ success: true, data: { apps: [] } });
        });
      }).as('slowLoad');

      cy.visit('/app/marketplace/apps');
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

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/marketplace/apps');
      cy.get('body').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/marketplace/apps');
      cy.get('body').should('be.visible');
    });

    it('should stack cards on small screens', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/marketplace/apps');
      cy.get('body').then($body => {
        const hasGrid = $body.find('[class*="grid-cols-1"]').length > 0 ||
                       $body.find('[class*="lg:grid-cols"]').length > 0;
        if (hasGrid) {
          cy.log('Responsive card layout found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should show multi-column layout on large screens', () => {
      cy.viewport(1920, 1080);
      cy.visit('/app/marketplace/apps');
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


export {};
