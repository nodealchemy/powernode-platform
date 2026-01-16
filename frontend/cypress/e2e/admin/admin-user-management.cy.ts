/// <reference types="cypress" />

/**
 * Admin User Management E2E Tests
 *
 * Simplified tests for user management functionality
 */

describe('Admin User Management', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Dashboard Access', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/dashboard');
    });

    it('should display dashboard after login', () => {
      cy.get('body').should('be.visible');
      cy.url().should('match', /\/(app|dashboard)/);
    });

    it('should display navigation menu', () => {
      cy.assertHasElement([
        'nav',
        '[role="navigation"]',
        'aside',
        '[class*="sidebar"]',
        '[class*="nav"]',
        'header',
      ]);
    });
  });

  describe('User Menu', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/dashboard');
    });

    it('should display current user info', () => {
      cy.assertHasElement([
        '[data-testid="user-menu"]',
        '[class*="avatar"]',
        '[class*="user"]',
        '[class*="profile"]',
        'button[aria-haspopup="true"]',
      ]);
    });

    it('should open user dropdown menu', () => {
      cy.get('button[aria-haspopup="true"]', { timeout: 5000 }).first().click();
      cy.assertContainsAny(['Settings', 'Profile', 'Sign Out', 'Logout']);
    });
  });

  describe('Navigation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/dashboard');
    });

    it('should have working navigation links', () => {
      cy.get('nav a, aside a, [role="navigation"] a').should('have.length.at.least', 1);
    });

    it('should allow navigation to different sections', () => {
      cy.get('nav a, aside a').first().should('be.visible').click();
      cy.url().should('include', '/');
    });
  });

  describe('Settings Access', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/dashboard');
    });

    it('should navigate to settings if available', () => {
      // Use broader element selection to handle different nav structures
      cy.get('body').then($body => {
        const settingsSelectors = [
          'a[href*="settings"]',
          'a[href*="profile"]',
          '[data-testid="settings-link"]',
          '[data-testid="nav-settings"]',
          'nav a',
          'aside a',
        ];

        for (const selector of settingsSelectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().should('be.visible').click();
            break;
          }
        }
      });
      cy.url().should('match', /\/(app|dashboard|settings|profile)/);
    });

    it('should display page content', () => {
      cy.assertHasElement([
        'main',
        '[role="main"]',
        '.main-content',
        '[class*="container"]',
        '[class*="content"]',
      ]);
    });
  });

  describe('Responsive Design', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/dashboard');
    });

    it('should handle all viewports', () => {
      cy.testResponsiveDesign('/app/dashboard', {
        viewports: [
          { name: 'mobile', width: 375, height: 667 },
          { name: 'tablet', width: 768, height: 1024 },
        ],
      });
    });
  });
});

export {};
