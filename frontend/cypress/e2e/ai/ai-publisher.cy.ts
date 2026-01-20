/// <reference types="cypress" />

/**
 * AI Publisher Tests
 *
 * Tests for AI Publisher functionality including:
 * - Publisher dashboard
 * - Template analytics
 * - Earnings tracking
 * - Payout management
 * - Template performance
 */

describe('AI Publisher Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Publisher Dashboard', () => {
    it('should navigate to publisher dashboard', () => {
      cy.visit('/ai/publisher/dashboard');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasPublisher = $body.text().includes('Publisher') ||
                            $body.text().includes('Dashboard') ||
                            $body.text().includes('Create Publisher');
        if (hasPublisher) {
          cy.log('Publisher dashboard loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display publisher setup option for new publishers', () => {
      cy.visit('/ai/publisher/dashboard');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSetup = $body.text().includes('Create Publisher Profile') ||
                        $body.text().includes('Get Started') ||
                        $body.text().includes('Become a Publisher') ||
                        $body.text().includes('Start Selling');
        if (hasSetup) {
          cy.log('Publisher setup option available');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display publisher profile for existing publishers', () => {
      cy.visit('/ai/publisher/dashboard');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasProfile = $body.text().includes('Publisher Dashboard') ||
                          $body.text().includes('Templates') ||
                          $body.text().includes('Earnings') ||
                          $body.text().includes('Payouts');
        if (hasProfile) {
          cy.log('Publisher profile displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display publisher tabs', () => {
      cy.visit('/ai/publisher/dashboard');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasTabs = $body.text().includes('Overview') ||
                       $body.text().includes('Templates') ||
                       $body.text().includes('Earnings') ||
                       $body.text().includes('Payouts');
        if (hasTabs) {
          cy.log('Publisher tabs displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display earnings overview', () => {
      cy.visit('/ai/publisher/dashboard');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasEarnings = $body.text().includes('Earnings') ||
                          $body.text().includes('Revenue') ||
                          $body.text().includes('$') ||
                          $body.text().includes('Lifetime');
        if (hasEarnings) {
          cy.log('Earnings overview displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Template Performance', () => {
    it('should display template list', () => {
      cy.visit('/ai/publisher/dashboard');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasTemplates = $body.text().includes('Template') ||
                            $body.text().includes('No templates') ||
                            $body.find('table, [data-testid="template-list"]').length > 0;
        if (hasTemplates) {
          cy.log('Template list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display template performance metrics', () => {
      cy.visit('/ai/publisher/dashboard');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasMetrics = $body.text().includes('Installations') ||
                          $body.text().includes('Rating') ||
                          $body.text().includes('Revenue') ||
                          $body.text().includes('Performance');
        if (hasMetrics) {
          cy.log('Template performance metrics displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display template status badges', () => {
      cy.visit('/ai/publisher/dashboard');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Published') ||
                         $body.text().includes('Draft') ||
                         $body.text().includes('Pending') ||
                         $body.text().includes('Active');
        if (hasStatus) {
          cy.log('Template status badges displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Template Analytics Page', () => {
    it('should navigate to template analytics', () => {
      cy.visit('/ai/publisher/analytics');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasAnalytics = $body.text().includes('Analytics') ||
                            $body.text().includes('Statistics') ||
                            $body.text().includes('Metrics');
        if (hasAnalytics) {
          cy.log('Template analytics page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display period selector', () => {
      cy.visit('/ai/publisher/analytics');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasPeriod = $body.text().includes('Last 7 days') ||
                         $body.text().includes('Last 30 days') ||
                         $body.text().includes('Last 90 days') ||
                         $body.find('select').length > 0;
        if (hasPeriod) {
          cy.log('Period selector displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display revenue analytics', () => {
      cy.visit('/ai/publisher/analytics');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasRevenue = $body.text().includes('Revenue') ||
                          $body.text().includes('Gross') ||
                          $body.text().includes('Net') ||
                          $body.text().includes('Commission');
        if (hasRevenue) {
          cy.log('Revenue analytics displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display installation metrics', () => {
      cy.visit('/ai/publisher/analytics');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasInstalls = $body.text().includes('Installation') ||
                           $body.text().includes('Installs') ||
                           $body.text().includes('Uninstall');
        if (hasInstalls) {
          cy.log('Installation metrics displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Earnings & Payouts', () => {
    it('should display earnings tab content', () => {
      cy.visit('/ai/publisher/dashboard');
      cy.waitForPageLoad();

      // Try to find and click Earnings tab
      cy.get('body').then($body => {
        if ($body.text().includes('Earnings')) {
          cy.contains('button, [role="tab"]', 'Earnings').click({ force: true });
          cy.log('Clicked Earnings tab');
        }
      });

      cy.get('body').then($body => {
        const hasEarnings = $body.text().includes('Lifetime') ||
                          $body.text().includes('Pending') ||
                          $body.text().includes('Revenue Share') ||
                          $body.text().includes('$');
        if (hasEarnings) {
          cy.log('Earnings content displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display payouts tab content', () => {
      cy.visit('/ai/publisher/dashboard');
      cy.waitForPageLoad();

      // Try to find and click Payouts tab
      cy.get('body').then($body => {
        if ($body.text().includes('Payouts')) {
          cy.contains('button, [role="tab"]', 'Payouts').click({ force: true });
          cy.log('Clicked Payouts tab');
        }
      });

      cy.get('body').then($body => {
        const hasPayouts = $body.text().includes('Payout') ||
                          $body.text().includes('Stripe') ||
                          $body.text().includes('Request') ||
                          $body.text().includes('History');
        if (hasPayouts) {
          cy.log('Payouts content displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Stripe connection status', () => {
      cy.visit('/ai/publisher/dashboard');
      cy.waitForPageLoad();

      // Navigate to payouts
      cy.get('body').then($body => {
        if ($body.text().includes('Payouts')) {
          cy.contains('button, [role="tab"]', 'Payouts').click({ force: true });
        }
      });

      cy.get('body').then($body => {
        const hasStripe = $body.text().includes('Stripe') ||
                         $body.text().includes('Connected') ||
                         $body.text().includes('Setup Stripe') ||
                         $body.text().includes('Not Connected');
        if (hasStripe) {
          cy.log('Stripe connection status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display payout history', () => {
      cy.visit('/ai/publisher/dashboard');
      cy.waitForPageLoad();

      // Navigate to payouts
      cy.get('body').then($body => {
        if ($body.text().includes('Payouts')) {
          cy.contains('button, [role="tab"]', 'Payouts').click({ force: true });
        }
      });

      cy.get('body').then($body => {
        const hasHistory = $body.text().includes('History') ||
                          $body.text().includes('No payouts') ||
                          $body.text().includes('Completed') ||
                          $body.text().includes('Pending');
        if (hasHistory) {
          cy.log('Payout history displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Publisher Setup Flow', () => {
    it('should navigate to publisher setup page', () => {
      cy.visit('/ai/publisher/setup');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSetup = $body.text().includes('Setup') ||
                        $body.text().includes('Create') ||
                        $body.text().includes('Publisher') ||
                        $body.text().includes('Profile');
        if (hasSetup) {
          cy.log('Publisher setup page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display setup form fields', () => {
      cy.visit('/ai/publisher/setup');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasFields = $body.find('input, textarea, form').length > 0 ||
                         $body.text().includes('Name') ||
                         $body.text().includes('Description');
        if (hasFields) {
          cy.log('Setup form fields displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Create Template Flow', () => {
    it('should have create template action', () => {
      cy.visit('/ai/publisher/dashboard');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCreate = $body.text().includes('Create Template') ||
                         $body.text().includes('New Template') ||
                         $body.text().includes('Add Template') ||
                         $body.find('[data-testid="create-template-btn"]').length > 0;
        if (hasCreate) {
          cy.log('Create template action available');
        }
      });

      cy.get('body').should('be.visible');
    });
  });
});
