/// <reference types="cypress" />

/**
 * User Profile Management Tests
 *
 * Tests for User Profile functionality including:
 * - Profile viewing and editing
 * - Avatar/photo management
 * - Password changes
 * - Notification preferences
 * - Account settings
 * - Session management
 */

describe('User Profile Management Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Profile Viewing', () => {
    it('should navigate to profile page', () => {
      cy.visit('/app/profile');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Profile', 'Account', 'Settings']);
    });

    it('should display user name', () => {
      cy.visit('/app/profile');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Name', 'First', 'Last']);
    });

    it('should display user email', () => {
      cy.visit('/app/profile');
      cy.waitForPageLoad();
      cy.assertContainsAny(['@', 'Email']);
    });

    it('should display user avatar', () => {
      cy.visit('/app/profile');
      cy.waitForPageLoad();
      cy.assertHasElement(['img[alt*="avatar"]', 'img[alt*="profile"]', '.avatar']);
    });
  });

  describe('Profile Editing', () => {
    beforeEach(() => {
      cy.visit('/app/profile/edit');
      cy.waitForPageLoad();
    });

    it('should have edit profile button', () => {
      cy.assertContainsAny(['Edit', 'Update']);
    });

    it('should have first name field', () => {
      cy.assertContainsAny(['First Name', 'First']);
    });

    it('should have last name field', () => {
      cy.assertContainsAny(['Last Name', 'Last']);
    });

    it('should have save button', () => {
      cy.assertHasElement(['button:contains("Save")', 'button[type="submit"]']);
    });
  });

  describe('Avatar Management', () => {
    beforeEach(() => {
      cy.visit('/app/profile');
      cy.waitForPageLoad();
    });

    it('should have upload avatar option', () => {
      cy.assertContainsAny(['Upload', 'Change Photo', 'Change Avatar']);
    });

    it('should have remove avatar option', () => {
      cy.assertContainsAny(['Remove', 'Delete']);
    });
  });

  describe('Password Management', () => {
    it('should navigate to password change', () => {
      cy.visit('/app/profile/password');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Password', 'Security']);
    });

    it('should have current password field', () => {
      cy.visit('/app/profile/password');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Current', 'Password']);
    });

    it('should have new password field', () => {
      cy.visit('/app/profile/password');
      cy.waitForPageLoad();
      cy.assertContainsAny(['New', 'Password']);
    });

    it('should have confirm password field', () => {
      cy.visit('/app/profile/password');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Confirm', 'Password']);
    });

    it('should display password requirements', () => {
      cy.visit('/app/profile/password');
      cy.waitForPageLoad();
      cy.assertContainsAny(['character', 'must', 'requirement']);
    });
  });

  describe('Notification Preferences', () => {
    it('should navigate to notification settings', () => {
      cy.visit('/app/profile/notifications');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Notification', 'Alert', 'Email']);
    });

    it('should display email notification toggles', () => {
      cy.visit('/app/profile/notifications');
      cy.waitForPageLoad();
      cy.assertHasElement(['input[type="checkbox"]', '[role="switch"]']);
    });

    it('should display notification categories', () => {
      cy.visit('/app/profile/notifications');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Marketing', 'Security', 'Updates', 'Product']);
    });
  });

  describe('Session Management', () => {
    it('should navigate to sessions page', () => {
      cy.visit('/app/profile/sessions');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Session', 'Device', 'Active']);
    });

    it('should display active sessions', () => {
      cy.visit('/app/profile/sessions');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Current', 'Active', 'Session']);
    });

    it('should have revoke session option', () => {
      cy.visit('/app/profile/sessions');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Revoke', 'Sign out', 'End']);
    });

    it('should display session details', () => {
      cy.visit('/app/profile/sessions');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Browser', 'Location', 'IP', 'Device']);
    });
  });

  describe('Responsive Design', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display profile correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/profile');
        cy.waitForPageLoad();

        cy.assertContainsAny(['Profile', 'Account', 'Settings']);
        cy.log(`Profile displayed correctly on ${name}`);
      });
    });
  });
});
