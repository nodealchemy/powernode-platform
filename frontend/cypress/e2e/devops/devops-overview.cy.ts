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
 * - Responsive design
 */

describe('DevOps Overview Dashboard Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['devops'] });
  });

  describe('Page Navigation', () => {
    it('should load DevOps Overview page', () => {
      cy.assertPageReady('/app/devops', 'DevOps');
    });

    it('should display breadcrumbs', () => {
      cy.navigateTo('/app/devops');
      cy.assertContainsAny(['Dashboard', 'DevOps', 'Overview']);
    });
  });

  describe('Stats Cards Display', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/devops');
    });

    it('should display DevOps statistics', () => {
      // Check for stat card content - the page has these stat titles
      cy.assertContainsAny(['Git Providers', 'Repositories', 'Runners', 'Webhooks', 'Integrations', 'API Keys']);
    });

    it('should display key metrics', () => {
      cy.assertContainsAny(['configured', 'total', 'Online', 'Active', 'today']);
    });
  });

  describe('Quick Access Links', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/devops');
    });

    it('should display Quick Access section', () => {
      cy.assertContainsAny(['Quick Access', 'Quick Links', 'Git', 'Repositories', 'Webhooks', 'API Keys']);
    });

    it('should navigate to Git Providers from quick link', () => {
      cy.get('a[href*="/git"]').first().click();
      cy.url().should('include', '/git');
    });
  });

  describe('Runner Health Section', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/devops');
    });

    it('should display Runner Health section', () => {
      cy.assertContainsAny(['Runner Health', 'Runners', 'Online', 'Offline', 'Busy', 'No runners']);
    });
  });

  describe('Webhook Deliveries Section', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/devops');
    });

    it('should display Webhook Deliveries section', () => {
      cy.assertContainsAny(['Webhook Deliveries', 'Deliveries', 'Total', 'Successful', 'Failed', 'No webhook']);
    });
  });

  describe('Commit Activity Section', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/devops');
    });

    it('should display Commit Activity section', () => {
      cy.assertContainsAny(['Commit Activity', 'commits', 'Activity', 'No repositories']);
    });
  });

  describe('Attention Required Alerts', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/devops');
    });

    it('should handle attention alerts display', () => {
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
      cy.assertContainsAny(['DevOps', 'Git Providers', 'Repositories', 'Runners', 'Webhooks']);
    });
  });

  describe('Refresh Functionality', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/devops');
    });

    it('should have refresh button', () => {
      cy.assertHasElement([
        '[data-testid="action-refresh"]',
        '[aria-label="Refresh"]',
        '[aria-label*="Refresh"]',
        'button:contains("Refresh")',
      ]);
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.testErrorHandling('/api/v1/devops/**', {
        statusCode: 500,
        visitUrl: '/app/devops',
      });
    });
  });

  describe('Responsive Design', () => {
    it('should display properly across viewports', () => {
      cy.testResponsiveDesign('/app/devops', {
        checkContent: 'DevOps',
      });
    });
  });
});

export {};
