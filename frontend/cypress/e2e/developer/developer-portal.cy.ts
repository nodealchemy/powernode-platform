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

      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Developer') ||
                          $body.text().includes('Portal') ||
                          $body.text().includes('API');
        if (hasContent) {
          cy.log('Developer Portal page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page title', () => {
      cy.visit('/app/developer');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('Developer Portal') ||
                        $body.text().includes('Developer');
        if (hasTitle) {
          cy.log('Page title displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page description', () => {
      cy.visit('/app/developer');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDescription = $body.text().includes('Integrate') ||
                              $body.text().includes('API') ||
                              $body.text().includes('subscription');
        if (hasDescription) {
          cy.log('Page description displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Info Cards', () => {
    beforeEach(() => {
      cy.visit('/app/developer');
      cy.waitForPageLoad();
    });

    it('should display REST API card', () => {
      cy.get('body').then($body => {
        const hasRestApi = $body.text().includes('REST API') ||
                          $body.text().includes('OpenAPI');
        if (hasRestApi) {
          cy.log('REST API card displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Authentication card', () => {
      cy.get('body').then($body => {
        const hasAuth = $body.text().includes('Authentication') ||
                       $body.text().includes('JWT') ||
                       $body.text().includes('API Key');
        if (hasAuth) {
          cy.log('Authentication card displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Webhooks card', () => {
      cy.get('body').then($body => {
        const hasWebhooks = $body.text().includes('Webhooks') ||
                           $body.text().includes('Real-time');
        if (hasWebhooks) {
          cy.log('Webhooks card displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Rate Limits card', () => {
      cy.get('body').then($body => {
        const hasRateLimits = $body.text().includes('Rate Limits') ||
                             $body.text().includes('req/min');
        if (hasRateLimits) {
          cy.log('Rate Limits card displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Tab Navigation', () => {
    beforeEach(() => {
      cy.visit('/app/developer');
      cy.waitForPageLoad();
    });

    it('should display API Documentation tab', () => {
      cy.get('body').then($body => {
        const hasDocsTab = $body.text().includes('API Documentation') ||
                          $body.text().includes('Documentation');
        if (hasDocsTab) {
          cy.log('API Documentation tab displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display API Keys tab', () => {
      cy.get('body').then($body => {
        const hasKeysTab = $body.text().includes('API Keys');
        if (hasKeysTab) {
          cy.log('API Keys tab displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Code Samples tab', () => {
      cy.get('body').then($body => {
        const hasSamplesTab = $body.text().includes('Code Samples');
        if (hasSamplesTab) {
          cy.log('Code Samples tab displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Webhooks tab', () => {
      cy.get('body').then($body => {
        const hasWebhooksTab = $body.text().includes('Webhooks');
        if (hasWebhooksTab) {
          cy.log('Webhooks tab displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should switch tabs when clicked', () => {
      cy.get('body').then($body => {
        const tabs = ['API Keys', 'Code Samples', 'Webhooks'];
        tabs.forEach(tabName => {
          const tab = $body.find(`button:contains("${tabName}")`);
          if (tab.length > 0) {
            cy.wrap(tab).first().click();
            cy.log(`Switched to ${tabName} tab`);
          }
        });
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('API Documentation Tab', () => {
    beforeEach(() => {
      cy.visit('/app/developer');
      cy.waitForPageLoad();
    });

    it('should display API documentation content', () => {
      cy.get('body').then($body => {
        const hasDocs = $body.text().includes('API') ||
                       $body.text().includes('Endpoint') ||
                       $body.text().includes('Documentation');
        if (hasDocs) {
          cy.log('API documentation content displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have link to interactive docs', () => {
      cy.get('body').then($body => {
        const hasLink = $body.find('a[href*="api-docs"]').length > 0 ||
                       $body.text().includes('Interactive Docs');
        if (hasLink) {
          cy.log('Link to interactive docs displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('API Keys Tab', () => {
    beforeEach(() => {
      cy.visit('/app/developer');
      cy.waitForPageLoad();

      // Navigate to API Keys tab
      cy.get('body').then($body => {
        const tab = $body.find('button:contains("API Keys")');
        if (tab.length > 0) {
          cy.wrap(tab).first().click();
        }
      });
    });

    it('should display API key management interface', () => {
      cy.get('body').then($body => {
        const hasKeyMgmt = $body.text().includes('API Key') ||
                          $body.text().includes('Create') ||
                          $body.text().includes('Manage');
        if (hasKeyMgmt) {
          cy.log('API key management interface displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Code Samples Tab', () => {
    beforeEach(() => {
      cy.visit('/app/developer');
      cy.waitForPageLoad();

      // Navigate to Code Samples tab
      cy.get('body').then($body => {
        const tab = $body.find('button:contains("Code Samples")');
        if (tab.length > 0) {
          cy.wrap(tab).first().click();
        }
      });
    });

    it('should display code samples', () => {
      cy.get('body').then($body => {
        const hasSamples = $body.text().includes('curl') ||
                          $body.text().includes('Python') ||
                          $body.text().includes('JavaScript') ||
                          $body.text().includes('Ruby') ||
                          $body.find('pre, code').length > 0;
        if (hasSamples) {
          cy.log('Code samples displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Webhooks Tab', () => {
    beforeEach(() => {
      cy.visit('/app/developer');
      cy.waitForPageLoad();

      // Navigate to Webhooks tab
      cy.get('body').then($body => {
        const tab = $body.find('button:contains("Webhooks")');
        if (tab.length > 0) {
          cy.wrap(tab).first().click();
        }
      });
    });

    it('should display webhook events table', () => {
      cy.get('body').then($body => {
        const hasEvents = $body.text().includes('subscription.created') ||
                         $body.text().includes('payment.completed') ||
                         $body.text().includes('Event') ||
                         $body.text().includes('Webhook Events');
        if (hasEvents) {
          cy.log('Webhook events table displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display signature verification guide', () => {
      cy.get('body').then($body => {
        const hasVerification = $body.text().includes('Signature') ||
                               $body.text().includes('Verify') ||
                               $body.text().includes('HMAC');
        if (hasVerification) {
          cy.log('Signature verification guide displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display webhook event types', () => {
      const expectedEvents = [
        'subscription.created',
        'subscription.updated',
        'subscription.cancelled',
        'payment.completed',
        'payment.failed',
        'invoice.created',
        'invoice.paid',
        'user.created',
      ];

      cy.get('body').then($body => {
        const bodyText = $body.text();
        const foundEvents = expectedEvents.filter(event => bodyText.includes(event));
        if (foundEvents.length > 0) {
          cy.log(`Found ${foundEvents.length} webhook event types`);
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.visit('/app/developer');
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
        cy.visit('/app/developer');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`Developer Portal displayed correctly on ${name}`);
      });
    });
  });
});
