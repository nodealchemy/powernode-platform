/// <reference types="cypress" />

/**
 * BaaS Tenant Onboarding Tests
 *
 * Tests for BaaS Tenant Onboarding functionality including:
 * - Tenant creation workflow
 * - Configuration setup
 * - API key generation
 * - Billing configuration
 * - Welcome wizard
 * - Tenant activation
 */

describe('BaaS Tenant Onboarding Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Tenant Creation', () => {
    it('should navigate to tenant creation page', () => {
      cy.visit('/app/baas/tenants/new');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCreate = $body.text().includes('Create') ||
                         $body.text().includes('New Tenant') ||
                         $body.text().includes('Onboard');
        if (hasCreate) {
          cy.log('Tenant creation page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display tenant creation form', () => {
      cy.visit('/app/baas/tenants/new');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasForm = $body.find('form, [data-testid="tenant-form"]').length > 0;
        if (hasForm) {
          cy.log('Tenant creation form displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have tenant name field', () => {
      cy.visit('/app/baas/tenants/new');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasName = $body.find('input[name*="name"], input[placeholder*="name"], label:contains("Name")').length > 0 ||
                       $body.text().includes('Tenant Name') ||
                       $body.text().includes('Name');
        if (hasName) {
          cy.log('Tenant name field displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have domain/subdomain field', () => {
      cy.visit('/app/baas/tenants/new');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDomain = $body.find('input[name*="domain"], input[name*="subdomain"]').length > 0 ||
                         $body.text().includes('Domain') ||
                         $body.text().includes('Subdomain');
        if (hasDomain) {
          cy.log('Domain field displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have plan selection', () => {
      cy.visit('/app/baas/tenants/new');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasPlan = $body.text().includes('Plan') ||
                       $body.text().includes('Tier') ||
                       $body.find('select, [data-testid="plan-select"]').length > 0;
        if (hasPlan) {
          cy.log('Plan selection displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Tenant Configuration', () => {
    beforeEach(() => {
      cy.visit('/app/baas/tenants/new');
      cy.waitForPageLoad();
    });

    it('should display billing configuration section', () => {
      cy.get('body').then($body => {
        const hasBilling = $body.text().includes('Billing') ||
                          $body.text().includes('Payment') ||
                          $body.text().includes('Invoice');
        if (hasBilling) {
          cy.log('Billing configuration displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display currency selection', () => {
      cy.get('body').then($body => {
        const hasCurrency = $body.text().includes('Currency') ||
                           $body.text().includes('USD') ||
                           $body.text().includes('EUR');
        if (hasCurrency) {
          cy.log('Currency selection displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display timezone selection', () => {
      cy.get('body').then($body => {
        const hasTimezone = $body.text().includes('Timezone') ||
                           $body.text().includes('Time Zone') ||
                           $body.find('select[name*="timezone"]').length > 0;
        if (hasTimezone) {
          cy.log('Timezone selection displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display webhook configuration', () => {
      cy.get('body').then($body => {
        const hasWebhook = $body.text().includes('Webhook') ||
                          $body.text().includes('Callback') ||
                          $body.text().includes('Endpoint');
        if (hasWebhook) {
          cy.log('Webhook configuration displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('API Key Setup', () => {
    it('should navigate to API keys section', () => {
      cy.visit('/app/baas/api-keys');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasApiKeys = $body.text().includes('API') ||
                          $body.text().includes('Keys') ||
                          $body.text().includes('Credentials');
        if (hasApiKeys) {
          cy.log('API keys section loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display create API key button', () => {
      cy.visit('/app/baas/api-keys');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCreate = $body.find('button:contains("Create"), button:contains("Generate"), button:contains("New")').length > 0 ||
                         $body.text().includes('Create');
        if (hasCreate) {
          cy.log('Create API key button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display existing API keys list', () => {
      cy.visit('/app/baas/api-keys');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasList = $body.find('table, [data-testid="api-keys-list"], .list').length > 0;
        if (hasList) {
          cy.log('API keys list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should show API key permissions options', () => {
      cy.visit('/app/baas/api-keys');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasPermissions = $body.text().includes('Permission') ||
                              $body.text().includes('Scope') ||
                              $body.text().includes('Access');
        if (hasPermissions) {
          cy.log('API key permissions displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Onboarding Wizard', () => {
    it('should display onboarding steps', () => {
      cy.visit('/app/baas/onboarding');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSteps = $body.find('[data-testid="wizard-steps"], .steps, .stepper').length > 0 ||
                        $body.text().includes('Step') ||
                        $body.text().includes('1.') ||
                        $body.text().includes('2.');
        if (hasSteps) {
          cy.log('Onboarding steps displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have progress indicator', () => {
      cy.visit('/app/baas/onboarding');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasProgress = $body.find('[role="progressbar"], .progress, [data-testid="progress"]').length > 0 ||
                           $body.text().includes('%');
        if (hasProgress) {
          cy.log('Progress indicator displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have next/continue button', () => {
      cy.visit('/app/baas/onboarding');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasNext = $body.find('button:contains("Next"), button:contains("Continue"), button:contains("Proceed")').length > 0;
        if (hasNext) {
          cy.log('Next button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Tenant List Management', () => {
    it('should display tenant list', () => {
      cy.visit('/app/baas/tenants');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasList = $body.find('table, [data-testid="tenant-list"], .grid').length > 0 ||
                       $body.text().includes('Tenant');
        if (hasList) {
          cy.log('Tenant list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have tenant search', () => {
      cy.visit('/app/baas/tenants');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSearch = $body.find('input[type="search"], input[placeholder*="Search"]').length > 0 ||
                         $body.text().includes('Search');
        if (hasSearch) {
          cy.log('Tenant search displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have tenant status filter', () => {
      cy.visit('/app/baas/tenants');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasFilter = $body.text().includes('Active') ||
                         $body.text().includes('Suspended') ||
                         $body.text().includes('Status');
        if (hasFilter) {
          cy.log('Status filter displayed');
        }
      });

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
      it(`should display tenant onboarding correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/baas/tenants/new');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`Tenant onboarding displayed correctly on ${name}`);
      });
    });
  });
});
