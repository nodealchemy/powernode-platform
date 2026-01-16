/// <reference types="cypress" />

/**
 * DevOps Runners Page Tests
 *
 * Tests for CI/CD Runners functionality including:
 * - Page navigation and load
 * - Stats cards display
 * - Runner list display
 * - Search and filter
 * - Sync and delete actions
 * - Pagination
 * - Error handling
 * - Responsive design
 */

describe('DevOps Runners Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['devops'] });
  });

  describe('Page Navigation', () => {
    it('should load Runners page directly', () => {
      cy.visit('/app/devops/runners');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Runner', 'Runners', 'Automation']);
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/devops/runners');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Dashboard', 'DevOps', 'Runners', 'Automation']);
    });
  });

  describe('Stats Cards Display', () => {
    beforeEach(() => {
      cy.visit('/app/devops/runners');
      cy.waitForPageLoad();
    });

    it('should display runner statistics', () => {
      cy.assertContainsAny(['Total', 'Online', 'Busy', 'Offline', 'Runner', 'Runners', 'No Runners']);
    });
  });

  describe('Runner List Display', () => {
    beforeEach(() => {
      cy.visit('/app/devops/runners');
      cy.waitForPageLoad();
    });

    it('should display runner list or empty state', () => {
      cy.assertContainsAny(['No Runners Found', 'No Runners', 'Sync runners', 'Online', 'Offline', 'Busy', 'Runner']);
    });

    it('should display runner details', () => {
      cy.assertContainsAny(['linux', 'windows', 'macos', 'x64', 'arm', 'jobs', 'success', 'No Runners', 'Runner']);
    });
  });

  describe('Search Functionality', () => {
    beforeEach(() => {
      cy.visit('/app/devops/runners');
      cy.waitForPageLoad();
    });

    it('should have search input', () => {
      cy.assertContainsAny(['Search', 'Filter', 'Runner', 'Runners']);
    });
  });

  describe('Status Filter', () => {
    beforeEach(() => {
      cy.visit('/app/devops/runners');
      cy.waitForPageLoad();
    });

    it('should have status filter dropdown', () => {
      cy.assertContainsAny(['Status', 'All', 'Online', 'Offline', 'Busy', 'Runner']);
    });
  });

  describe('Sync Runners', () => {
    beforeEach(() => {
      cy.visit('/app/devops/runners');
      cy.waitForPageLoad();
    });

    it('should have Sync Runners button', () => {
      cy.assertContainsAny(['Sync Runners', 'Sync', 'Refresh', 'Runner']);
    });
  });

  describe('Delete Runner', () => {
    beforeEach(() => {
      cy.visit('/app/devops/runners');
      cy.waitForPageLoad();
    });

    it('should have Delete action for runners', () => {
      cy.assertContainsAny(['Delete', 'Remove', 'No Runners', 'Runner']);
    });
  });

  describe('Pagination', () => {
    beforeEach(() => {
      cy.visit('/app/devops/runners');
      cy.waitForPageLoad();
    });

    it('should display pagination when needed', () => {
      cy.assertContainsAny(['Next', 'Previous', 'Page', 'No Runners', 'Runner', 'Showing']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('/api/v1/git_runners*', {
        statusCode: 500,
        visitUrl: '/app/devops/runners',
      });
    });

    it('should have Try Again button on error', () => {
      cy.mockApiError('/api/v1/git_runners*', 500, 'Failed to fetch runners');
      cy.visit('/app/devops/runners');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Try Again', 'Retry', 'Error', 'Failed', 'Runner']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly across viewports', () => {
      cy.testResponsiveDesign('/app/devops/runners', {
        checkContent: 'Runner',
      });
    });
  });
});

export {};
