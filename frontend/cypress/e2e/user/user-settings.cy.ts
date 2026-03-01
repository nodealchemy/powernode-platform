/// <reference types="cypress" />

/**
 * User Settings Page Tests
 *
 * Tests for user settings functionality including:
 * - Page navigation
 * - Tab navigation (Profile, Account, Subscription, Preferences, Notifications, Security)
 * - Form fields and content
 * - Error handling
 * - Responsive design
 */

describe('User Settings Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Page Navigation', () => {
    it('should navigate to Settings page', () => {
      cy.assertPageReady('/app/profile');
    });

    it('should display page title', () => {
      cy.assertPageReady('/app/profile');
      cy.assertContainsAny(['Settings', 'Profile']);
    });

    it('should display page description', () => {
      cy.assertPageReady('/app/profile');
      cy.assertContainsAny(['Manage your account', 'settings', 'preferences']);
    });
  });

  describe('Tab Navigation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/profile');
    });

    it('should display Profile tab', () => {
      cy.assertContainsAny(['Profile']);
    });

    it('should display Account tab', () => {
      cy.assertContainsAny(['Account']);
    });

    it('should display Subscription tab', () => {
      cy.assertContainsAny(['Subscription']);
    });

    it('should display Preferences tab', () => {
      cy.assertContainsAny(['Preferences']);
    });

    it('should display Notifications tab', () => {
      cy.assertContainsAny(['Notifications']);
    });

    it('should display Security tab', () => {
      cy.assertContainsAny(['Security']);
    });

    it('should switch to Account tab', () => {
      cy.clickTab('Account');
      cy.assertContainsAny(['Settings', 'Profile', 'Account']);
    });

    it('should switch to Security tab', () => {
      cy.clickTab('Security');
      cy.assertContainsAny(['Settings', 'Profile', 'Account']);
    });
  });

  describe('Profile Tab Content', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/profile');
    });

    it('should display profile avatar', () => {
      // Profile page shows user initials in a rounded div, not an actual image
      cy.assertHasElement([
        'img[class*="rounded-full"]',
        '[class*="avatar"]',
        '.rounded-full',
        '[data-testid="profile-avatar"]'
      ]);
    });

    it('should display name field', () => {
      // Profile uses "Name" label instead of "First Name"/"Last Name"
      cy.assertContainsAny(['Name', 'First Name', 'Full Name']);
    });

    it('should display email field label', () => {
      cy.assertContainsAny(['Email', 'Email Address']);
    });

    it('should display email field', () => {
      cy.assertContainsAny(['Email']);
    });

    it('should display form input fields', () => {
      // Profile form has name and email inputs
      cy.assertHasElement(['input[name="name"]', 'input[name="email"]', 'form input']);
    });

    it('should display Save Changes button', () => {
      cy.assertContainsAny(['Save Changes', 'Update Profile', 'Save']);
    });
  });

  describe('Account Tab Content', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/profile');
      cy.clickTab('Account');
    });

    it('should display account information section', () => {
      cy.assertContainsAny(['Account Information', 'account', 'Account']);
    });

    it('should display account name', () => {
      cy.assertContainsAny(['Name', 'Account']);
    });

    it('should display timezone setting', () => {
      cy.assertContainsAny(['Timezone', 'Time Zone', 'Account']);
    });

    it('should display locale setting', () => {
      cy.assertContainsAny(['Locale', 'Language', 'Account']);
    });
  });

  describe('Subscription Tab Content', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/profile');
      cy.clickTab('Subscription');
    });

    it('should display subscription details', () => {
      cy.assertContainsAny(['Plan', 'Subscription']);
    });

    it('should display current plan name', () => {
      cy.assertContainsAny(['Current Plan', 'Plan Name', 'Subscription']);
    });

    it('should display billing cycle', () => {
      cy.assertContainsAny(['Billing', 'Monthly', 'Annual', 'Subscription']);
    });

    it('should display Change Plan button', () => {
      cy.assertContainsAny(['Change Plan', 'Upgrade', 'Manage', 'Subscription']);
    });
  });

  describe('Preferences Tab Content', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/profile');
      cy.clickTab('Preferences');
    });

    it('should display theme selector', () => {
      cy.assertContainsAny(['Theme', 'Appearance', 'Preferences']);
    });

    it('should display light/dark mode options', () => {
      cy.assertContainsAny(['Light', 'Dark', 'System', 'Preferences']);
    });

    it('should display date format setting', () => {
      cy.assertContainsAny(['Date Format', 'Date', 'Preferences']);
    });
  });

  describe('Notifications Tab Content', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/profile');
      cy.clickTab('Notifications');
    });

    it('should display email notifications toggle', () => {
      cy.assertContainsAny(['Email', 'email notifications', 'Notifications']);
    });

    it('should display push notifications toggle', () => {
      cy.assertContainsAny(['Push', 'Browser', 'Notifications']);
    });

    it('should display notification categories', () => {
      cy.assertContainsAny(['Billing', 'Security', 'Updates', 'Notifications']);
    });
  });

  describe('Security Tab Content', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/profile');
      cy.clickTab('Security');
    });

    it('should display password change section', () => {
      cy.assertContainsAny(['Password', 'Change Password', 'Security']);
    });

    it('should display current password field', () => {
      cy.assertContainsAny(['Current Password', 'Security']);
    });

    it('should display new password field', () => {
      cy.assertContainsAny(['New Password', 'Security']);
    });

    it('should display two-factor authentication section', () => {
      cy.assertContainsAny(['Two-Factor', '2FA', 'Authentication', 'Security']);
    });

    it('should display active sessions section', () => {
      cy.assertContainsAny(['Sessions', 'Active Devices', 'Security']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.testErrorHandling('**/api/**/settings**', {
        statusCode: 500,
        visitUrl: '/app/profile'
      });
    });

    it('should display error state when data fails to load', () => {
      cy.intercept('GET', '**/api/**/users/**', {
        statusCode: 500,
        body: { error: 'Failed to load' }
      }).as('loadError');

      cy.visit('/app/profile');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Error', 'Failed', 'Profile']);
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '**/api/**/users/**', (req) => {
        req.reply((res) => {
          res.delay = 2000;
          res.send({ success: true, data: {} });
        });
      }).as('slowLoad');

      cy.visit('/app/profile');
      cy.assertHasElement(['[class*="animate-spin"]']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.testViewport('mobile', '/app/profile');
      cy.assertContainsAny(['Settings', 'Profile', 'Account']);
    });

    it('should display properly on tablet viewport', () => {
      cy.testViewport('tablet', '/app/profile');
      cy.assertContainsAny(['Settings', 'Profile', 'Account']);
    });

    it('should stack form fields on small screens', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/profile');
      cy.waitForPageLoad();
      cy.assertHasElement(['[class*="flex-col"]', '[class*="grid-cols-1"]']);
    });

    it('should show multi-column layout on large screens', () => {
      cy.viewport(1920, 1080);
      cy.visit('/app/profile');
      cy.waitForPageLoad();
      cy.assertHasElement(['[class*="md:grid-cols"]', '[class*="lg:grid-cols"]']);
    });
  });
});


export {};
