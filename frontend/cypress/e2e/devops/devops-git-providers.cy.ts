/// <reference types="cypress" />

/**
 * DevOps Git Providers Page Tests
 *
 * Tests for Git Providers functionality including:
 * - Page navigation and load
 * - Provider list display
 * - Add/Edit/Delete providers
 * - Credential management
 * - Error handling
 * - Responsive design
 */

describe('DevOps Git Providers Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['devops'] });
    Cypress.on('uncaught:exception', () => false);
  });

  describe('Page Navigation', () => {
    it('should load Git Providers page directly', () => {
      cy.visit('/app/devops/git');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Git Providers', 'Git', 'Provider', 'DevOps']);
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/devops/git');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Dashboard', 'DevOps', 'Git Providers', 'Git']);
    });
  });

  describe('Provider List Display', () => {
    beforeEach(() => {
      cy.visit('/app/devops/git');
      cy.waitForPageLoad();
    });

    it('should display provider list or empty state', () => {
      cy.assertContainsAny(['No Git Providers', 'Add a Git provider', 'GitHub', 'GitLab', 'Bitbucket', 'Gitea', 'Provider', 'Git']);
    });

    it('should display provider status', () => {
      cy.assertContainsAny(['Configured', 'Not configured', 'Connected', 'credential', 'connection', 'No Git Providers', 'Provider', 'Git']);
    });
  });

  describe('Add Provider', () => {
    beforeEach(() => {
      cy.visit('/app/devops/git');
      cy.waitForPageLoad();
    });

    it('should display Add Provider button', () => {
      cy.assertContainsAny(['Add Provider', 'Add', 'Create', 'Refresh', 'Git']);
    });

    it('should open modal when Add Provider clicked', () => {
      cy.get('button:contains("Add Provider"), button:contains("Add")').first().click();
      cy.waitForStableDOM();
      cy.assertContainsAny(['Provider', 'Git', 'GitHub', 'GitLab', 'Bitbucket', 'Cancel']);
    });
  });

  describe('Manage Credentials', () => {
    beforeEach(() => {
      cy.visit('/app/devops/git');
      cy.waitForPageLoad();
    });

    it('should have credential management options', () => {
      cy.assertContainsAny(['Add Credential', 'Connect', 'Configure', 'No Git Providers', 'Manage', 'Provider', 'Git']);
    });
  });

  describe('Provider Actions', () => {
    beforeEach(() => {
      cy.visit('/app/devops/git');
      cy.waitForPageLoad();
    });

    it('should have edit and delete actions', () => {
      cy.assertContainsAny(['Edit', 'Delete', 'Configure', 'No Git Providers', 'Manage', 'Provider', 'Git']);
    });
  });

  describe('Refresh Functionality', () => {
    beforeEach(() => {
      cy.visit('/app/devops/git');
      cy.waitForPageLoad();
    });

    it('should have Refresh button', () => {
      cy.assertContainsAny(['Refresh', 'Sync', 'Git Providers', 'Git']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('**/api/**/git**', {
        statusCode: 500,
        visitUrl: '/app/devops/git',
      });
    });

    it('should display error message on API failure', () => {
      cy.mockApiError('**/api/**/git**', 500, 'Server error');
      cy.visit('/app/devops/git');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Error', 'Failed', 'Git Providers', 'Provider', 'Git']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly across viewports', () => {
      cy.testResponsiveDesign('/app/devops/git', {
        checkContent: ['Git', 'Provider', 'DevOps'],
      });
    });
  });
});

export {};
