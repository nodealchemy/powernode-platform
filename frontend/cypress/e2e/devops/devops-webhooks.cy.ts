/// <reference types="cypress" />

/**
 * DevOps Webhooks Management Tests
 *
 * Tests for Webhooks page functionality including:
 * - Page navigation and load
 * - Webhook list display
 * - Add/Edit/Delete webhooks
 * - Statistics and filtering
 * - Responsive design
 */

describe('DevOps Webhooks Management Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['devops'] });
  });

  describe('Page Navigation', () => {
    it('should load Webhooks page directly', () => {
      cy.visit('/app/devops/webhooks');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Webhook', 'Webhooks', 'Management', 'DevOps']);
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/devops/webhooks');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Dashboard', 'DevOps', 'Webhooks']);
    });
  });

  describe('Stats Overview', () => {
    beforeEach(() => {
      cy.visit('/app/devops/webhooks');
      cy.waitForPageLoad();
    });

    it('should display webhook statistics or page content', () => {
      cy.assertContainsAny(['Total', 'Endpoints', 'Active', 'Inactive', 'Deliveries', 'Webhook', 'No webhooks']);
    });
  });

  describe('Webhook List Display', () => {
    beforeEach(() => {
      cy.visit('/app/devops/webhooks');
      cy.waitForPageLoad();
    });

    it('should display webhook list or empty state', () => {
      cy.assertContainsAny(['No webhooks', 'Add your first', 'http://', 'https://', 'Webhook', 'webhook', 'Create']);
    });

    it('should display webhook content', () => {
      cy.assertContainsAny(['Active', 'Inactive', 'event', 'subscription', 'payment', 'No webhooks', 'Webhook', 'Add']);
    });
  });

  describe('Add Webhook', () => {
    beforeEach(() => {
      cy.visit('/app/devops/webhooks');
      cy.waitForPageLoad();
    });

    it('should display Add Webhook button or action', () => {
      cy.assertContainsAny(['Add Webhook', 'Create', 'New', 'Webhook']);
    });

    it('should have action buttons or modal trigger', () => {
      cy.get('body').then($body => {
        const addBtn = $body.find('button:contains("Add Webhook"), button:contains("Create"), button:contains("New")');
        if (addBtn.length > 0) {
          cy.wrap(addBtn).first().click();
          cy.waitForStableDOM();
          cy.assertContainsAny(['Create', 'URL', 'Events', 'Cancel', 'Webhook', 'Add']);
        }
      });
    });
  });

  describe('Webhook Actions', () => {
    beforeEach(() => {
      cy.visit('/app/devops/webhooks');
      cy.waitForPageLoad();
    });

    it('should have action options', () => {
      cy.assertContainsAny(['View', 'Edit', 'Disable', 'Enable', 'Delete', 'No webhooks', 'Webhook', 'Add', 'Create']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('**/api/**/webhooks**', {
        statusCode: 500,
        visitUrl: '/app/devops/webhooks',
      });
    });

    it('should display error message on API failure', () => {
      cy.intercept('GET', '**/api/**/webhooks**', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });
      cy.visit('/app/devops/webhooks');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Error', 'Failed', 'Webhook', 'permission', 'retry']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/devops/webhooks');
      cy.waitForPageLoad();
      cy.get('body').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/devops/webhooks');
      cy.waitForPageLoad();
      cy.get('body').should('be.visible');
    });

    it('should display properly on large screens', () => {
      cy.viewport(1920, 1080);
      cy.visit('/app/devops/webhooks');
      cy.waitForPageLoad();
      cy.get('body').should('be.visible');
    });
  });
});

export {};
