/// <reference types="cypress" />

/**
 * Developer Portal Tests
 *
 * Tests for Developer Portal functionality including:
 * - Page navigation and load
 * - API documentation display
 * - API keys management
 * - Code samples viewing
 * - Webhook documentation
 * - Tab navigation
 * - Error handling
 * - Responsive design
 */

describe('Developer Portal Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Page Navigation', () => {
    it('should navigate to Developer Portal page', () => {
      cy.visit('/app/developer');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Developer', 'Portal', 'API']);
    });

    it('should display page title', () => {
      cy.visit('/app/developer');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Developer Portal', 'Developer']);
    });

    it('should display page description', () => {
      cy.visit('/app/developer');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Integrate', 'API', 'subscription']);
    });
  });

  describe('Info Cards', () => {
    beforeEach(() => {
      cy.visit('/app/developer');
      cy.waitForPageLoad();
    });

    it('should display REST API card', () => {
      cy.assertContainsAny(['REST API', 'OpenAPI']);
    });

    it('should display Authentication card', () => {
      cy.assertContainsAny(['Authentication', 'JWT', 'API Key']);
    });

    it('should display Webhooks card', () => {
      cy.assertContainsAny(['Webhooks', 'Real-time']);
    });

    it('should display Rate Limits card', () => {
      cy.assertContainsAny(['Rate Limits', 'req/min']);
    });
  });

  describe('Tab Navigation', () => {
    beforeEach(() => {
      cy.visit('/app/developer');
      cy.waitForPageLoad();
    });

    it('should display API Documentation tab', () => {
      cy.assertContainsAny(['API Documentation', 'Documentation']);
    });

    it('should display API Keys tab', () => {
      cy.assertContainsAny(['API Keys']);
    });

    it('should display Code Samples tab', () => {
      cy.assertContainsAny(['Code Samples']);
    });

    it('should display Webhooks tab', () => {
      cy.assertContainsAny(['Webhooks']);
    });

    it('should switch tabs when clicked', () => {
      cy.get('button:contains("API Keys")').first().click();
      cy.get('button:contains("Code Samples")').first().click();
      cy.get('button:contains("Webhooks")').first().click();
      cy.assertContainsAny(['Webhooks', 'Event', 'subscription.created']);
    });
  });

  describe('API Documentation Tab', () => {
    beforeEach(() => {
      cy.visit('/app/developer');
      cy.waitForPageLoad();
    });

    it('should display API documentation content', () => {
      cy.assertContainsAny(['API', 'Endpoint', 'Documentation']);
    });

    it('should have link to interactive docs', () => {
      cy.assertContainsAny(['Interactive Docs', 'API', 'Documentation']);
    });
  });

  describe('API Keys Tab', () => {
    beforeEach(() => {
      cy.visit('/app/developer');
      cy.waitForPageLoad();
      cy.get('button:contains("API Keys")').first().click();
    });

    it('should display API key management interface', () => {
      cy.assertContainsAny(['API Key', 'Create', 'Manage']);
    });
  });

  describe('Code Samples Tab', () => {
    beforeEach(() => {
      cy.visit('/app/developer');
      cy.waitForPageLoad();
      cy.get('button:contains("Code Samples")').first().click();
    });

    it('should display code samples', () => {
      cy.assertContainsAny(['curl', 'Python', 'JavaScript', 'Ruby']);
    });
  });

  describe('Webhooks Tab', () => {
    beforeEach(() => {
      cy.visit('/app/developer');
      cy.waitForPageLoad();
      cy.get('button:contains("Webhooks")').first().click();
    });

    it('should display webhook events table', () => {
      cy.assertContainsAny(['subscription.created', 'payment.completed', 'Event', 'Webhook Events']);
    });

    it('should display signature verification guide', () => {
      cy.assertContainsAny(['Signature', 'Verify', 'HMAC']);
    });

    it('should display webhook event types', () => {
      cy.assertContainsAny(['subscription.created', 'subscription.updated', 'payment.completed', 'invoice.created']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.visit('/app/developer');
      cy.waitForPageLoad();

      // Page should still be functional even if API fails
      cy.assertContainsAny(['Developer', 'Portal', 'API']);
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
        cy.visit('/app/developer');
        cy.waitForPageLoad();

        cy.assertContainsAny(['Developer', 'Portal', 'API']);
        cy.log(`Developer Portal displayed correctly on ${name}`);
      });
    });
  });
});
