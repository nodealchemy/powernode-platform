/// <reference types="cypress" />

/**
 * Analytics Dashboard - Cohorts Tab Tests
 *
 * Tests for analytics cohort functionality
 */

describe('Analytics Dashboard - Cohorts Tab Fix', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  it('should handle Cohorts tab without errors', () => {
    // Navigate to Analytics page
    cy.visit('/app/analytics');

    cy.url().should('include', 'analytics');
    cy.get('button:contains("Cohorts")').first().click();

    // Verify no errors occur
    cy.get('body').should('not.contain.text', 'TypeError');
    cy.get('body').should('not.contain.text', 'Cannot read');
  });

  it('should display proper empty state when no cohort data', () => {
    // Navigate to Analytics -> Cohorts
    cy.visit('/app/analytics');

    cy.url().should('include', 'analytics');
    cy.get('button:contains("Cohorts")').first().click();

    cy.assertHasElement(['.chart-container', 'canvas', 'svg']);
  });

  it('should not break when switching between analytics tabs', () => {
    // Navigate to Analytics
    cy.visit('/app/analytics');

    cy.url().should('include', 'analytics');

    // Test switching between available tabs
    const tabs = ['Revenue', 'Growth', 'Churn', 'Customers', 'Cohorts'];

    tabs.forEach(tab => {
      cy.get(`button:contains("${tab}")`).first().click();
      cy.get('body').should('not.contain.text', 'TypeError');
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.waitForPageLoad();
    });
  });
});


export {};
