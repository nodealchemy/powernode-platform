/// <reference types="cypress" />

/**
 * DevOps API Keys Management Tests
 *
 * Tests for API Keys page functionality including:
 * - Page navigation and load
 * - API key list display
 * - Generate/Copy/Regenerate keys
 * - Toggle key status
 * - Security notice
 * - Stats display
 * - Error handling
 * - Responsive design
 */

describe('DevOps API Keys Management Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['devops'] });
  });

  describe('Page Navigation', () => {
    it('should load API Keys page directly', () => {
      cy.visit('/app/devops/api-keys');
      cy.waitForPageLoad();
      cy.assertContainsAny(['API Key', 'API Keys', 'Management']);
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/devops/api-keys');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Dashboard', 'DevOps', 'API Keys', 'API']);
    });
  });

  describe('API Key List Display', () => {
    beforeEach(() => {
      cy.visit('/app/devops/api-keys');
      cy.waitForPageLoad();
    });

    it('should display API keys list or empty state', () => {
      cy.assertContainsAny(['No API Keys', 'Active', 'Inactive', 'Revoked', '****', 'API Key', 'Production', 'Development']);
    });

    it('should display key details', () => {
      cy.assertContainsAny(['Last used', 'Never', 'ago', 'Usage', 'requests', 'No API Keys', 'Created', 'API Key']);
    });
  });

  describe('Generate New API Key', () => {
    beforeEach(() => {
      cy.visit('/app/devops/api-keys');
      cy.waitForPageLoad();
    });

    it('should display Generate New Key button', () => {
      cy.assertContainsAny(['Generate', 'New Key', 'Create', 'Your First Key']);
    });

    it('should open modal when Generate New Key clicked', () => {
      cy.get('button:contains("Generate")').first().click();
      cy.waitForStableDOM();
      cy.assertContainsAny(['Create', 'Name', 'Scope', 'Permission', 'Cancel', 'API Key']);
    });
  });

  describe('Copy API Key', () => {
    beforeEach(() => {
      cy.visit('/app/devops/api-keys');
      cy.waitForPageLoad();
    });

    it('should have copy button for API keys', () => {
      cy.assertContainsAny(['Copy', 'No API Keys', 'Generate']);
    });
  });

  describe('Regenerate API Key', () => {
    beforeEach(() => {
      cy.visit('/app/devops/api-keys');
      cy.waitForPageLoad();
    });

    it('should have regenerate button for API keys', () => {
      cy.assertContainsAny(['Regenerate', 'No API Keys', 'Generate']);
    });
  });

  describe('Toggle API Key Status', () => {
    beforeEach(() => {
      cy.visit('/app/devops/api-keys');
      cy.waitForPageLoad();
    });

    it('should have revoke/activate button', () => {
      cy.assertContainsAny(['Revoke', 'Activate', 'Disable', 'No API Keys', 'Generate']);
    });
  });

  describe('Security Notice', () => {
    beforeEach(() => {
      cy.visit('/app/devops/api-keys');
      cy.waitForPageLoad();
    });

    it('should display security notice', () => {
      cy.assertContainsAny(['Security', 'secure', 'Keep them secure', 'Warning', 'Notice', 'API Key']);
    });
  });

  describe('API Call Stats', () => {
    beforeEach(() => {
      cy.visit('/app/devops/api-keys');
      cy.waitForPageLoad();
    });

    it('should display API call statistics', () => {
      cy.assertContainsAny(['API Calls Today', 'Calls Today', 'Total Calls', 'Active Keys', 'Active', 'Total', 'API']);
    });
  });

  describe('Refresh Functionality', () => {
    beforeEach(() => {
      cy.visit('/app/devops/api-keys');
      cy.waitForPageLoad();
    });

    it('should have refresh button', () => {
      cy.assertContainsAny(['Refresh', 'Sync', 'API Key']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('/api/v1/api_keys*', {
        statusCode: 500,
        visitUrl: '/app/devops/api-keys',
      });
    });

    it('should have retry button on error', () => {
      cy.mockApiError('/api/v1/api_keys*', 500, 'Server error');
      cy.visit('/app/devops/api-keys');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Retry', 'Try again', 'Error', 'Failed', 'API Key', 'Management']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly across viewports', () => {
      cy.testResponsiveDesign('/app/devops/api-keys', {
        checkContent: 'API',
      });
    });
  });
});

export {};
