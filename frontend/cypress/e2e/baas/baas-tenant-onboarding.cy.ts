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
      cy.assertContainsAny(['Create', 'New Tenant', 'Onboard']);
    });

    it('should display tenant creation form', () => {
      cy.visit('/app/baas/tenants/new');
      cy.waitForPageLoad();
      cy.assertHasElement(['form', '[data-testid="tenant-form"]']);
    });

    it('should have tenant name field', () => {
      cy.visit('/app/baas/tenants/new');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Tenant Name', 'Name']);
    });

    it('should have domain/subdomain field', () => {
      cy.visit('/app/baas/tenants/new');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Domain', 'Subdomain']);
    });

    it('should have plan selection', () => {
      cy.visit('/app/baas/tenants/new');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Plan', 'Tier']);
    });
  });

  describe('Tenant Configuration', () => {
    beforeEach(() => {
      cy.visit('/app/baas/tenants/new');
      cy.waitForPageLoad();
    });

    it('should display billing configuration section', () => {
      cy.assertContainsAny(['Billing', 'Payment', 'Invoice']);
    });

    it('should display currency selection', () => {
      cy.assertContainsAny(['Currency', 'USD', 'EUR']);
    });

    it('should display timezone selection', () => {
      cy.assertContainsAny(['Timezone', 'Time Zone']);
    });

    it('should display webhook configuration', () => {
      cy.assertContainsAny(['Webhook', 'Callback', 'Endpoint']);
    });
  });

  describe('API Key Setup', () => {
    it('should navigate to API keys section', () => {
      cy.visit('/app/baas/api-keys');
      cy.waitForPageLoad();
      cy.assertContainsAny(['API', 'Keys', 'Credentials']);
    });

    it('should display create API key button', () => {
      cy.visit('/app/baas/api-keys');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Create']);
    });

    it('should display existing API keys list', () => {
      cy.visit('/app/baas/api-keys');
      cy.waitForPageLoad();
      cy.assertHasElement(['table', '[data-testid="api-keys-list"]', '.list']);
    });

    it('should show API key permissions options', () => {
      cy.visit('/app/baas/api-keys');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Permission', 'Scope', 'Access']);
    });
  });

  describe('Onboarding Wizard', () => {
    it('should display onboarding steps', () => {
      cy.visit('/app/baas/onboarding');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Step', '1.', '2.']);
    });

    it('should have progress indicator', () => {
      cy.visit('/app/baas/onboarding');
      cy.waitForPageLoad();
      cy.assertContainsAny(['%']);
    });

    it('should have next/continue button', () => {
      cy.visit('/app/baas/onboarding');
      cy.waitForPageLoad();
      cy.assertHasElement(['button:contains("Next")', 'button:contains("Continue")', 'button:contains("Proceed")']);
    });
  });

  describe('Tenant List Management', () => {
    it('should display tenant list', () => {
      cy.visit('/app/baas/tenants');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Tenant']);
    });

    it('should have tenant search', () => {
      cy.visit('/app/baas/tenants');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Search']);
    });

    it('should have tenant status filter', () => {
      cy.visit('/app/baas/tenants');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Active', 'Suspended', 'Status']);
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

        cy.assertContainsAny(['Tenant', 'Onboarding', 'BaaS']);
        cy.log(`Tenant onboarding displayed correctly on ${name}`);
      });
    });
  });
});
