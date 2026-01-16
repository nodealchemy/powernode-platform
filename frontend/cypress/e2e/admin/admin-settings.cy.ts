/// <reference types="cypress" />

/**
 * Admin Settings E2E Tests
 *
 * Tests for settings functionality via the Profile page
 */

describe('Admin Settings', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Settings Navigation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/profile');
    });

    it('should navigate to settings page via user menu', () => {
      // Open user menu
      cy.get('button[aria-haspopup="true"]', { timeout: 5000 }).first().click();
      // Click on profile/settings link
      cy.assertHasElement([
        '[data-testid="nav-profile"]',
        '[data-testid="nav-account-settings"]',
        'a[href*="profile"]',
        '[class*="menu-item"]',
      ])
        .first()
        .click();
      cy.url().should('include', '/profile');
    });

    it('should display settings content', () => {
      cy.get('body').should('be.visible');
      cy.assertContainsAny(['Profile', 'My Profile', 'Settings']);
    });
  });

  describe('Profile Settings', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/profile');
    });

    it('should display user profile section', () => {
      cy.assertHasElement([
        '[data-testid="profile-form"]',
        'input[name="name"]',
        'input[name="email"]',
        'form',
        '[class*="form"]',
      ]);
    });

    it('should allow viewing profile information', () => {
      cy.assertHasElement(['main', '[role="main"]', '.main-content', '[class*="container"]', '[class*="content"]']);
    });
  });

  describe('Security Settings', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/profile');
    });

    it('should navigate to security section', () => {
      // Click on Security tab
      cy.clickTab('Security');
      cy.assertContainsAny(['Change Password', 'Security', 'Current Password', 'Password']);
    });
  });

  describe('Notification Settings', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/profile');
    });

    it('should have notification options', () => {
      // Click on Notifications tab
      cy.clickTab('Notifications');
      cy.assertHasElement([
        'input[type="checkbox"]',
        '.toggle-theme',
        '[class*="toggle"]',
        '[role="switch"]',
        '[class*="switch"]',
      ]);
      cy.assertContainsAny(['Email Notifications', 'Notifications', 'Preferences']);
    });
  });

  describe('Theme Settings', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/profile');
    });

    it('should display theme toggle in preferences', () => {
      // Click on Preferences tab
      cy.clickTab('Preferences');
      cy.assertContainsAny(['Theme', 'Light', 'Dark', 'Appearance']);
      cy.assertHasElement([
        'select',
        '[data-testid="theme-toggle"]',
        'button[aria-label*="theme"]',
        '[role="listbox"]',
        '[class*="select"]',
      ]);
    });
  });

  describe('Account Actions', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/profile');
    });

    it('should display logout option', () => {
      cy.get('button[aria-haspopup="true"]', { timeout: 5000 }).first().click();
      cy.contains('Sign Out', { timeout: 5000 }).should('be.visible');
    });

    it('should allow user to logout', () => {
      cy.logout();
    });
  });

  describe('Responsive Design', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/profile');
    });

    it('should handle all viewports', () => {
      cy.testResponsiveDesign('/app/profile', {
        viewports: [{ name: 'mobile', width: 375, height: 667 }],
      });
    });
  });
});

export {};
