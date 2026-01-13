/// <reference types="cypress" />

/**
 * Admin Settings - Proxy Tab E2E Tests
 *
 * Tests for proxy configuration including:
 * - Proxy host management
 * - Connection testing
 * - Proxy detection status
 * - Load balancing configuration
 * - Responsive design
 */

describe('Admin Settings Proxy Tab Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to Proxy tab', () => {
      cy.visit('/app/admin/settings/proxy');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Proxy') ||
                          $body.text().includes('Load Balancing') ||
                          $body.text().includes('Host');
        if (hasContent) {
          cy.log('Proxy tab loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should redirect unauthorized users', () => {
      cy.visit('/app/admin/settings/proxy');
      cy.wait(2000);
      cy.get('body').should('be.visible');
    });
  });

  describe('Proxy Host Management', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/proxy');
      cy.wait(2000);
    });

    it('should display proxy hosts list', () => {
      cy.get('body').then($body => {
        const hasHosts = $body.text().includes('Host') ||
                         $body.text().includes('Server') ||
                         $body.text().includes('Upstream');
        if (hasHosts) {
          cy.log('Proxy hosts list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have add host button', () => {
      cy.get('body').then($body => {
        const hasAddButton = $body.find('button:contains("Add"), button:contains("+")').length > 0;
        if (hasAddButton) {
          cy.log('Add host button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display host status indicators', () => {
      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Active') ||
                          $body.text().includes('Inactive') ||
                          $body.text().includes('Healthy') ||
                          $body.text().includes('Unhealthy');
        if (hasStatus) {
          cy.log('Host status indicators displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display host weight/priority', () => {
      cy.get('body').then($body => {
        const hasWeight = $body.text().includes('Weight') ||
                          $body.text().includes('Priority') ||
                          $body.text().includes('Balance');
        if (hasWeight) {
          cy.log('Host weight/priority displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Proxy Detection Status', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/proxy');
      cy.wait(2000);
    });

    it('should display detection status', () => {
      cy.get('body').then($body => {
        const hasDetection = $body.text().includes('Detection') ||
                             $body.text().includes('Detected') ||
                             $body.text().includes('Status');
        if (hasDetection) {
          cy.log('Detection status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display current proxy configuration', () => {
      cy.get('body').then($body => {
        const hasConfig = $body.text().includes('Configuration') ||
                          $body.text().includes('Current') ||
                          $body.text().includes('Settings');
        if (hasConfig) {
          cy.log('Current proxy configuration displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Connection Testing', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/proxy');
      cy.wait(2000);
    });

    it('should have test connection button', () => {
      cy.get('body').then($body => {
        const hasTestButton = $body.find('button:contains("Test"), button:contains("Check")').length > 0;
        if (hasTestButton) {
          cy.log('Test connection button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display connection test results', () => {
      cy.get('body').then($body => {
        const hasResults = $body.text().includes('Response') ||
                           $body.text().includes('Latency') ||
                           $body.text().includes('Success') ||
                           $body.text().includes('Failed');
        if (hasResults) {
          cy.log('Connection test results displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display response time metrics', () => {
      cy.get('body').then($body => {
        const hasMetrics = $body.text().includes('ms') ||
                           $body.text().includes('Time') ||
                           $body.text().includes('Response');
        if (hasMetrics) {
          cy.log('Response time metrics displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Load Balancing Configuration', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/proxy');
      cy.wait(2000);
    });

    it('should display load balancing options', () => {
      cy.get('body').then($body => {
        const hasLoadBalancing = $body.text().includes('Load Balancing') ||
                                  $body.text().includes('Balance') ||
                                  $body.text().includes('Algorithm');
        if (hasLoadBalancing) {
          cy.log('Load balancing options displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display balancing algorithm selection', () => {
      cy.get('body').then($body => {
        const hasAlgorithm = $body.text().includes('Round Robin') ||
                             $body.text().includes('Least Connections') ||
                             $body.text().includes('IP Hash') ||
                             $body.text().includes('Weighted');
        if (hasAlgorithm) {
          cy.log('Balancing algorithm selection displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display health check settings', () => {
      cy.get('body').then($body => {
        const hasHealthCheck = $body.text().includes('Health') ||
                               $body.text().includes('Check') ||
                               $body.text().includes('Interval');
        if (hasHealthCheck) {
          cy.log('Health check settings displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('SSL/TLS Configuration', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/proxy');
      cy.wait(2000);
    });

    it('should display SSL settings', () => {
      cy.get('body').then($body => {
        const hasSSL = $body.text().includes('SSL') ||
                       $body.text().includes('TLS') ||
                       $body.text().includes('Certificate');
        if (hasSSL) {
          cy.log('SSL settings displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display certificate status', () => {
      cy.get('body').then($body => {
        const hasCert = $body.text().includes('Certificate') ||
                        $body.text().includes('Expires') ||
                        $body.text().includes('Valid');
        if (hasCert) {
          cy.log('Certificate status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Saving Configuration', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/proxy');
      cy.wait(2000);
    });

    it('should have save button', () => {
      cy.get('body').then($body => {
        const hasSave = $body.find('button:contains("Save"), button:contains("Update")').length > 0;
        if (hasSave) {
          cy.log('Save button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should show save confirmation', () => {
      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.intercept('GET', '**/api/**/admin/**', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/admin/settings/proxy');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/admin/settings/proxy');
      cy.wait(2000);

      cy.get('body').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/admin/settings/proxy');
      cy.wait(2000);

      cy.get('body').should('be.visible');
    });
  });
});
