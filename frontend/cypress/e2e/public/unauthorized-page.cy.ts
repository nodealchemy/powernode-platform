/// <reference types="cypress" />

/**
 * Unauthorized Page (403) E2E Tests
 *
 * Tests for the /unauthorized route which displays when users
 * attempt to access resources without proper permissions.
 */

describe('Unauthorized Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Page Display', () => {
    it('should display the unauthorized page with 403 error code', () => {
      cy.visit('/unauthorized');
      cy.contains('403').should('be.visible');
    });

    it('should display Access Denied title', () => {
      cy.visit('/unauthorized');
      cy.contains('Access Denied').should('be.visible');
    });

    it('should display permission denied description', () => {
      cy.visit('/unauthorized');
      cy.contains("don't have permission").should('be.visible');
    });

    it('should display the shield icon', () => {
      cy.visit('/unauthorized');
      cy.get('svg').should('exist');
    });
  });

  describe('Navigation Actions', () => {
    it('should have Go to Dashboard button', () => {
      cy.visit('/unauthorized');
      cy.contains('Go to Dashboard').should('be.visible');
    });

    it('should navigate to dashboard when clicking Go to Dashboard', () => {
      cy.visit('/unauthorized');
      cy.contains('Go to Dashboard').click();
      // Dashboard link goes to /dashboard which redirects to /app
      cy.url().should('include', '/app');
    });

    it('should have Go Back button', () => {
      cy.visit('/unauthorized');
      cy.contains('Go Back').should('be.visible');
    });
  });

  describe('Help Links', () => {
    beforeEach(() => {
      // Mock CMS pages for help links
      cy.intercept('GET', '/api/v1/pages/contact', {
        statusCode: 200,
        body: { success: true, data: { slug: 'contact', title: 'Contact', content: '' } },
      }).as('getContactPage');

      cy.intercept('GET', '/api/v1/pages/help', {
        statusCode: 200,
        body: { success: true, data: { slug: 'help', title: 'Help', content: '' } },
      }).as('getHelpPage');
    });

    it('should display contact administrator link', () => {
      cy.visit('/unauthorized');
      cy.contains('Contact your administrator').should('be.visible');
    });

    it('should navigate to contact page when clicking contact link', () => {
      cy.visit('/unauthorized');
      cy.contains('Contact your administrator').click();
      cy.url().should('include', '/pages/contact');
    });

    it('should display Help Center link', () => {
      cy.visit('/unauthorized');
      cy.contains('visit our Help Center').should('be.visible');
    });

    it('should navigate to help page when clicking help link', () => {
      cy.visit('/unauthorized');
      cy.contains('visit our Help Center').click();
      cy.url().should('include', '/pages/help');
    });
  });

  describe('Responsive Layout', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/unauthorized');
      cy.contains('403').should('be.visible');
      cy.contains('Access Denied').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/unauthorized');
      cy.contains('403').should('be.visible');
      cy.contains('Access Denied').should('be.visible');
    });

    it('should display properly on desktop viewport', () => {
      cy.viewport(1920, 1080);
      cy.visit('/unauthorized');
      cy.contains('403').should('be.visible');
      cy.contains('Access Denied').should('be.visible');
    });
  });

  describe('Accessibility', () => {
    it('should have proper heading structure', () => {
      cy.visit('/unauthorized');
      cy.get('h1').should('exist');
      cy.get('h2').should('exist');
    });

    it('should have accessible action buttons', () => {
      cy.visit('/unauthorized');
      cy.get('a').contains('Go to Dashboard').should('be.visible');
      cy.get('button').contains('Go Back').should('be.visible');
    });
  });
});

export {};
