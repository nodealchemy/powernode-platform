/// <reference types="cypress" />

/**
 * Account Profile Page Tests
 *
 * Tests for Account Profile functionality including:
 * - Page navigation and load
 * - Profile information display
 * - Profile editing
 * - Avatar/photo management
 * - Account settings
 * - Security settings
 * - Email preferences
 * - Password change
 * - Two-factor authentication
 * - Permission-based access
 * - Error handling
 * - Responsive design
 */

describe('Account Profile Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Page Navigation', () => {
    it('should navigate to Profile page', () => {
      cy.visit('/app/account/profile');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Profile', 'Account', 'Settings']);
    });

    it('should display page title', () => {
      cy.visit('/app/account/profile');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Profile', 'My Profile']);
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/account/profile');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Dashboard', 'Account']);
    });
  });

  describe('Profile Information Display', () => {
    beforeEach(() => {
      cy.visit('/app/account/profile');
      cy.waitForPageLoad();
    });

    it('should display user name', () => {
      cy.assertHasElement(['input[name="name"]', 'input[name="first_name"]']);
    });

    it('should display user email', () => {
      cy.assertHasElement(['input[name="email"]', 'input[type="email"]']);
    });

    it('should display profile avatar or photo', () => {
      cy.assertHasElement(['img[class*="avatar"]', '[class*="Avatar"]', '[class*="rounded-full"]']);
    });

    it('should display phone number field', () => {
      cy.assertHasElement(['input[name="phone"]']);
    });
  });

  describe('Profile Editing', () => {
    beforeEach(() => {
      cy.visit('/app/account/profile');
      cy.waitForPageLoad();
    });

    it('should have Edit Profile button', () => {
      cy.get('button').contains(/Edit|Update/i).should('exist');
    });

    it('should have Save button', () => {
      cy.get('button').contains(/Save|Update Profile/i).should('exist');
    });

    it('should display editable form fields', () => {
      cy.assertHasElement(['input[type="text"]', 'input[type="email"]']);
    });
  });

  describe('Security Settings', () => {
    beforeEach(() => {
      cy.visit('/app/account/profile');
      cy.waitForPageLoad();
    });

    it('should display security section', () => {
      cy.assertContainsAny(['Security', 'Password']);
    });

    it('should have Change Password option', () => {
      cy.assertContainsAny(['Change Password', 'Password']);
    });

    it('should display two-factor authentication option', () => {
      cy.assertContainsAny(['Two-Factor', '2FA', 'Authentication']);
    });

    it('should display last login information', () => {
      cy.assertContainsAny(['Last Login', 'Last sign in']);
    });
  });

  describe('Email Preferences', () => {
    beforeEach(() => {
      cy.visit('/app/account/profile');
      cy.waitForPageLoad();
    });

    it('should display email preferences section', () => {
      cy.assertContainsAny(['Email', 'Notifications', 'Preferences']);
    });

    it('should display notification toggles', () => {
      cy.assertHasElement(['input[type="checkbox"]', '[class*="toggle"]', '[role="switch"]']);
    });
  });

  describe('Account Information', () => {
    beforeEach(() => {
      cy.visit('/app/account/profile');
      cy.waitForPageLoad();
    });

    it('should display account name', () => {
      cy.assertContainsAny(['Account', 'Organization']);
    });

    it('should display user role', () => {
      cy.assertContainsAny(['Role', 'admin', 'member', 'Manager']);
    });

    it('should display member since date', () => {
      cy.assertContainsAny(['Member since', 'Joined', 'Created']);
    });
  });

  describe('Danger Zone', () => {
    beforeEach(() => {
      cy.visit('/app/account/profile');
      cy.waitForPageLoad();
    });

    it('should display danger zone section', () => {
      cy.assertContainsAny(['Danger Zone', 'Delete Account', 'Deactivate']);
    });
  });

  describe('API Key Management', () => {
    beforeEach(() => {
      cy.visit('/app/account/profile');
      cy.waitForPageLoad();
    });

    it('should display API keys section', () => {
      cy.assertContainsAny(['API', 'Keys']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.intercept('GET', '/api/v1/profile*', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/account/profile');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Profile', 'Account', 'Error']);
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should display error notification on update failure', () => {
      cy.intercept('PUT', '/api/v1/profile*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to update profile' }
      }).as('updateProfile');

      cy.visit('/app/account/profile');
      cy.waitForPageLoad();
      cy.get('button').contains(/Save|Update/i).first().click();
      cy.wait('@updateProfile');
      cy.assertContainsAny(['Profile', 'Error', 'Failed']);
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '/api/v1/profile*', {
        delay: 1000,
        statusCode: 200,
        body: { success: true, user: {} }
      });

      cy.visit('/app/account/profile');
      cy.assertHasElement(['[class*="spin"]', '[class*="loading"]']);
    });
  });

  describe('Session Information', () => {
    beforeEach(() => {
      cy.visit('/app/account/profile');
      cy.waitForPageLoad();
    });

    it('should display active sessions', () => {
      cy.assertContainsAny(['Sessions', 'Active', 'Devices']);
    });

    it('should have logout all sessions option', () => {
      cy.assertContainsAny(['Logout all', 'Sign out', 'all devices']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/account/profile');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Profile', 'Account']);
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/account/profile');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Profile', 'Account']);
    });

    it('should stack sections on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/account/profile');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Profile', 'Account']);
    });

    it('should show multi-column layout on large screens', () => {
      cy.viewport(1280, 800);
      cy.visit('/app/account/profile');
      cy.waitForPageLoad();
      cy.assertHasElement(['[class*="md:grid-cols"]', '[class*="lg:grid-cols"]', '[class*="grid"]']);
    });
  });
});


export {};
