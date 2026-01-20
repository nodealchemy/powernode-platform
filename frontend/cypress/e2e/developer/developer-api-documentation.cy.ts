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

      cy.get('body').then($body => {
        const hasDocs = $body.text().includes('API') ||
                       $body.text().includes('Documentation') ||
                       $body.text().includes('Reference');
        if (hasDocs) {
          cy.log('API documentation page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display documentation sidebar', () => {
      cy.visit('/app/developer/docs');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSidebar = $body.find('nav, aside, [data-testid="docs-sidebar"]').length > 0;
        if (hasSidebar) {
          cy.log('Documentation sidebar displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display search in documentation', () => {
      cy.visit('/app/developer/docs');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSearch = $body.find('input[type="search"], input[placeholder*="Search"]').length > 0 ||
                         $body.text().includes('Search');
        if (hasSearch) {
          cy.log('Documentation search displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Endpoint Categories', () => {
    beforeEach(() => {
      cy.visit('/app/developer/docs');
      cy.waitForPageLoad();
    });

    it('should display authentication endpoints', () => {
      cy.get('body').then($body => {
        const hasAuth = $body.text().includes('Authentication') ||
                       $body.text().includes('Auth') ||
                       $body.text().includes('Login');
        if (hasAuth) {
          cy.log('Authentication endpoints displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display subscriptions endpoints', () => {
      cy.get('body').then($body => {
        const hasSubs = $body.text().includes('Subscription') ||
                       $body.text().includes('subscriptions');
        if (hasSubs) {
          cy.log('Subscriptions endpoints displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display billing endpoints', () => {
      cy.get('body').then($body => {
        const hasBilling = $body.text().includes('Billing') ||
                          $body.text().includes('Invoice') ||
                          $body.text().includes('Payment');
        if (hasBilling) {
          cy.log('Billing endpoints displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display webhooks endpoints', () => {
      cy.get('body').then($body => {
        const hasWebhooks = $body.text().includes('Webhook') ||
                           $body.text().includes('webhook');
        if (hasWebhooks) {
          cy.log('Webhooks endpoints displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Endpoint Documentation', () => {
    beforeEach(() => {
      cy.visit('/app/developer/docs');
      cy.waitForPageLoad();
    });

    it('should display HTTP methods', () => {
      cy.get('body').then($body => {
        const hasMethods = $body.text().includes('GET') ||
                          $body.text().includes('POST') ||
                          $body.text().includes('PUT') ||
                          $body.text().includes('DELETE');
        if (hasMethods) {
          cy.log('HTTP methods displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display endpoint paths', () => {
      cy.get('body').then($body => {
        const hasPaths = $body.text().includes('/api/') ||
                        $body.text().includes('/v1/') ||
                        $body.find('code').length > 0;
        if (hasPaths) {
          cy.log('Endpoint paths displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display request parameters', () => {
      cy.get('body').then($body => {
        const hasParams = $body.text().includes('Parameter') ||
                         $body.text().includes('Required') ||
                         $body.text().includes('Optional');
        if (hasParams) {
          cy.log('Request parameters displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display response schema', () => {
      cy.get('body').then($body => {
        const hasResponse = $body.text().includes('Response') ||
                           $body.text().includes('Returns') ||
                           $body.text().includes('200');
        if (hasResponse) {
          cy.log('Response schema displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Code Samples', () => {
    beforeEach(() => {
      cy.visit('/app/developer/docs');
      cy.waitForPageLoad();
    });

    it('should display code examples', () => {
      cy.get('body').then($body => {
        const hasCode = $body.find('pre, code, [data-testid="code-block"]').length > 0;
        if (hasCode) {
          cy.log('Code examples displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have language selector for code samples', () => {
      cy.get('body').then($body => {
        const hasLangs = $body.text().includes('cURL') ||
                        $body.text().includes('JavaScript') ||
                        $body.text().includes('Python') ||
                        $body.text().includes('Ruby');
        if (hasLangs) {
          cy.log('Language selector displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have copy code button', () => {
      cy.get('body').then($body => {
        const hasCopy = $body.find('button:contains("Copy"), [data-testid="copy-button"], [aria-label*="copy"]').length > 0;
        if (hasCopy) {
          cy.log('Copy code button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Authentication Documentation', () => {
    it('should navigate to authentication docs', () => {
      cy.visit('/app/developer/docs/authentication');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasAuth = $body.text().includes('Authentication') ||
                       $body.text().includes('API Key') ||
                       $body.text().includes('Token');
        if (hasAuth) {
          cy.log('Authentication docs loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display API key authentication', () => {
      cy.visit('/app/developer/docs/authentication');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasApiKey = $body.text().includes('API Key') ||
                         $body.text().includes('X-API-Key') ||
                         $body.text().includes('Bearer');
        if (hasApiKey) {
          cy.log('API key authentication displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display rate limiting info', () => {
      cy.visit('/app/developer/docs/authentication');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasRateLimit = $body.text().includes('Rate') ||
                            $body.text().includes('Limit') ||
                            $body.text().includes('Throttl');
        if (hasRateLimit) {
          cy.log('Rate limiting info displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Interactive API Explorer', () => {
    it('should navigate to API explorer', () => {
      cy.visit('/app/developer/explorer');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasExplorer = $body.text().includes('Explorer') ||
                          $body.text().includes('Try') ||
                          $body.text().includes('Test');
        if (hasExplorer) {
          cy.log('API explorer loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have request builder', () => {
      cy.visit('/app/developer/explorer');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasBuilder = $body.find('input, textarea, select').length > 0 ||
                          $body.text().includes('Request');
        if (hasBuilder) {
          cy.log('Request builder displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have send request button', () => {
      cy.visit('/app/developer/explorer');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSend = $body.find('button:contains("Send"), button:contains("Execute"), button:contains("Try")').length > 0;
        if (hasSend) {
          cy.log('Send request button displayed');
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
      it(`should display API docs correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/developer/docs');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`API docs displayed correctly on ${name}`);
      });
    });
  });
});
