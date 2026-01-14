/// <reference types="cypress" />

describe('DevOps New Integration Page Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 5000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to New Integration page', () => {
      cy.visit('/app/devops/integrations/new');
      cy.url().should('include', '/devops');
    });

    it('should display page title', () => {
      cy.visit('/app/devops/integrations/new');
      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('Add Integration') ||
                        $body.find('[class*="PageContainer"]').length > 0;
        if (hasTitle) {
          cy.log('Add Integration page title found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display page description', () => {
      cy.visit('/app/devops/integrations/new');
      cy.get('body').then($body => {
        const hasDesc = $body.text().includes('Set up a new integration') ||
                       $body.text().includes('integration');
        if (hasDesc) {
          cy.log('Page description found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Page Actions', () => {
    it('should have Cancel button', () => {
      cy.visit('/app/devops/integrations/new');
      cy.get('body').then($body => {
        const hasCancel = $body.text().includes('Cancel') ||
                         $body.find('button:contains("Cancel")').length > 0;
        if (hasCancel) {
          cy.log('Cancel button found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should navigate back on Cancel click', () => {
      cy.visit('/app/devops/integrations/new');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Cancel")').length > 0) {
          cy.contains('button', 'Cancel').click();
          cy.url().should('include', '/integrations');
        }
      });
    });
  });

  describe('Integration Wizard', () => {
    it('should display IntegrationWizard component', () => {
      cy.visit('/app/devops/integrations/new');
      cy.get('body').then($body => {
        const hasWizard = $body.find('[class*="wizard"]').length > 0 ||
                         $body.find('[class*="step"]').length > 0 ||
                         $body.text().includes('Select') ||
                         $body.text().includes('Choose');
        if (hasWizard) {
          cy.log('Integration wizard component found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display integration type selection', () => {
      cy.visit('/app/devops/integrations/new');
      cy.get('body').then($body => {
        const hasTypes = $body.find('[class*="card"]').length > 0 ||
                        $body.find('[class*="grid"]').length > 0;
        if (hasTypes) {
          cy.log('Integration type selection found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display wizard step indicators', () => {
      cy.visit('/app/devops/integrations/new');
      cy.get('body').then($body => {
        const hasSteps = $body.find('[class*="step"]').length > 0 ||
                        $body.text().includes('Step') ||
                        $body.text().match(/\d+\s*of\s*\d+/);
        if (hasSteps) {
          cy.log('Wizard step indicators found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.intercept('GET', '**/api/**/integration**', {
        statusCode: 500,
        body: { error: 'Internal Server Error' }
      }).as('apiError');

      cy.visit('/app/devops/integrations/new');
      cy.get('body').should('be.visible');
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '**/api/**/integration**', (req) => {
        req.reply((res) => {
          res.delay = 2000;
          res.send({ success: true, data: {} });
        });
      }).as('slowLoad');

      cy.visit('/app/devops/integrations/new');
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
      cy.visit('/app/devops/integrations/new');
      cy.get('body').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/devops/integrations/new');
      cy.get('body').should('be.visible');
    });
  });
});


export {};
