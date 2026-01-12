/// <reference types="cypress" />

/**
 * Visual Regression Tests
 *
 * Simplified visual tests for key pages
 */

describe('Visual Regression Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
  });

  describe('Public Pages', () => {
    it('should match login page layout', () => {
      cy.visit('/login');

      // Wait for page to fully load
      cy.get('[data-testid="email-input"], input[type="email"]', { timeout: 10000 }).should('be.visible');
      cy.get('[data-testid="password-input"], input[type="password"]').should('be.visible');
      cy.get('[data-testid="login-submit-btn"], button[type="submit"]').should('be.visible');

      // Screenshot for visual comparison
      cy.screenshot('login-page', {
        capture: 'viewport',
        clip: { x: 0, y: 0, width: 1280, height: 720 }
      });
    });

    it('should match login page tablet layout', () => {
      cy.viewport(768, 1024);
      cy.visit('/login');
      cy.get('[data-testid="email-input"], input[type="email"]', { timeout: 10000 }).should('be.visible');

      cy.screenshot('login-page-tablet', {
        capture: 'viewport'
      });
    });

    it('should match login page mobile layout', () => {
      cy.viewport(375, 667);
      cy.visit('/login');
      cy.get('[data-testid="email-input"], input[type="email"]', { timeout: 10000 }).should('be.visible');

      cy.screenshot('login-page-mobile', {
        capture: 'viewport'
      });
    });

    it('should match plan selection page layout', () => {
      cy.visit('/plans');

      // Wait for plans to load
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 }).should('exist');

      cy.screenshot('plans-page-desktop', {
        capture: 'fullPage'
      });
    });

    it('should match plans page tablet layout', () => {
      cy.viewport(768, 1024);
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 }).should('exist');

      cy.screenshot('plans-page-tablet', {
        capture: 'fullPage'
      });
    });

    it('should match plans page mobile layout', () => {
      cy.viewport(375, 667);
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 }).should('exist');

      cy.screenshot('plans-page-mobile', {
        capture: 'fullPage'
      });
    });

    it('should show plan selected state', () => {
      cy.viewport(1280, 720);
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 })
        .first()
        .click();
      cy.get('[data-testid="plan-select-btn"]', { timeout: 10000 }).should('be.visible');

      cy.screenshot('plans-page-plan-selected', {
        capture: 'fullPage'
      });
    });
  });

  describe('Authenticated Pages', () => {
    beforeEach(() => {
      cy.visit('/login');
      cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
      cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
      cy.get('[data-testid="login-submit-btn"]').click();
      cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
    });

    it('should match dashboard layout', () => {
      cy.url().should('match', /\/(app|dashboard)/);
      cy.get('body').should('be.visible');

      cy.screenshot('dashboard-main', {
        capture: 'fullPage'
      });
    });

    it('should match dashboard tablet layout', () => {
      cy.viewport(768, 1024);
      cy.get('body').should('be.visible');

      cy.screenshot('dashboard-main-tablet', {
        capture: 'fullPage'
      });
    });

    it('should match dashboard mobile layout', () => {
      cy.viewport(375, 667);
      cy.get('body').should('be.visible');

      cy.screenshot('dashboard-main-mobile', {
        capture: 'fullPage'
      });
    });

    it('should capture user menu dropdown', () => {
      cy.viewport(1280, 720);
      cy.get('body').then($body => {
        const userMenuSelectors = [
          '[data-testid="user-menu"]',
          '[class*="avatar"]',
          'button[aria-haspopup="menu"]'
        ];

        for (const selector of userMenuSelectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().click({ force: true });
            break;
          }
        }
      });

      cy.screenshot('dashboard-user-menu-open', {
        capture: 'viewport'
      });
    });
  });

  describe('Component States', () => {
    it('should capture empty form state', () => {
      cy.visit('/login');
      cy.get('[data-testid="email-input"], input[type="email"]', { timeout: 10000 }).should('be.visible');

      cy.screenshot('form-state-empty');
    });

    it('should capture filled form state', () => {
      cy.visit('/login');
      cy.get('[data-testid="email-input"], input[type="email"]', { timeout: 10000 })
        .type('test@example.com');
      cy.get('[data-testid="password-input"], input[type="password"]')
        .type('TestPassword123!');

      cy.screenshot('form-state-filled');
    });

    it('should capture hover states on plan cards', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 })
        .first()
        .trigger('mouseover');

      cy.screenshot('plan-card-hover');
    });

    it('should capture focus states', () => {
      cy.visit('/login');
      cy.get('[data-testid="email-input"], input[type="email"]', { timeout: 10000 }).focus();

      cy.screenshot('input-focus-state');
    });
  });

  describe('Cross-viewport Consistency', () => {
    const viewports = [
      { width: 1920, height: 1080, name: 'desktop-xl' },
      { width: 1280, height: 720, name: 'desktop' },
      { width: 1024, height: 768, name: 'tablet-landscape' },
      { width: 768, height: 1024, name: 'tablet-portrait' },
      { width: 375, height: 667, name: 'mobile' }
    ];

    viewports.forEach(viewport => {
      it(`should render login page correctly at ${viewport.name}`, () => {
        cy.viewport(viewport.width, viewport.height);
        cy.visit('/login');
        cy.get('[data-testid="email-input"], input[type="email"]', { timeout: 10000 }).should('be.visible');

        cy.screenshot(`login-${viewport.name}`);
      });
    });

    viewports.forEach(viewport => {
      it(`should render plans page correctly at ${viewport.name}`, () => {
        cy.viewport(viewport.width, viewport.height);
        cy.visit('/plans');
        cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 }).should('exist');

        cy.screenshot(`plans-${viewport.name}`, {
          capture: 'fullPage'
        });
      });
    });
  });

  describe('Error States', () => {
    it('should capture login error state', () => {
      cy.visit('/login');
      cy.get('[data-testid="email-input"], input[type="email"]', { timeout: 10000 })
        .type('test@example.com');
      cy.get('[data-testid="password-input"], input[type="password"]')
        .type('wrongpassword');
      cy.get('[data-testid="login-submit-btn"], button[type="submit"]').click();

      // Wait for error message
      cy.wait(2000);
      cy.screenshot('login-error-state');
    });
  });
});
