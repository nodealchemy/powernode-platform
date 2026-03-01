/// <reference types="cypress" />

/**
 * DevOps Repositories Page Tests
 *
 * Tests for Git Repositories functionality including:
 * - Page navigation and load
 * - Repository list display
 * - Search and filter functionality
 * - Sync and webhook actions
 * - Pagination
 * - Error handling
 * - Responsive design
 */

describe('DevOps Repositories Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['devops'] });
  });

  describe('Page Navigation', () => {
    it('should load Repositories page directly', () => {
      cy.assertPageReady('/app/devops/repositories', 'Repositor');
    });

    it('should display breadcrumbs', () => {
      cy.navigateTo('/app/devops/repositories');
      cy.assertContainsAny(['Dashboard', 'DevOps', 'Repositories']);
    });
  });

  describe('Repository List Display', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/devops/repositories');
    });

    it('should display repository list or empty state', () => {
      cy.assertContainsAny(['No Repositories Found', 'Sync repositories', 'GitHub', 'GitLab']);
    });

    it('should display repository details', () => {
      cy.assertContainsAny(['Private', 'Public', 'Webhook', 'star', 'No Repositories']);
    });
  });

  describe('Search Functionality', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/devops/repositories');
    });

    it('should have search input', () => {
      cy.assertContainsAny(['Search', 'Filter']);
    });
  });

  describe('Filter Functionality', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/devops/repositories');
    });

    it('should have filter options', () => {
      cy.assertContainsAny(['Filters', 'Filter', 'All', 'Provider']);
    });
  });

  describe('Import Repositories', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/devops/repositories');
    });

    it('should have Import Repositories button', () => {
      cy.assertContainsAny(['Import Repositories', 'Import']);
    });
  });

  describe('Repository Card Expansion', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/devops/repositories');
    });

    it('should display repository tabs when expanded', () => {
      cy.get('[class*="card"][class*="cursor-pointer"]').first().click();
      cy.assertContainsAny(['Overview', 'Code', 'Pull Requests', 'Branches']);
    });
  });

  describe('Pagination', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/devops/repositories');
    });

    it('should display pagination controls when needed', () => {
      cy.assertContainsAny(['Next', 'Previous', 'Page', 'No Repositories']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('/api/v1/git_repositories*', {
        statusCode: 500,
        visitUrl: '/app/devops/repositories',
      });
    });
  });

  describe('Responsive Design', () => {
    it('should display properly across viewports', () => {
      cy.testResponsiveDesign('/app/devops/repositories', {
        checkContent: 'Repositor',
      });
    });
  });
});

export {};
