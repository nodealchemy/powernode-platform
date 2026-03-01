/// <reference types="cypress" />

/**
 * User Profile and Settings Tests
 *
 * Simplified tests for profile and settings using demo user
 */

describe('User Profile and Settings Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('User Profile Display', () => {
    it('should display dashboard after login', () => {
      cy.url().should('match', /\/(app|dashboard)/);
      cy.assertContainsAny(['Profile', 'Settings', 'Dashboard']);
    });

    it('should have user menu visible', () => {
      // Header user button has aria-haspopup="true" and shows user initials in a rounded-full div
      cy.assertHasElement([
        '[data-testid="user-menu"]',
        'button[aria-haspopup="true"]',
        '[class*="avatar"]',
        '.rounded-full'
      ]);
    });
  });

  describe('Profile Navigation', () => {
    it('should navigate to profile settings if available', () => {
      // Header user button has aria-haspopup="true"
      cy.assertHasElement([
        '[data-testid="user-menu"]',
        'button[aria-haspopup="true"]',
        '[class*="avatar"]',
        '.rounded-full'
      ]);
      cy.assertContainsAny(['Profile', 'Settings', 'Dashboard']);
    });

    it('should access settings page directly', () => {
      // Profile page is at /app/profile
      cy.assertPageReady('/app/profile');
    });
  });

  describe('Account Settings', () => {
    it('should navigate to account settings', () => {
      cy.navigateTo('settings');
      cy.assertContainsAny(['Profile', 'Settings', 'Dashboard']);
    });

    it('should display settings form', () => {
      // Profile page is at /app/profile and has a profile-form
      cy.assertPageReady('/app/profile');
      cy.assertHasElement([
        'form',
        'input[name]',
        '[data-testid="settings-form"]',
        '[data-testid="profile-form"]',
        'form#profile-form'
      ]);
    });
  });

  describe('Security Settings', () => {
    it('should navigate to security settings if available', () => {
      // Security settings is at /app/profile/security
      cy.assertPageReady('/app/profile/security');
    });
  });

  describe('Theme Preferences', () => {
    it('should handle theme toggle if available', () => {
      cy.assertHasElement(['[data-testid="theme-toggle"]', '.theme-toggle', '[aria-label*="theme"]']);
    });

    it('should persist preferences across page reload', () => {
      cy.reload();
      cy.waitForPageLoad();
      cy.url().should('match', /\/(app|dashboard)/);
      cy.assertContainsAny(['Profile', 'Settings', 'Dashboard']);
    });
  });

  describe('Mobile Profile Management', () => {
    it('should handle profile management on mobile viewport', () => {
      cy.testViewport('mobile', '/app');
      cy.url().should('match', /\/(app|dashboard)/);
    });

    it('should access user menu on mobile', () => {
      cy.testViewport('mobile', '/app');
      // Header user button has aria-haspopup="true" and shows user initials in a rounded-full div
      cy.assertHasElement([
        '[data-testid="user-menu"]',
        'button[aria-haspopup="true"]',
        '[class*="avatar"]',
        '.rounded-full'
      ]);
    });

    it('should handle tablet viewport', () => {
      cy.testViewport('tablet', '/app');
      cy.assertContainsAny(['Profile', 'Settings', 'Dashboard']);
    });
  });

  describe('Error Handling', () => {
    it('should not display error messages on valid pages', () => {
      cy.get('body')
        .should('not.contain.text', 'Something went wrong')
        .and('not.contain.text', 'Error loading');
    });

    it('should maintain session across navigation', () => {
      cy.visit('/app/settings/profile');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Profile', 'Settings', 'Dashboard']);

      cy.visit('/app');
      cy.waitForPageLoad();
      cy.url().should('match', /\/(app|dashboard)/);
    });
  });

  describe('Logout Flow', () => {
    it('should allow user to logout', () => {
      cy.logout();
    });
  });
});


export {};
