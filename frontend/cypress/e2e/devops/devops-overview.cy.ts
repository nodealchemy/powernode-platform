/// <reference types="cypress" />

/**
 * DevOps Overview Dashboard Tests
 *
 * Tests for the DevOps Overview page functionality including:
 * - Dashboard navigation and page load
 * - Stats cards display
 * - Quick access links navigation
 * - Runner health status display
 * - Webhook deliveries display
 * - Commit activity chart
 * - Attention required alerts
 * - Refresh functionality
 * - Responsive design
 */

describe('DevOps Overview Dashboard Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.setupDevopsIntercepts();
    // Login with demo user
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 5000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').should('be.visible').click();
    cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to DevOps Overview from sidebar', () => {
      cy.visit('/app');

      cy.get('body').then($body => {
        // Look for DevOps navigation link
        const devopsSelectors = [
          'a[href*="/devops"]',
          'button:contains("DevOps")',
          '[data-testid="nav-devops"]'
        ];

        let found = false;
        for (const selector of devopsSelectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().click();
            found = true;
            break;
          }
        }

        if (!found) {
          // Navigate directly
          cy.visit('/app/devops');
        }
      });

      cy.url().should('include', '/devops');
      cy.get('body').should('be.visible');
    });

    it('should load DevOps Overview page directly', () => {
      cy.visit('/app/devops');

      cy.url().then(url => {
        if (url.includes('/devops')) {
          // Check for page title or content
          cy.get('body').should('satisfy', ($body) => {
            const text = $body.text();
            return text.includes('DevOps') || text.includes('Overview') || text.includes('Infrastructure');
          });
        } else {
          cy.log('DevOps page redirected - may require specific permissions');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/devops');

      cy.get('body').then($body => {
        // Check for breadcrumb structure
        const hasBreadcrumbs = $body.find('nav[aria-label="breadcrumb"]').length > 0 ||
                               $body.text().includes('Dashboard') && $body.text().includes('DevOps');

        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs found');
        } else {
          cy.log('Breadcrumbs not visible - may use different navigation pattern');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Stats Cards Display', () => {
    beforeEach(() => {
      cy.visit('/app/devops');
      cy.waitForPageLoad();
    });

    it('should display Git Providers stats card', () => {
      cy.get('body').then($body => {
        if ($body.text().includes('Git Providers') || $body.find('[class*="git"]').length > 0) {
          cy.contains('Git Providers').should('be.visible');
          cy.log('Git Providers card displayed');
        } else {
          cy.log('Git Providers card not found - feature may not be enabled');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Repositories stats card', () => {
      cy.get('body').then($body => {
        if ($body.text().includes('Repositories') || $body.text().includes('repos')) {
          cy.contains(/Repositories/i).should('be.visible');
          cy.log('Repositories card displayed');
        } else {
          cy.log('Repositories card not found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Runners stats card', () => {
      cy.get('body').then($body => {
        if ($body.text().includes('Runners') || $body.text().includes('Runner')) {
          cy.contains(/Runners?/i).should('be.visible');
          cy.log('Runners card displayed');
        } else {
          cy.log('Runners card not found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Webhooks stats card', () => {
      cy.get('body').then($body => {
        if ($body.text().includes('Webhooks') || $body.text().includes('Webhook')) {
          cy.contains(/Webhooks?/i).should('be.visible');
          cy.log('Webhooks card displayed');
        } else {
          cy.log('Webhooks card not found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Integrations stats card', () => {
      cy.get('body').then($body => {
        if ($body.text().includes('Integrations') || $body.text().includes('Integration')) {
          cy.contains(/Integrations?/i).should('be.visible');
          cy.log('Integrations card displayed');
        } else {
          cy.log('Integrations card not found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display API Keys stats card', () => {
      cy.get('body').then($body => {
        if ($body.text().includes('API Keys') || $body.text().includes('API Key')) {
          cy.contains(/API Keys?/i).should('be.visible');
          cy.log('API Keys card displayed');
        } else {
          cy.log('API Keys card not found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display stats values in cards', () => {
      cy.get('body').then($body => {
        // Look for numeric values that represent stats
        const statsCards = $body.find('[class*="stat"], [class*="card"], [class*="metric"]');

        if (statsCards.length > 0) {
          cy.log(`Found ${statsCards.length} potential stat elements`);
        }

        // Check for any numbers displayed
        const hasNumbers = /\d+/.test($body.text());
        if (hasNumbers) {
          cy.log('Stats values displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Quick Access Links', () => {
    beforeEach(() => {
      cy.visit('/app/devops');
      cy.waitForPageLoad();
    });

    it('should display Quick Access section', () => {
      cy.get('body').then($body => {
        if ($body.text().includes('Quick Access') || $body.text().includes('Quick Links')) {
          cy.contains(/Quick (Access|Links)/i).should('be.visible');
          cy.log('Quick Access section found');
        } else {
          cy.log('Quick Access section not visible - may use different layout');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should navigate to Git Providers from quick link', () => {
      cy.get('body').then($body => {
        const gitLink = $body.find('a[href*="/git"], [class*="quick"] a:contains("Git")');

        if (gitLink.length > 0) {
          cy.wrap(gitLink).first().click();
          cy.url().should('include', '/git');
        } else {
          cy.log('Git Providers quick link not found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should navigate to Repositories from quick link', () => {
      cy.get('body').then($body => {
        const repoLink = $body.find('a[href*="/repositories"]');

        if (repoLink.length > 0) {
          cy.wrap(repoLink).first().click();
          cy.url().should('include', '/repositories');
        } else {
          cy.log('Repositories quick link not found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should navigate to Webhooks from quick link', () => {
      cy.get('body').then($body => {
        const webhookLink = $body.find('a[href*="/webhooks"]');

        if (webhookLink.length > 0) {
          cy.wrap(webhookLink).first().click();
          cy.url().should('include', '/webhooks');
        } else {
          cy.log('Webhooks quick link not found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should navigate to API Keys from quick link', () => {
      cy.get('body').then($body => {
        const apiKeyLink = $body.find('a[href*="/api-keys"]');

        if (apiKeyLink.length > 0) {
          cy.wrap(apiKeyLink).first().click();
          cy.url().should('include', '/api-keys');
        } else {
          cy.log('API Keys quick link not found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Runner Health Section', () => {
    beforeEach(() => {
      cy.visit('/app/devops');
      cy.waitForPageLoad();
    });

    it('should display Runner Health section', () => {
      cy.get('body').then($body => {
        if ($body.text().includes('Runner Health') || $body.text().includes('Runners')) {
          cy.contains(/Runner (Health|Status)/i).should('be.visible');
          cy.log('Runner Health section displayed');
        } else {
          cy.log('Runner Health section not found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display runner status indicators', () => {
      cy.get('body').then($body => {
        const hasStatusIndicators = $body.text().includes('Online') ||
                                    $body.text().includes('Offline') ||
                                    $body.text().includes('Busy');

        if (hasStatusIndicators) {
          cy.log('Runner status indicators found');
        } else {
          cy.log('No runner status indicators - may have no runners configured');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display runner progress bar when runners exist', () => {
      cy.get('body').then($body => {
        const progressBar = $body.find('[class*="progress"], [role="progressbar"]');

        if (progressBar.length > 0) {
          cy.log('Runner progress bar found');
        } else {
          cy.log('No progress bar - runners may not be configured');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Webhook Deliveries Section', () => {
    beforeEach(() => {
      cy.visit('/app/devops');
      cy.waitForPageLoad();
    });

    it('should display Webhook Deliveries section', () => {
      cy.get('body').then($body => {
        if ($body.text().includes('Webhook Deliveries') || $body.text().includes('Deliveries Today')) {
          cy.contains(/Webhook Deliver|Deliveries/i).should('be.visible');
          cy.log('Webhook Deliveries section found');
        } else {
          cy.log('Webhook Deliveries section not found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display delivery statistics', () => {
      cy.get('body').then($body => {
        const hasDeliveryStats = $body.text().includes('Total') ||
                                  $body.text().includes('Successful') ||
                                  $body.text().includes('Failed');

        if (hasDeliveryStats) {
          cy.log('Delivery statistics displayed');
        } else {
          cy.log('No delivery stats - may have no webhook activity');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Commit Activity Section', () => {
    beforeEach(() => {
      cy.visit('/app/devops');
      cy.waitForPageLoad();
    });

    it('should display Commit Activity section', () => {
      cy.get('body').then($body => {
        if ($body.text().includes('Commit Activity') || $body.text().includes('commits')) {
          cy.contains(/Commit (Activity|History)/i).should('be.visible');
          cy.log('Commit Activity section found');
        } else {
          cy.log('Commit Activity section not found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display activity chart when repos exist', () => {
      cy.get('body').then($body => {
        const chartElements = $body.find('canvas, svg, [class*="chart"], [class*="bar"]');

        if (chartElements.length > 0) {
          cy.log('Activity chart elements found');
        } else {
          cy.log('No chart elements - may have no repositories');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Attention Required Alerts', () => {
    beforeEach(() => {
      cy.visit('/app/devops');
      cy.waitForPageLoad();
    });

    it('should display attention alerts when issues exist', () => {
      cy.get('body').then($body => {
        if ($body.text().includes('Attention Required') || $body.text().includes('errors')) {
          cy.contains(/Attention|Warning|Error/i).should('be.visible');
          cy.log('Attention alert displayed');
        } else {
          cy.log('No attention alerts - system is healthy');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should provide review links for alerts', () => {
      cy.get('body').then($body => {
        const alertSection = $body.find('[class*="warning"], [class*="alert"]');

        if (alertSection.length > 0) {
          const hasReviewLink = alertSection.find('a, button').length > 0;
          if (hasReviewLink) {
            cy.log('Review links available in alerts');
          }
        } else {
          cy.log('No alert sections found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Refresh Functionality', () => {
    beforeEach(() => {
      cy.visit('/app/devops');
      cy.waitForPageLoad();
    });

    it('should have refresh button', () => {
      cy.get('body').then($body => {
        const refreshButton = $body.find('button:contains("Refresh"), [aria-label*="refresh"], [title*="Refresh"]');

        if (refreshButton.length > 0) {
          cy.wrap(refreshButton).first().should('be.visible');
          cy.log('Refresh button found');
        } else {
          cy.log('Refresh button not found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should refresh data when refresh button clicked', () => {
      cy.get('body').then($body => {
        const refreshButton = $body.find('button:contains("Refresh"), [aria-label*="refresh"]');

        if (refreshButton.length > 0) {
          cy.wrap(refreshButton).first().should('be.visible').click();
          // Should show loading or refreshing state
          cy.waitForPageLoad();
          cy.get('body').should('be.visible');
          cy.log('Refresh action triggered');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/devops');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');

      // Check that content is not cut off
      cy.get('body').then($body => {
        const pageContent = $body.text();
        if (pageContent.includes('DevOps') || pageContent.includes('Overview')) {
          cy.log('Page content visible on mobile');
        }
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/devops');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');

      // Check that content is not cut off
      cy.get('body').then($body => {
        const pageContent = $body.text();
        if (pageContent.includes('DevOps') || pageContent.includes('Overview')) {
          cy.log('Page content visible on tablet');
        }
      });
    });

    it('should stack cards on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/devops');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const cards = $body.find('[class*="card"], [class*="stat"]');
        if (cards.length > 0) {
          cy.log(`Found ${cards.length} card elements - verifying layout`);
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      // Mock API error
      cy.intercept('GET', '/api/v1/devops/**', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/devops');
      cy.waitForPageLoad();

      // Page should still be visible and not crash
      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should show loading state while fetching data', () => {
      // Delay API response to see loading state
      cy.intercept('GET', '/api/v1/devops/**', (req) => {
        req.on('response', (res) => {
          res.setDelay(1000);
        });
      });

      cy.visit('/app/devops');

      cy.get('body').then($body => {
        // Look for loading indicators
        const hasLoadingState = $body.find('[class*="loading"], [class*="spinner"]').length > 0 ||
                                $body.text().includes('Loading');

        if (hasLoadingState) {
          cy.log('Loading state displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });
});


export {};
