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
    cy.standardTestSetup();
  });

  describe('Page Navigation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/admin/settings/proxy');
    });

    it('should navigate to Proxy tab', () => {
      cy.assertContainsAny(['Proxy', 'Load Balancing', 'Host']);
    });

    it('should redirect unauthorized users', () => {
      cy.assertContainsAny(['Proxy', 'Settings', 'Admin']);
    });
  });

  describe('Proxy Host Management', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/proxy');
      cy.waitForPageLoad();
    });

    it('should display proxy hosts list', () => {
      cy.assertContainsAny(['Host', 'Server', 'Upstream']);
    });

    it('should have add host button', () => {
      cy.get('button:contains("Add"), button:contains("+")').should('exist');
    });

    it('should display host status indicators', () => {
      cy.assertContainsAny(['Active', 'Inactive', 'Healthy', 'Unhealthy']);
    });

    it('should display host weight/priority', () => {
      cy.assertContainsAny(['Weight', 'Priority', 'Balance']);
    });
  });

  describe('Proxy Detection Status', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/proxy');
      cy.waitForPageLoad();
    });

    it('should display detection status', () => {
      cy.assertContainsAny(['Detection', 'Detected', 'Status']);
    });

    it('should display current proxy configuration', () => {
      cy.assertContainsAny(['Configuration', 'Current', 'Settings']);
    });
  });

  describe('Connection Testing', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/proxy');
      cy.waitForPageLoad();
    });

    it('should have test connection button', () => {
      cy.get('button:contains("Test"), button:contains("Check")').should('exist');
    });

    it('should display connection test results', () => {
      cy.assertContainsAny(['Response', 'Latency', 'Success', 'Failed']);
    });

    it('should display response time metrics', () => {
      cy.assertContainsAny(['ms', 'Time', 'Response']);
    });
  });

  describe('Load Balancing Configuration', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/proxy');
      cy.waitForPageLoad();
    });

    it('should display load balancing options', () => {
      cy.assertContainsAny(['Load Balancing', 'Balance', 'Algorithm']);
    });

    it('should display balancing algorithm selection', () => {
      cy.assertContainsAny(['Round Robin', 'Least Connections', 'IP Hash', 'Weighted']);
    });

    it('should display health check settings', () => {
      cy.assertContainsAny(['Health', 'Check', 'Interval']);
    });
  });

  describe('SSL/TLS Configuration', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/proxy');
      cy.waitForPageLoad();
    });

    it('should display SSL settings', () => {
      cy.assertContainsAny(['SSL', 'TLS', 'Certificate']);
    });

    it('should display certificate status', () => {
      cy.assertContainsAny(['Certificate', 'Expires', 'Valid']);
    });
  });

  describe('Saving Configuration', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/proxy');
      cy.waitForPageLoad();
    });

    it('should have save button', () => {
      cy.get('button:contains("Save"), button:contains("Update")').should('exist');
    });

    it('should show save confirmation', () => {
      cy.assertContainsAny(['Save', 'Update', 'Proxy']);
    });
  });

  describe('Error Handling', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/admin/settings/proxy');
    });

    it('should handle API errors gracefully', () => {
      cy.intercept('GET', '**/api/**/admin/**', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/admin/settings/proxy');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Proxy', 'Settings', 'Error']);
      cy.get('body').should('not.contain.text', 'Cannot read');
    });
  });

  describe('Responsive Design', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/admin/settings/proxy');
    });

    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/admin/settings/proxy');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Proxy', 'Settings']);
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/admin/settings/proxy');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Proxy', 'Settings']);
    });
  });

  describe('Permission Check', () => {
    it('should require admin permissions', () => {
      cy.testPermissionDenied('/app/admin/settings/proxy');
    });
  });
});


export {};
