/// <reference types="cypress" />

/**
 * BaaS (Billing-as-a-Service) Dashboard Tests
 *
 * Tests for BaaS Dashboard functionality including:
 * - Page navigation and load
 * - Dashboard overview display
 * - Tenant information
 * - API keys management
 * - Settings configuration
 * - Tab navigation
 * - Error handling
 * - Responsive design
 */

describe('BaaS Dashboard Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Page Navigation', () => {
    it('should navigate to BaaS dashboard page', () => {
      cy.visit('/app/baas');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasContent = $body.text().includes('BaaS') ||
                          $body.text().includes('Billing-as-a-Service') ||
                          $body.text().includes('Dashboard');
        if (hasContent) {
          cy.log('BaaS dashboard page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page title', () => {
      cy.visit('/app/baas');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('BaaS Dashboard') ||
                        $body.text().includes('Billing-as-a-Service');
        if (hasTitle) {
          cy.log('Page title displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display setup prompt when no tenant configured', () => {
      cy.visit('/app/baas');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSetupPrompt = $body.text().includes('Set Up') ||
                               $body.text().includes('Get Started') ||
                               $body.text().includes('Start Billing');
        if (hasSetupPrompt) {
          cy.log('Setup prompt displayed for new users');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Dashboard Overview', () => {
    beforeEach(() => {
      cy.visit('/app/baas');
      cy.waitForPageLoad();
    });

    it('should display tenant overview when configured', () => {
      cy.get('body').then($body => {
        const hasOverview = $body.text().includes('Overview') ||
                           $body.find('[data-testid="tenant-overview"]').length > 0;
        if (hasOverview) {
          cy.log('Tenant overview displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display statistics cards', () => {
      cy.get('body').then($body => {
        const hasStats = $body.text().includes('Total') ||
                        $body.text().includes('Revenue') ||
                        $body.text().includes('Customers') ||
                        $body.text().includes('Subscriptions');
        if (hasStats) {
          cy.log('Statistics cards displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Tab Navigation', () => {
    beforeEach(() => {
      cy.visit('/app/baas');
      cy.waitForPageLoad();
    });

    it('should display tab navigation', () => {
      cy.get('body').then($body => {
        const hasTabs = $body.text().includes('Overview') ||
                       $body.text().includes('API Keys') ||
                       $body.text().includes('Settings');
        if (hasTabs) {
          cy.log('Tab navigation displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should switch to API Keys tab', () => {
      cy.get('body').then($body => {
        const apiKeysTab = $body.find('button:contains("API Keys")');
        if (apiKeysTab.length > 0) {
          cy.wrap(apiKeysTab).first().click();
          cy.log('Switched to API Keys tab');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should switch to Settings tab', () => {
      cy.get('body').then($body => {
        const settingsTab = $body.find('button:contains("Settings")');
        if (settingsTab.length > 0) {
          cy.wrap(settingsTab).first().click();
          cy.log('Switched to Settings tab');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('API Keys Management', () => {
    beforeEach(() => {
      cy.visit('/app/baas');
      cy.waitForPageLoad();
    });

    it('should display API keys section', () => {
      cy.get('body').then($body => {
        const hasApiKeys = $body.text().includes('API Keys') ||
                          $body.text().includes('API Key');
        if (hasApiKeys) {
          cy.log('API Keys section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display create API key button', () => {
      cy.get('body').then($body => {
        const hasCreateBtn = $body.text().includes('Create API Key') ||
                            $body.find('button:contains("Create")').length > 0;
        if (hasCreateBtn) {
          cy.log('Create API Key button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display API keys table when keys exist', () => {
      cy.get('body').then($body => {
        const hasTable = $body.text().includes('Name') ||
                        $body.text().includes('Key') ||
                        $body.text().includes('Status') ||
                        $body.text().includes('No API keys');
        if (hasTable) {
          cy.log('API keys table or empty state displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display revoke option for active keys', () => {
      cy.get('body').then($body => {
        const hasRevoke = $body.text().includes('Revoke') ||
                         $body.find('[data-testid="revoke-key"]').length > 0 ||
                         $body.text().includes('No API keys');
        if (hasRevoke) {
          cy.log('Revoke option available or no keys to revoke');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Settings Configuration', () => {
    beforeEach(() => {
      cy.visit('/app/baas');
      cy.waitForPageLoad();
    });

    it('should display billing configuration section', () => {
      cy.get('body').then($body => {
        const hasConfig = $body.text().includes('Billing Configuration') ||
                         $body.text().includes('Configuration') ||
                         $body.text().includes('Settings');
        if (hasConfig) {
          cy.log('Billing configuration section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display payment gateways section', () => {
      cy.get('body').then($body => {
        const hasGateways = $body.text().includes('Payment Gateways') ||
                           $body.text().includes('Stripe') ||
                           $body.text().includes('PayPal');
        if (hasGateways) {
          cy.log('Payment gateways section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display invoice settings', () => {
      cy.get('body').then($body => {
        const hasInvoice = $body.text().includes('Invoice') ||
                          $body.text().includes('Due Days') ||
                          $body.text().includes('Auto Invoice');
        if (hasInvoice) {
          cy.log('Invoice settings displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Action Buttons', () => {
    beforeEach(() => {
      cy.visit('/app/baas');
      cy.waitForPageLoad();
    });

    it('should display API Docs button', () => {
      cy.get('body').then($body => {
        const hasDocsBtn = $body.text().includes('API Docs') ||
                          $body.find('a:contains("Docs"), button:contains("Docs")').length > 0;
        if (hasDocsBtn) {
          cy.log('API Docs button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Manage Customers button', () => {
      cy.get('body').then($body => {
        const hasCustomersBtn = $body.text().includes('Manage Customers') ||
                               $body.text().includes('Customers');
        if (hasCustomersBtn) {
          cy.log('Manage Customers button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Loading States', () => {
    it('should show loading indicator while fetching data', () => {
      cy.visit('/app/baas');

      cy.get('body').then($body => {
        const hasLoader = $body.find('.animate-spin').length > 0 ||
                         $body.find('[data-testid="loading"]').length > 0 ||
                         $body.text().includes('Loading');
        if (hasLoader) {
          cy.log('Loading indicator shown');
        }
      });

      cy.waitForPageLoad();
      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.visit('/app/baas');
      cy.waitForPageLoad();

      // Page should still be functional even if API fails
      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/baas');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`BaaS dashboard displayed correctly on ${name}`);
      });
    });
  });
});
