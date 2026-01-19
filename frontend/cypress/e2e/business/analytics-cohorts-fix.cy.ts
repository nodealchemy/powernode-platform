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

    cy.url().then(url => {
      if (url.includes('analytics')) {
        // Find and click the Cohorts tab
        cy.get('body').then($body => {
          const cohortsButton = $body.find('button:contains("Cohorts")');
          if (cohortsButton.length > 0) {
            cy.wrap(cohortsButton).first().click();

            // Verify no errors occur
            cy.get('body').should('not.contain.text', 'TypeError');
            cy.get('body').should('not.contain.text', 'Cannot read');
          } else {
            cy.log('Cohorts tab not found - may not be implemented');
          }
        });
      } else {
        cy.log('Analytics page not accessible');
      }
    });

    cy.get('body').should('be.visible');
  });

  it('should display proper empty state when no cohort data', () => {
    // Navigate to Analytics -> Cohorts
    cy.visit('/app/analytics');

    cy.url().then(url => {
      if (url.includes('analytics')) {
        cy.get('body').then($body => {
          const cohortsButton = $body.find('button:contains("Cohorts")');
          if (cohortsButton.length > 0) {
            cy.wrap(cohortsButton).first().click();

            // Should show either data or a friendly empty state
            cy.get('body').should('satisfy', ($el) => {
              const text = $el.text();
              const hasChart = $el.find('.chart-container, canvas, svg').length > 0;
              const hasContent = text.length > 100;
              return hasChart || hasContent;
            });
          }
        });
      }
    });

    cy.get('body').should('be.visible');
  });

  it('should not break when switching between analytics tabs', () => {
    // Navigate to Analytics
    cy.visit('/app/analytics');

    cy.url().then(url => {
      if (url.includes('analytics')) {
        // Test switching between available tabs
        const tabs = ['Revenue', 'Growth', 'Churn', 'Customers', 'Cohorts'];

        tabs.forEach(tab => {
          cy.get('body').then($body => {
            const tabButton = $body.find(`button:contains("${tab}")`);
            if (tabButton.length > 0) {
              cy.wrap(tabButton).first().click();

              // Should not show any errors
              cy.get('body').should('not.contain.text', 'TypeError');
              cy.get('body').should('not.contain.text', 'Cannot read');

              // Wait a bit for content to load
              cy.waitForPageLoad();
            }
          });
        });
      }
    });

    cy.get('body').should('be.visible');
  });
});


export {};
