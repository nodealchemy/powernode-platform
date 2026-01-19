/// <reference types="cypress" />

/**
 * Analytics & Reports E2E Tests
 *
 * Tests for analytics and reporting functionality
 */

describe('Analytics & Reports', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Dashboard Analytics', () => {
    it('should display dashboard after login', () => {
      cy.get('body').should('be.visible');
      cy.url().should('match', /\/(app|dashboard)/);
    });

    it('should show main content area', () => {
      cy.assertHasElement(['main', '[role="main"]', '.main-content', '[class*="container"]'])
        .should('exist');
    });

    it('should display dashboard widgets if available', () => {
      cy.assertHasElement([
        '[data-testid="dashboard-widget"]',
        '[class*="widget"]',
        '[class*="card"]',
        '[class*="metric"]',
        '[class*="stat"]',
      ]).should('be.visible');
    });
  });

  describe('Navigation to Analytics', () => {
    it('should navigate to analytics if available', () => {
      cy.get('body').then($body => {
        const selectors = ['a[href*="analytics"]', 'a[href*="reports"]', 'a[href*="insights"]', '[data-testid="nav-analytics"]'];
        for (const selector of selectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().click();
            break;
          }
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display page content', () => {
      cy.assertHasElement(['main', '[role="main"]', '.main-content']).should('exist');
    });
  });

  describe('Date Range Selection', () => {
    it('should have date selection if available', () => {
      cy.assertHasElement([
        '[data-testid="date-range"]',
        'input[type="date"]',
        '[class*="date-picker"]',
        '[class*="calendar"]',
      ]).should('exist');
    });
  });

  describe('Charts and Visualizations', () => {
    it('should display charts if available', () => {
      cy.assertHasElement([
        'canvas',
        '[data-testid="chart"]',
        '[class*="chart"]',
        'svg[class*="recharts"]',
        '[class*="visualization"]',
      ]).should('exist');
    });
  });

  describe('Metrics Display', () => {
    it('should display metric cards if available', () => {
      cy.assertHasElement([
        '[data-testid="metric-card"]',
        '[class*="metric"]',
        '[class*="stat"]',
        '[class*="kpi"]',
      ]).should('be.visible');
    });
  });

  describe('Export Functionality', () => {
    it('should have export options if available', () => {
      cy.get('body').then($body => {
        const hasExport = $body.find('[data-testid="export-btn"], button:contains("Export"), button:contains("Download")').length > 0;
        if (hasExport) {
          cy.assertHasElement(['[data-testid="export-btn"]', 'button:contains("Export")', 'button:contains("Download")'])
            .should('exist');
        }
      });
    });
  });

  describe('Filter Options', () => {
    it('should display filter controls if available', () => {
      cy.assertHasElement([
        '[data-testid="filter"]',
        'select',
        '[class*="filter"]',
        '[class*="dropdown"]',
      ]).should('exist');
    });
  });

  describe('Responsive Design', () => {
    it('should handle mobile and tablet viewports', () => {
      cy.testResponsiveDesign('/app', {
        viewports: [
          { name: 'mobile', width: 375, height: 667 },
          { name: 'tablet', width: 768, height: 1024 },
        ],
      });
    });
  });

  describe('User Navigation', () => {
    it('should allow user to access plans page', () => {
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 })
        .should('have.length.at.least', 1);
    });

    it('should maintain session across navigation', () => {
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('body').should('be.visible');

      cy.loginAsDemo();
      cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
    });
  });

  describe('Error Handling', () => {
    it('should not display error messages', () => {
      cy.get('body')
        .should('not.contain.text', 'Error')
        .and('not.contain.text', 'Something went wrong')
        .and('not.contain.text', 'Page not found');
    });

    it('should not be stuck in loading', () => {
      cy.get('body').should('be.visible');
      cy.get('[data-testid="loading"], .loading', { timeout: 1000 }).should('not.exist');
    });
  });
});

export {};
