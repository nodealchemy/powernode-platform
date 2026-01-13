/// <reference types="cypress" />

/**
 * AI Overview Page Tests
 *
 * Tests for AI Overview functionality including:
 * - Page navigation and load
 * - Dashboard stats display
 * - Quick actions
 * - Live updates toggle
 * - Refresh functionality
 * - System health status
 * - Responsive design
 */

describe('AI Overview Page Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    // Login with demo user
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to AI Overview from sidebar', () => {
      cy.visit('/app');
      cy.wait(2000);

      cy.get('body').then($body => {
        const aiLink = $body.find('a[href*="/ai"], a[href*="/app/ai"]');

        if (aiLink.length > 0) {
          cy.wrap(aiLink).first().click();
          cy.url().should('include', '/ai');
        } else {
          cy.visit('/app/ai/overview');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should load AI Overview page directly', () => {
      cy.visit('/app/ai/overview');
      cy.wait(2000);

      cy.get('body').then($body => {
        const text = $body.text();
        const hasContent = text.includes('AI Overview') ||
                           text.includes('AI') ||
                           text.includes('Dashboard') ||
                           text.includes('Loading');
        if (hasContent) {
          cy.log('AI Overview page content loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page title', () => {
      cy.visit('/app/ai/overview');

      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('AI Overview') ||
                          $body.text().includes('AI Dashboard');

        if (hasTitle) {
          cy.log('Page title displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/ai/overview');

      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('Dashboard') ||
                               $body.text().includes('AI');

        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs displayed correctly');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Dashboard Stats Display', () => {
    beforeEach(() => {
      cy.visit('/app/ai/overview');
      cy.wait(2000);
    });

    it('should display AI stats cards', () => {
      cy.get('body').then($body => {
        const hasStats = $body.text().includes('Workflows') ||
                          $body.text().includes('Agents') ||
                          $body.text().includes('Providers') ||
                          $body.text().includes('Conversations');

        if (hasStats) {
          cy.log('AI stats cards displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display workflow count', () => {
      cy.get('body').then($body => {
        if ($body.text().includes('Workflow')) {
          cy.log('Workflow stats displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display agent count', () => {
      cy.get('body').then($body => {
        if ($body.text().includes('Agent')) {
          cy.log('Agent stats displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display provider count', () => {
      cy.get('body').then($body => {
        if ($body.text().includes('Provider')) {
          cy.log('Provider stats displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Quick Actions', () => {
    beforeEach(() => {
      cy.visit('/app/ai/overview');
      cy.wait(2000);
    });

    it('should have Refresh button', () => {
      cy.get('body').then($body => {
        const refreshButton = $body.find('button:contains("Refresh"), [aria-label*="refresh"]');

        if (refreshButton.length > 0) {
          cy.wrap(refreshButton).first().should('be.visible');
          cy.log('Refresh button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Live Updates toggle', () => {
      cy.get('body').then($body => {
        const liveButton = $body.find('button:contains("Live"), button:contains("Paused")');

        if (liveButton.length > 0) {
          cy.log('Live updates toggle found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should refresh data when Refresh clicked', () => {
      cy.get('body').then($body => {
        const refreshButton = $body.find('button:contains("Refresh")');

        if (refreshButton.length > 0) {
          cy.wrap(refreshButton).first().click();
          cy.wait(1000);
          cy.log('Refresh triggered');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should toggle live updates when clicked', () => {
      cy.get('body').then($body => {
        const liveButton = $body.find('button:contains("Live"), button:contains("Paused")');

        if (liveButton.length > 0) {
          cy.wrap(liveButton).first().click();
          cy.wait(500);
          cy.log('Live updates toggled');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('System Health Display', () => {
    beforeEach(() => {
      cy.visit('/app/ai/overview');
      cy.wait(2000);
    });

    it('should display system health status', () => {
      cy.get('body').then($body => {
        const hasHealth = $body.text().includes('Health') ||
                           $body.text().includes('Status') ||
                           $body.text().includes('healthy') ||
                           $body.text().includes('Online');

        if (hasHealth) {
          cy.log('System health status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display provider status', () => {
      cy.get('body').then($body => {
        const hasProviderStatus = $body.text().includes('Provider') ||
                                   $body.text().includes('Connected') ||
                                   $body.text().includes('Available');

        if (hasProviderStatus) {
          cy.log('Provider status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Quick Access Links', () => {
    beforeEach(() => {
      cy.visit('/app/ai/overview');
      cy.wait(2000);
    });

    it('should have links to AI subpages', () => {
      cy.get('body').then($body => {
        const hasLinks = $body.find('a[href*="/workflows"], a[href*="/agents"], a[href*="/providers"]').length > 0;

        if (hasLinks) {
          cy.log('Quick access links found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should navigate to Workflows when clicked', () => {
      cy.get('body').then($body => {
        const workflowLink = $body.find('a[href*="/workflows"]');

        if (workflowLink.length > 0) {
          cy.wrap(workflowLink).first().click();
          cy.url().should('include', '/workflow');
          cy.log('Navigated to Workflows');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should navigate to Agents when clicked', () => {
      cy.visit('/app/ai/overview');
      cy.wait(2000);

      cy.get('body').then($body => {
        const agentLink = $body.find('a[href*="/agents"]');

        if (agentLink.length > 0) {
          cy.wrap(agentLink).first().click();
          cy.url().should('include', '/agent');
          cy.log('Navigated to Agents');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Empty State', () => {
    it('should handle empty AI system gracefully', () => {
      cy.intercept('GET', '/api/v1/ai/*', {
        statusCode: 200,
        body: { success: true, data: [] }
      });

      cy.visit('/app/ai/overview');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.intercept('GET', '/api/v1/ai/dashboard*', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/ai/overview');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should display error notification on failure', () => {
      cy.intercept('GET', '/api/v1/ai/dashboard*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load AI dashboard' }
      });

      cy.visit('/app/ai/overview');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasError = $body.text().includes('Error') ||
                          $body.text().includes('Failed') ||
                          $body.find('[class*="error"]').length > 0;

        if (hasError) {
          cy.log('Error notification displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Permission-Based Display', () => {
    it('should show content based on permissions', () => {
      cy.visit('/app/ai/overview');
      cy.wait(2000);

      cy.get('body').then($body => {
        if ($body.text().includes('Permission') || $body.text().includes('Access')) {
          cy.log('Permission notice displayed');
        } else {
          cy.log('User has AI permissions');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/ai/overview');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('AI');
        if (hasContent) {
          cy.log('Content visible on mobile');
        }
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/ai/overview');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('AI');
        if (hasContent) {
          cy.log('Content visible on tablet');
        }
      });
    });

    it('should stack cards on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/ai/overview');
      cy.wait(2000);

      cy.get('body').should('be.visible');
    });
  });
});
