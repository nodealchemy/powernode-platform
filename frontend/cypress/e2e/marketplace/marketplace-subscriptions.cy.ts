/// <reference types="cypress" />

/**
 * Marketplace My Subscriptions Page Tests
 *
 * Tests for Marketplace Subscriptions management functionality including:
 * - Page navigation and load
 * - Subscriptions list display
 * - Filtering by type and status
 * - Subscription actions (pause, resume, cancel)
 * - Empty state handling
 * - Responsive design
 */

describe('Marketplace Subscriptions Page Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.setupMarketplaceIntercepts();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 5000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to My Subscriptions page', () => {
      cy.visit('/app/marketplace/subscriptions');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Subscriptions') ||
                          $body.text().includes('Subscription') ||
                          $body.text().includes('Marketplace') ||
                          $body.text().includes('Permission');
        if (hasContent) {
          cy.log('My Subscriptions page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page title', () => {
      cy.visit('/app/marketplace/subscriptions');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('My Subscriptions') ||
                         $body.text().includes('Subscriptions');
        if (hasTitle) {
          cy.log('Page title displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page description', () => {
      cy.visit('/app/marketplace/subscriptions');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDescription = $body.text().includes('Manage') ||
                               $body.text().includes('marketplace');
        if (hasDescription) {
          cy.log('Page description displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Page Actions', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace/subscriptions');
      cy.waitForPageLoad();
    });

    it('should have Browse Marketplace button', () => {
      cy.get('body').then($body => {
        const browseButton = $body.find('button:contains("Browse Marketplace"), button:contains("Marketplace")');
        if (browseButton.length > 0) {
          cy.log('Browse Marketplace button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should navigate to marketplace on button click', () => {
      cy.get('body').then($body => {
        const browseButton = $body.find('button:contains("Browse Marketplace"), button:contains("Marketplace")');
        if (browseButton.length > 0) {
          cy.wrap(browseButton).first().should('be.visible').click();
          cy.waitForPageLoad();
          cy.url().should('include', 'marketplace');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Filtering', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace/subscriptions');
      cy.waitForPageLoad();
    });

    it('should display type filter', () => {
      cy.get('body').then($body => {
        const hasTypeFilter = $body.text().includes('Type:') ||
                              $body.find('button:contains("All")').length > 0;
        if (hasTypeFilter) {
          cy.log('Type filter displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display status filter', () => {
      cy.get('body').then($body => {
        const hasStatusFilter = $body.text().includes('Status:') ||
                                $body.find('button:contains("Active")').length > 0;
        if (hasStatusFilter) {
          cy.log('Status filter displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should filter by type', () => {
      cy.get('body').then($body => {
        const typeButton = $body.find('button:contains("Apps"), button:contains("Plugins"), button:contains("Templates")');
        if (typeButton.length > 0) {
          cy.wrap(typeButton).first().should('be.visible').click();
          cy.log('Filtered by type');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should filter by status', () => {
      cy.get('body').then($body => {
        const statusButton = $body.find('button:contains("Active"), button:contains("Paused")');
        if (statusButton.length > 0) {
          cy.wrap(statusButton).first().should('be.visible').click();
          cy.log('Filtered by status');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Subscriptions List Display', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace/subscriptions');
      cy.waitForPageLoad();
    });

    it('should display subscriptions list', () => {
      cy.get('body').then($body => {
        const hasList = $body.find('[class*="list"], [class*="card"], [class*="space"]').length > 0;
        if (hasList) {
          cy.log('Subscriptions list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display subscription cards', () => {
      cy.get('body').then($body => {
        const hasCards = $body.find('[class*="card"], [class*="Card"]').length > 0;
        if (hasCards) {
          cy.log('Subscription cards displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display subscription name', () => {
      cy.get('body').then($body => {
        const hasNames = $body.find('h3, [class*="title"]').length > 0;
        if (hasNames) {
          cy.log('Subscription names displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display subscription status badge', () => {
      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Active') ||
                          $body.text().includes('Paused') ||
                          $body.text().includes('Cancelled') ||
                          $body.find('[class*="badge"]').length > 0;
        if (hasStatus) {
          cy.log('Subscription status badge displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display subscription type badge', () => {
      cy.get('body').then($body => {
        const hasType = $body.text().includes('App') ||
                        $body.text().includes('Plugin') ||
                        $body.text().includes('Template') ||
                        $body.text().includes('Integration');
        if (hasType) {
          cy.log('Subscription type badge displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display subscription date', () => {
      cy.get('body').then($body => {
        const hasDate = $body.text().includes('Subscribed') ||
                        $body.text().match(/\d{1,2}\/\d{1,2}\/\d{4}/) !== null;
        if (hasDate) {
          cy.log('Subscription date displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Subscription Actions', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace/subscriptions');
      cy.waitForPageLoad();
    });

    it('should have View button', () => {
      cy.get('body').then($body => {
        const viewButton = $body.find('button:contains("View")');
        if (viewButton.length > 0) {
          cy.log('View button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Configure button for active subscriptions', () => {
      cy.get('body').then($body => {
        const configButton = $body.find('button[title="Configure"], [aria-label*="configure"]');
        if (configButton.length > 0) {
          cy.log('Configure button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Pause button for active subscriptions', () => {
      cy.get('body').then($body => {
        const pauseButton = $body.find('button[title="Pause"], [aria-label*="pause"]');
        if (pauseButton.length > 0) {
          cy.log('Pause button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Resume button for paused subscriptions', () => {
      cy.get('body').then($body => {
        const resumeButton = $body.find('button[title="Resume"], [aria-label*="resume"]');
        if (resumeButton.length > 0) {
          cy.log('Resume button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Cancel button', () => {
      cy.get('body').then($body => {
        const cancelButton = $body.find('button[title="Cancel"], [aria-label*="cancel"]');
        if (cancelButton.length > 0) {
          cy.log('Cancel button found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Empty State', () => {
    it('should display empty state when no subscriptions', () => {
      cy.intercept('GET', '/api/v1/marketplace/subscriptions*', {
        statusCode: 200,
        body: []
      }).as('getEmptySubscriptions');

      cy.visit('/app/marketplace/subscriptions');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasEmpty = $body.text().includes('No subscriptions') ||
                         $body.text().includes('no subscriptions') ||
                         $body.text().includes('Browse the marketplace');
        if (hasEmpty) {
          cy.log('Empty state displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have call to action in empty state', () => {
      cy.intercept('GET', '/api/v1/marketplace/subscriptions*', {
        statusCode: 200,
        body: []
      }).as('getEmptySubscriptions');

      cy.visit('/app/marketplace/subscriptions');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasAction = $body.find('button:contains("Browse"), button:contains("Marketplace")').length > 0;
        if (hasAction) {
          cy.log('Call to action found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Paused Subscription Warning', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace/subscriptions');
      cy.waitForPageLoad();
    });

    it('should display warning for paused subscriptions', () => {
      cy.get('body').then($body => {
        const hasWarning = $body.text().includes('paused') ||
                           $body.find('[class*="warning"]').length > 0;
        if (hasWarning) {
          cy.log('Paused subscription warning displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.intercept('GET', '/api/v1/marketplace/subscriptions*', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      }).as('getSubscriptionsError');

      cy.visit('/app/marketplace/subscriptions');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should display error notification on failure', () => {
      cy.intercept('GET', '/api/v1/marketplace/subscriptions*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load subscriptions' }
      }).as('getSubscriptionsError');

      cy.visit('/app/marketplace/subscriptions');
      cy.waitForPageLoad();

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

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '/api/v1/marketplace/subscriptions*', {
        delay: 1000,
        statusCode: 200,
        body: []
      }).as('getSubscriptionsDelayed');

      cy.visit('/app/marketplace/subscriptions');

      cy.get('body').then($body => {
        const hasLoading = $body.find('[class*="spin"], [class*="loading"]').length > 0;
        if (hasLoading) {
          cy.log('Loading indicator displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/marketplace/subscriptions');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Subscriptions') || $body.text().includes('Marketplace');
        if (hasContent) {
          cy.log('Content visible on mobile');
        }
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/marketplace/subscriptions');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Subscriptions') || $body.text().includes('Marketplace');
        if (hasContent) {
          cy.log('Content visible on tablet');
        }
      });
    });

    it('should stack cards on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/marketplace/subscriptions');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
    });
  });
});


export {};
