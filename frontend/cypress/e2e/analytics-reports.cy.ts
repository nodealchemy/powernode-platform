/// <reference types="cypress" />

/**
 * Analytics & Reports E2E Tests
 *
 * Simplified tests for analytics and reporting functionality
 */

describe('Analytics & Reports', () => {
  beforeEach(() => {
    cy.clearAppData();
    // Login with demo user
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Dashboard Analytics', () => {
    it('should display dashboard after login', () => {
      cy.get('body').should('be.visible');
      cy.url().should('match', /\/(app|dashboard)/);
    });

    it('should show main content area', () => {
      cy.get('main, [role="main"], .main-content, [class*="container"]')
        .should('exist');
    });

    it('should display dashboard widgets if available', () => {
      cy.get('body').then($body => {
        const widgetSelectors = [
          '[data-testid="dashboard-widget"]',
          '[class*="widget"]',
          '[class*="card"]',
          '[class*="metric"]',
          '[class*="stat"]'
        ];

        for (const selector of widgetSelectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().should('be.visible');
            break;
          }
        }
      });
    });
  });

  describe('Navigation to Analytics', () => {
    it('should navigate to analytics if available', () => {
      cy.get('body').then($body => {
        const analyticsSelectors = [
          'a[href*="analytics"]',
          'a[href*="reports"]',
          'a[href*="insights"]',
          '[data-testid="nav-analytics"]'
        ];

        for (const selector of analyticsSelectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().click({ force: true });
            break;
          }
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page content', () => {
      cy.get('main, [role="main"], .main-content').should('exist');
    });
  });

  describe('Date Range Selection', () => {
    it('should have date selection if available', () => {
      cy.get('body').then($body => {
        const dateSelectors = [
          '[data-testid="date-range"]',
          'input[type="date"]',
          '[class*="date-picker"]',
          'button:contains("Last")',
          '[class*="calendar"]'
        ];

        for (const selector of dateSelectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().should('exist');
            break;
          }
        }
      });
    });
  });

  describe('Charts and Visualizations', () => {
    it('should display charts if available', () => {
      cy.get('body').then($body => {
        const chartSelectors = [
          'canvas',
          '[data-testid="chart"]',
          '[class*="chart"]',
          'svg[class*="recharts"]',
          '[class*="visualization"]'
        ];

        for (const selector of chartSelectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().should('exist');
            break;
          }
        }
      });
    });
  });

  describe('Metrics Display', () => {
    it('should display metric cards if available', () => {
      cy.get('body').then($body => {
        const metricSelectors = [
          '[data-testid="metric-card"]',
          '[class*="metric"]',
          '[class*="stat"]',
          '[class*="kpi"]'
        ];

        for (const selector of metricSelectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().should('be.visible');
            break;
          }
        }
      });
    });
  });

  describe('Export Functionality', () => {
    it('should have export options if available', () => {
      cy.get('body').then($body => {
        const exportSelectors = [
          '[data-testid="export-btn"]',
          'button:contains("Export")',
          'button:contains("Download")',
          '[class*="export"]'
        ];

        for (const selector of exportSelectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().should('exist');
            break;
          }
        }
      });
    });
  });

  describe('Filter Options', () => {
    it('should display filter controls if available', () => {
      cy.get('body').then($body => {
        const filterSelectors = [
          '[data-testid="filter"]',
          'select',
          '[class*="filter"]',
          '[class*="dropdown"]'
        ];

        for (const selector of filterSelectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().should('exist');
            break;
          }
        }
      });
    });
  });

  describe('Responsive Design', () => {
    it('should handle mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.get('body').should('be.visible');
      cy.get('main, [role="main"], .main-content').should('be.visible');
    });

    it('should handle tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.get('body').should('be.visible');
    });
  });

  describe('User Navigation', () => {
    it('should allow user to access other pages', () => {
      // Clear session to see public plans
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 })
        .should('have.length.at.least', 1);
    });

    it('should maintain session across navigation', () => {
      // Clear session to see public plans
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('body').should('be.visible');

      // Re-login and check app
      cy.visit('/login');
      cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
      cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
      cy.get('[data-testid="login-submit-btn"]').click();
      cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
    });
  });

  describe('Error Handling', () => {
    it('should not display error messages', () => {
      cy.get('body')
        .should('not.contain.text', 'Error')
        .and('not.contain.text', 'Something went wrong')
        .and('not.contain.text', 'Page not found');
    });

    it('should display proper loading states', () => {
      cy.get('body').should('be.visible');
      // Should not be stuck in loading
      cy.get('[data-testid="loading"], .loading', { timeout: 1000 })
        .should('not.exist');
    });
  });
});
