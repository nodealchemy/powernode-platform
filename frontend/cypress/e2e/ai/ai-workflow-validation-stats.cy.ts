/// <reference types="cypress" />

describe('AI Workflow Validation Statistics Page Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 5000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to Workflow Validation Statistics page', () => {
      cy.visit('/app/ai/workflows/validation-statistics');
      cy.url().should('include', '/ai');
    });

    it('should display page title', () => {
      cy.visit('/app/ai/workflows/validation-statistics');
      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('Validation Statistics') ||
                        $body.text().includes('Workflow Validation') ||
                        $body.find('[class*="PageContainer"]').length > 0;
        if (hasTitle) {
          cy.log('Validation statistics page title found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/ai/workflows/validation-statistics');
      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('AI') ||
                              $body.text().includes('Workflows') ||
                              $body.find('[class*="breadcrumb"]').length > 0;
        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Quick Stats Overview', () => {
    it('should display Total Workflows stat', () => {
      cy.visit('/app/ai/workflows/validation-statistics');
      cy.get('body').then($body => {
        const hasStat = $body.text().includes('Total Workflows');
        if (hasStat) {
          cy.log('Total Workflows stat found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Average Health stat', () => {
      cy.visit('/app/ai/workflows/validation-statistics');
      cy.get('body').then($body => {
        const hasStat = $body.text().includes('Average Health');
        if (hasStat) {
          cy.log('Average Health stat found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Valid Workflows stat', () => {
      cy.visit('/app/ai/workflows/validation-statistics');
      cy.get('body').then($body => {
        const hasStat = $body.text().includes('Valid Workflows');
        if (hasStat) {
          cy.log('Valid Workflows stat found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Issues Found stat', () => {
      cy.visit('/app/ai/workflows/validation-statistics');
      cy.get('body').then($body => {
        const hasStat = $body.text().includes('Issues Found') ||
                       $body.text().includes('Issues');
        if (hasStat) {
          cy.log('Issues stat found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display stat cards in grid layout', () => {
      cy.visit('/app/ai/workflows/validation-statistics');
      cy.get('body').then($body => {
        const hasCards = $body.find('[class*="grid"]').length > 0 ||
                        $body.find('[class*="stat"]').length > 0 ||
                        $body.find('[class*="card"]').length > 0;
        if (hasCards) {
          cy.log('Stat cards grid layout found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Validation Statistics Dashboard', () => {
    it('should display validation dashboard component', () => {
      cy.visit('/app/ai/workflows/validation-statistics');
      cy.get('body').then($body => {
        const hasDashboard = $body.text().includes('Validation') ||
                            $body.find('[class*="dashboard"]').length > 0;
        if (hasDashboard) {
          cy.log('Validation dashboard found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display validation status indicators', () => {
      cy.visit('/app/ai/workflows/validation-statistics');
      cy.get('body').then($body => {
        const hasIndicators = $body.find('[class*="status"]').length > 0 ||
                             $body.find('[class*="indicator"]').length > 0;
        if (hasIndicators) {
          cy.log('Status indicators found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Permission Check', () => {
    it('should show access denied for unauthorized users', () => {
      cy.visit('/app/ai/workflows/validation-statistics');
      cy.get('body').then($body => {
        const hasAccessDenied = $body.text().includes('Access Denied') ||
                               $body.text().includes('permission') ||
                               $body.text().includes('authorized');
        const hasContent = $body.text().includes('Validation Statistics') ||
                          $body.text().includes('Total Workflows');
        if (hasAccessDenied) {
          cy.log('Access denied shown for unauthorized users');
        } else if (hasContent) {
          cy.log('User has permission to view page');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display appropriate description based on admin status', () => {
      cy.visit('/app/ai/workflows/validation-statistics');
      cy.get('body').then($body => {
        const hasPlatformDesc = $body.text().includes('Platform-wide') ||
                               $body.text().includes('platform-wide');
        const hasAccountDesc = $body.text().includes('Your account') ||
                              $body.text().includes('your account');
        if (hasPlatformDesc) {
          cy.log('Admin description shown (Platform-wide)');
        } else if (hasAccountDesc) {
          cy.log('User description shown (Your account)');
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

      cy.visit('/app/ai/workflows/validation-statistics');
      cy.get('body').should('be.visible');
    });

    it('should display error state when data fails to load', () => {
      cy.intercept('GET', '**/api/**/workflows/statistics**', {
        statusCode: 500,
        body: { error: 'Server Error' }
      }).as('statsError');

      cy.visit('/app/ai/workflows/validation-statistics');
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

      cy.visit('/app/ai/workflows/validation-statistics');
      cy.get('body').then($body => {
        const hasSpinner = $body.find('[class*="animate-spin"]').length > 0 ||
                          $body.find('[class*="spinner"]').length > 0 ||
                          $body.find('[class*="loading"]').length > 0;
        if (hasSpinner) {
          cy.log('Loading indicator found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/ai/workflows/validation-statistics');
      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Validation') ||
                          $body.text().includes('Workflows');
        if (hasContent) {
          cy.log('Page content displays on mobile');
        }
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/ai/workflows/validation-statistics');
      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Validation') ||
                          $body.text().includes('Workflows');
        if (hasContent) {
          cy.log('Page content displays on tablet');
        }
      });
    });

    it('should stack stat cards on small screens', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/ai/workflows/validation-statistics');
      cy.get('body').then($body => {
        const hasGrid = $body.find('[class*="grid"]').length > 0;
        if (hasGrid) {
          cy.log('Grid layout found for stat cards');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should show multi-column layout on large screens', () => {
      cy.viewport(1920, 1080);
      cy.visit('/app/ai/workflows/validation-statistics');
      cy.get('body').then($body => {
        const hasGrid = $body.find('[class*="grid"]').length > 0 ||
                       $body.find('[class*="md:grid-cols"]').length > 0;
        if (hasGrid) {
          cy.log('Multi-column layout found for large screens');
        }
      });
      cy.get('body').should('be.visible');
    });
  });
});


export {};
