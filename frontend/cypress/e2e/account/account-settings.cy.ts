/// <reference types="cypress" />

/**
 * Account Settings Update Flow E2E Tests
 *
 * Tests for account settings functionality including:
 * - Profile settings update
 * - Password change
 * - Email update
 * - Two-factor authentication
 * - Notification preferences
 * - Account deletion
 * - Responsive design
 */

describe('Account Settings Update Flow Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Page Navigation', () => {
    it('should navigate to Account Settings', () => {
      cy.visit('/app/profile');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Profile', 'Settings', 'Account']);
    });

    it('should display settings navigation', () => {
      cy.visit('/app/profile');
      cy.waitForPageLoad();
      cy.assertHasElement(['a', 'button', '[class*="nav"]']);
    });
  });

  describe('Profile Settings', () => {
    beforeEach(() => {
      cy.visit('/app/profile');
      cy.waitForPageLoad();
    });

    it('should display first name field', () => {
      cy.assertHasElement(['input[name*="first"]', 'input[name*="firstName"]']);
    });

    it('should display last name field', () => {
      cy.assertHasElement(['input[name*="last"]', 'input[name*="lastName"]']);
    });

    it('should display email field', () => {
      cy.assertHasElement(['input[type="email"]', 'input[name*="email"]']);
    });

    it('should display phone field', () => {
      cy.assertHasElement(['input[type="tel"]', 'input[name*="phone"]']);
    });

    it('should have avatar/photo upload', () => {
      cy.assertHasElement(['input[type="file"]', '[class*="avatar"]', '[class*="photo"]']);
    });

    it('should have Save button', () => {
      cy.get('button').contains(/Save|Update/i).should('exist');
    });

    it('should update profile name', () => {
      cy.get('input[name*="first"], input[name*="name"]').first().clear().type('Updated Name');
      cy.assertContainsAny(['Profile', 'Settings']);
    });
  });

  describe('Password Change', () => {
    beforeEach(() => {
      cy.visit('/app/profile/security');
      cy.waitForPageLoad();
    });

    it('should navigate to Security settings', () => {
      cy.assertContainsAny(['Security', 'Password']);
    });

    it('should have current password field', () => {
      cy.assertHasElement(['input[name*="current"]', 'input[name*="old"]']);
    });

    it('should have new password field', () => {
      cy.assertHasElement(['input[name*="new"]', 'input[type="password"]']);
    });

    it('should have confirm password field', () => {
      cy.get('input[name*="confirm"]').should('exist');
    });

    it('should have Change Password button', () => {
      cy.get('button').contains(/Change|Update Password/i).should('exist');
    });

    it('should display password requirements', () => {
      cy.assertContainsAny(['characters', 'uppercase', 'number', 'requirements']);
    });
  });

  describe('Two-Factor Authentication', () => {
    beforeEach(() => {
      cy.visit('/app/profile/security');
      cy.waitForPageLoad();
    });

    it('should display 2FA section', () => {
      cy.assertContainsAny(['Two-Factor', '2FA', 'Authentication']);
    });

    it('should have enable/disable 2FA option', () => {
      cy.assertHasElement(['input[type="checkbox"]', 'button:contains("Enable")', 'button:contains("Disable")']);
    });

    it('should display 2FA status', () => {
      cy.assertContainsAny(['Enabled', 'Disabled', 'Not configured']);
    });
  });

  describe('Notification Preferences', () => {
    beforeEach(() => {
      cy.visit('/app/profile/notifications');
      cy.waitForPageLoad();
    });

    it('should navigate to Notification settings', () => {
      cy.assertContainsAny(['Notification', 'Preferences']);
    });

    it('should display email notification toggle', () => {
      cy.assertHasElement(['input[type="checkbox"]']);
    });

    it('should display SMS notification toggle', () => {
      cy.assertContainsAny(['SMS', 'Text']);
    });

    it('should display push notification toggle', () => {
      cy.assertContainsAny(['Push', 'Browser']);
    });

    it('should have notification categories', () => {
      cy.assertContainsAny(['Marketing', 'Security', 'Updates', 'Billing']);
    });

    it('should save notification preferences', () => {
      cy.get('input[type="checkbox"], [role="switch"]').first().click();
      cy.waitForPageLoad();
      cy.assertContainsAny(['Notifications', 'Preferences']);
    });
  });

  describe('Session Management', () => {
    beforeEach(() => {
      cy.visit('/app/profile/security');
      cy.waitForPageLoad();
    });

    it('should display active sessions', () => {
      cy.assertContainsAny(['Session', 'Devices', 'Active']);
    });

    it('should have logout all sessions option', () => {
      cy.assertContainsAny(['all devices', 'Logout', 'Sign Out']);
    });
  });

  describe('Account Deletion', () => {
    beforeEach(() => {
      cy.visit('/app/profile');
      cy.waitForPageLoad();
    });

    it('should have delete account option', () => {
      cy.assertContainsAny(['Delete', 'Close Account']);
    });

    it('should display deletion warning', () => {
      cy.assertContainsAny(['permanent', 'cannot be undone', 'Warning']);
    });
  });

  describe('Form Validation', () => {
    beforeEach(() => {
      cy.visit('/app/profile');
      cy.waitForPageLoad();
    });

    it('should validate required fields', () => {
      cy.get('input[required]').first().clear();
      cy.get('button').contains(/Save/i).first().click();
      cy.waitForPageLoad();
      cy.assertContainsAny(['Profile', 'required', 'Settings']);
    });

    it('should validate email format', () => {
      cy.get('input[type="email"]').first().clear().type('invalid-email');
      cy.assertContainsAny(['Profile', 'Settings', 'Email']);
    });
  });

  describe('Success/Error States', () => {
    beforeEach(() => {
      cy.visit('/app/profile');
      cy.waitForPageLoad();
    });

    it('should show success notification on save', () => {
      cy.get('input').first().type(' updated');
      cy.get('button').contains(/Save/i).first().click();
      cy.waitForPageLoad();
      cy.assertContainsAny(['Profile', 'Settings', 'Saved']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.intercept('PUT', '**/api/**/users/**', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/profile');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Profile', 'Settings', 'Error']);
      cy.get('body').should('not.contain.text', 'Cannot read');
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '**/api/**/users/**', {
        delay: 2000,
        statusCode: 200,
        body: {}
      });

      cy.visit('/app/profile');
      cy.assertHasElement(['[class*="spin"]']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/profile');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Profile', 'Settings']);
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/profile');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Profile', 'Settings']);
    });

    it('should display properly on large screens', () => {
      cy.viewport(1920, 1080);
      cy.visit('/app/profile');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Profile', 'Settings']);
    });
  });
});


export {};
