/// <reference types="cypress" />

/**
 * Developer API Documentation Tests
 *
 * Tests for API Documentation functionality including:
 * - API reference navigation
 * - Endpoint documentation
 * - Request/Response examples
 * - Authentication docs
 * - Code samples
 * - Interactive testing
 */

describe('Developer API Documentation Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('API Documentation Access', () => {
    it('should navigate to API documentation', () => {
      cy.visit('/app/developer/docs');
      cy.waitForPageLoad();
      cy.assertContainsAny(['API', 'Documentation', 'Reference']);
    });

    it('should display documentation sidebar', () => {
      cy.visit('/app/developer/docs');
      cy.waitForPageLoad();
      cy.assertHasElement(['nav', 'aside', '[data-testid="docs-sidebar"]']);
    });

    it('should display search in documentation', () => {
      cy.visit('/app/developer/docs');
      cy.waitForPageLoad();
      cy.assertHasElement(['input[type="search"]', 'input[placeholder*="Search"]']);
    });
  });

  describe('Endpoint Categories', () => {
    beforeEach(() => {
      cy.visit('/app/developer/docs');
      cy.waitForPageLoad();
    });

    it('should display authentication endpoints', () => {
      cy.assertContainsAny(['Authentication', 'Auth', 'Login']);
    });

    it('should display subscriptions endpoints', () => {
      cy.assertContainsAny(['Subscription', 'subscriptions']);
    });

    it('should display billing endpoints', () => {
      cy.assertContainsAny(['Billing', 'Invoice', 'Payment']);
    });

    it('should display webhooks endpoints', () => {
      cy.assertContainsAny(['Webhook', 'webhook']);
    });
  });

  describe('Endpoint Documentation', () => {
    beforeEach(() => {
      cy.visit('/app/developer/docs');
      cy.waitForPageLoad();
    });

    it('should display HTTP methods', () => {
      cy.assertContainsAny(['GET', 'POST', 'PUT', 'DELETE']);
    });

    it('should display endpoint paths', () => {
      cy.assertContainsAny(['/api/', '/v1/']);
    });

    it('should display request parameters', () => {
      cy.assertContainsAny(['Parameter', 'Required', 'Optional']);
    });

    it('should display response schema', () => {
      cy.assertContainsAny(['Response', 'Returns', '200']);
    });
  });

  describe('Code Samples', () => {
    beforeEach(() => {
      cy.visit('/app/developer/docs');
      cy.waitForPageLoad();
    });

    it('should display code examples', () => {
      cy.assertHasElement(['pre', 'code', '[data-testid="code-block"]']);
    });

    it('should have language selector for code samples', () => {
      cy.assertContainsAny(['cURL', 'JavaScript', 'Python', 'Ruby']);
    });

    it('should have copy code button', () => {
      cy.assertHasElement(['button:contains("Copy")', '[data-testid="copy-button"]', '[aria-label*="copy"]']);
    });
  });

  describe('Authentication Documentation', () => {
    it('should navigate to authentication docs', () => {
      cy.visit('/app/developer/docs/authentication');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Authentication', 'API Key', 'Token']);
    });

    it('should display API key authentication', () => {
      cy.visit('/app/developer/docs/authentication');
      cy.waitForPageLoad();
      cy.assertContainsAny(['API Key', 'X-API-Key', 'Bearer']);
    });

    it('should display rate limiting info', () => {
      cy.visit('/app/developer/docs/authentication');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Rate', 'Limit', 'Throttl']);
    });
  });

  describe('Interactive API Explorer', () => {
    it('should navigate to API explorer', () => {
      cy.visit('/app/developer/explorer');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Explorer', 'Try', 'Test']);
    });

    it('should have request builder', () => {
      cy.visit('/app/developer/explorer');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Request', 'Builder', 'Endpoint']);
    });

    it('should have send request button', () => {
      cy.visit('/app/developer/explorer');
      cy.waitForPageLoad();
      cy.assertHasElement(['button:contains("Send")', 'button:contains("Execute")', 'button:contains("Try")']);
    });
  });

  describe('Responsive Design', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display API docs correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/developer/docs');
        cy.waitForPageLoad();

        cy.assertContainsAny(['API', 'Documentation', 'Developer']);
        cy.log(`API docs displayed correctly on ${name}`);
      });
    });
  });
});
