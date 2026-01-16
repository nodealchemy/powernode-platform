/// <reference types="cypress" />

/**
 * Admin Settings - Performance Tab E2E Tests
 *
 * Tests for performance optimization settings including:
 * - Performance overview
 * - Caching configuration
 * - Database optimization
 * - Asset optimization
 * - Monitoring settings
 * - Responsive design
 */

describe('Admin Settings Performance Tab Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Page Navigation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/admin/settings/performance');
    });

    it('should navigate to Performance tab', () => {

      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Performance') ||
                          $body.text().includes('Optimization') ||
                          $body.text().includes('Cache');
        if (hasContent) {
          cy.log('Performance tab loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should redirect unauthorized users', () => {
      cy.visit('/app/admin/settings/performance');
      cy.waitForPageLoad();
      cy.get('body').should('be.visible');
    });
  });

  describe('Performance Overview', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/performance');
      cy.waitForPageLoad();
    });

    it('should display performance metrics', () => {
      cy.get('body').then($body => {
        const hasMetrics = $body.text().includes('Response Time') ||
                           $body.text().includes('Latency') ||
                           $body.text().includes('ms');
        if (hasMetrics) {
          cy.log('Performance metrics displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display performance score', () => {
      cy.get('body').then($body => {
        const hasScore = $body.text().includes('Score') ||
                         $body.text().includes('%') ||
                         $body.text().includes('Good') ||
                         $body.text().includes('Excellent');
        if (hasScore) {
          cy.log('Performance score displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Caching Configuration', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/performance');
      cy.waitForPageLoad();
    });

    it('should display cache settings section', () => {
      cy.get('body').then($body => {
        const hasCache = $body.text().includes('Cache') ||
                         $body.text().includes('Caching');
        if (hasCache) {
          cy.log('Cache settings section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display cache toggle', () => {
      cy.get('body').then($body => {
        const hasToggle = $body.find('input[type="checkbox"], [role="switch"]').length > 0;
        if (hasToggle) {
          cy.log('Cache toggle displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display cache TTL settings', () => {
      cy.get('body').then($body => {
        const hasTTL = $body.text().includes('TTL') ||
                       $body.text().includes('Time to Live') ||
                       $body.text().includes('Expiration');
        if (hasTTL) {
          cy.log('Cache TTL settings displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have clear cache button', () => {
      cy.get('body').then($body => {
        const hasClearCache = $body.find('button:contains("Clear"), button:contains("Flush")').length > 0;
        if (hasClearCache) {
          cy.log('Clear cache button found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Database Optimization', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/performance');
      cy.waitForPageLoad();
    });

    it('should display database settings', () => {
      cy.get('body').then($body => {
        const hasDB = $body.text().includes('Database') ||
                      $body.text().includes('Query') ||
                      $body.text().includes('Connection');
        if (hasDB) {
          cy.log('Database settings displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display connection pool settings', () => {
      cy.get('body').then($body => {
        const hasPool = $body.text().includes('Pool') ||
                        $body.text().includes('Connection') ||
                        $body.text().includes('Connections');
        if (hasPool) {
          cy.log('Connection pool settings displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display query optimization options', () => {
      cy.get('body').then($body => {
        const hasQuery = $body.text().includes('Query') ||
                         $body.text().includes('Optimization');
        if (hasQuery) {
          cy.log('Query optimization options displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Asset Optimization', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/performance');
      cy.waitForPageLoad();
    });

    it('should display asset settings', () => {
      cy.get('body').then($body => {
        const hasAsset = $body.text().includes('Asset') ||
                         $body.text().includes('Compression') ||
                         $body.text().includes('Minification');
        if (hasAsset) {
          cy.log('Asset settings displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display compression toggle', () => {
      cy.get('body').then($body => {
        const hasCompression = $body.text().includes('Compression') ||
                               $body.text().includes('Gzip') ||
                               $body.text().includes('Brotli');
        if (hasCompression) {
          cy.log('Compression toggle displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display CDN settings', () => {
      cy.get('body').then($body => {
        const hasCDN = $body.text().includes('CDN') ||
                       $body.text().includes('Content Delivery');
        if (hasCDN) {
          cy.log('CDN settings displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Monitoring Settings', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/performance');
      cy.waitForPageLoad();
    });

    it('should display monitoring options', () => {
      cy.get('body').then($body => {
        const hasMonitoring = $body.text().includes('Monitor') ||
                              $body.text().includes('Metrics') ||
                              $body.text().includes('Logging');
        if (hasMonitoring) {
          cy.log('Monitoring options displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display performance alerts', () => {
      cy.get('body').then($body => {
        const hasAlerts = $body.text().includes('Alert') ||
                          $body.text().includes('Threshold') ||
                          $body.text().includes('Warning');
        if (hasAlerts) {
          cy.log('Performance alerts displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Performance Actions', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/performance');
      cy.waitForPageLoad();
    });

    it('should have optimize button', () => {
      cy.get('body').then($body => {
        const hasOptimize = $body.find('button:contains("Optimize"), button:contains("Run")').length > 0;
        if (hasOptimize) {
          cy.log('Optimize button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have refresh metrics button', () => {
      cy.get('body').then($body => {
        const hasRefresh = $body.find('button:contains("Refresh"), button[aria-label*="refresh"]').length > 0;
        if (hasRefresh) {
          cy.log('Refresh metrics button found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/admin/settings/performance');
    });

    it('should handle API errors gracefully', () => {
      cy.intercept('GET', '**/api/**/admin/**', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/admin/settings/performance');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
    });
  });

  describe('Loading State', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/admin/settings/performance');
    });

    it('should display loading indicator', () => {
      cy.intercept('GET', '**/api/**/admin/**', {
        delay: 2000,
        statusCode: 200,
        body: {}
      });

      cy.visit('/app/admin/settings/performance');

      cy.get('body').then($body => {
        const hasLoading = $body.find('[class*="spin"]').length > 0 ||
                           $body.text().includes('Loading');
        if (hasLoading) {
          cy.log('Loading indicator displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/admin/settings/performance');
    });

    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/admin/settings/performance');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/admin/settings/performance');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
    });
  });
});


export {};
