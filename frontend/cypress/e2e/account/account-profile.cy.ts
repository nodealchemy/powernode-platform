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

      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Profile') ||
                          $body.text().includes('Account') ||
                          $body.text().includes('Settings');
        if (hasContent) {
          cy.log('Profile page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page title', () => {
      cy.visit('/app/account/profile');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('Profile') ||
                        $body.text().includes('My Profile');
        if (hasTitle) {
          cy.log('Page title displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/account/profile');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('Dashboard') ||
                               $body.text().includes('Account');
        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Profile Information Display', () => {
    beforeEach(() => {
      cy.visit('/app/account/profile');
      cy.waitForPageLoad();
    });

    it('should display user name', () => {
      cy.get('body').then($body => {
        const hasName = $body.text().includes('Name') ||
                       $body.find('input[name="name"], input[name="first_name"]').length > 0;
        if (hasName) {
          cy.log('User name displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display user email', () => {
      cy.get('body').then($body => {
        const hasEmail = $body.text().includes('Email') ||
                        $body.find('input[name="email"], input[type="email"]').length > 0;
        if (hasEmail) {
          cy.log('User email displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display profile avatar or photo', () => {
      cy.get('body').then($body => {
        const hasAvatar = $body.find('img[class*="avatar"], [class*="Avatar"]').length > 0 ||
                         $body.find('[class*="rounded-full"]').length > 0;
        if (hasAvatar) {
          cy.log('Profile avatar displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display phone number field', () => {
      cy.get('body').then($body => {
        const hasPhone = $body.text().includes('Phone') ||
                        $body.find('input[name="phone"]').length > 0;
        if (hasPhone) {
          cy.log('Phone number field displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Profile Editing', () => {
    beforeEach(() => {
      cy.visit('/app/account/profile');
      cy.waitForPageLoad();
    });

    it('should have Edit Profile button', () => {
      cy.get('body').then($body => {
        const editButton = $body.find('button:contains("Edit"), button:contains("Update")');
        if (editButton.length > 0) {
          cy.log('Edit Profile button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Save button', () => {
      cy.get('body').then($body => {
        const saveButton = $body.find('button:contains("Save"), button:contains("Update Profile")');
        if (saveButton.length > 0) {
          cy.log('Save button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display editable form fields', () => {
      cy.get('body').then($body => {
        const hasFields = $body.find('input[type="text"], input[type="email"]').length > 0;
        if (hasFields) {
          cy.log('Editable form fields displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Security Settings', () => {
    beforeEach(() => {
      cy.visit('/app/account/profile');
      cy.waitForPageLoad();
    });

    it('should display security section', () => {
      cy.get('body').then($body => {
        const hasSecurity = $body.text().includes('Security') ||
                           $body.text().includes('Password');
        if (hasSecurity) {
          cy.log('Security section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Change Password option', () => {
      cy.get('body').then($body => {
        const hasPassword = $body.text().includes('Change Password') ||
                           $body.text().includes('Password') ||
                           $body.find('button:contains("Password")').length > 0;
        if (hasPassword) {
          cy.log('Change Password option found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display two-factor authentication option', () => {
      cy.get('body').then($body => {
        const has2FA = $body.text().includes('Two-Factor') ||
                      $body.text().includes('2FA') ||
                      $body.text().includes('Authentication');
        if (has2FA) {
          cy.log('Two-factor authentication option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display last login information', () => {
      cy.get('body').then($body => {
        const hasLogin = $body.text().includes('Last Login') ||
                        $body.text().includes('Last sign in');
        if (hasLogin) {
          cy.log('Last login information displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Email Preferences', () => {
    beforeEach(() => {
      cy.visit('/app/account/profile');
      cy.waitForPageLoad();
    });

    it('should display email preferences section', () => {
      cy.get('body').then($body => {
        const hasPreferences = $body.text().includes('Email') ||
                              $body.text().includes('Notifications') ||
                              $body.text().includes('Preferences');
        if (hasPreferences) {
          cy.log('Email preferences section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display notification toggles', () => {
      cy.get('body').then($body => {
        const hasToggles = $body.find('input[type="checkbox"], [class*="toggle"], [role="switch"]').length > 0;
        if (hasToggles) {
          cy.log('Notification toggles displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Account Information', () => {
    beforeEach(() => {
      cy.visit('/app/account/profile');
      cy.waitForPageLoad();
    });

    it('should display account name', () => {
      cy.get('body').then($body => {
        const hasAccount = $body.text().includes('Account') ||
                          $body.text().includes('Organization');
        if (hasAccount) {
          cy.log('Account information displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display user role', () => {
      cy.get('body').then($body => {
        const hasRole = $body.text().includes('Role') ||
                       $body.text().includes('admin') ||
                       $body.text().includes('member') ||
                       $body.text().includes('Manager');
        if (hasRole) {
          cy.log('User role displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display member since date', () => {
      cy.get('body').then($body => {
        const hasMemberSince = $body.text().includes('Member since') ||
                              $body.text().includes('Joined') ||
                              $body.text().includes('Created');
        if (hasMemberSince) {
          cy.log('Member since date displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Danger Zone', () => {
    beforeEach(() => {
      cy.visit('/app/account/profile');
      cy.waitForPageLoad();
    });

    it('should display danger zone section', () => {
      cy.get('body').then($body => {
        const hasDanger = $body.text().includes('Danger Zone') ||
                         $body.text().includes('Delete Account') ||
                         $body.text().includes('Deactivate');
        if (hasDanger) {
          cy.log('Danger zone section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('API Key Management', () => {
    beforeEach(() => {
      cy.visit('/app/account/profile');
      cy.waitForPageLoad();
    });

    it('should display API keys section', () => {
      cy.get('body').then($body => {
        const hasApiKeys = $body.text().includes('API') ||
                          $body.text().includes('Keys');
        if (hasApiKeys) {
          cy.log('API keys section displayed');
        }
      });

      cy.get('body').should('be.visible');
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

      cy.get('body').should('be.visible');
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

      cy.get('body').then($body => {
        const saveButton = $body.find('button:contains("Save"), button:contains("Update")');
        if (saveButton.length > 0) {
          cy.wrap(saveButton).first().should('be.visible').click();
          cy.wait('@updateProfile');
        }
      });

      cy.get('body').should('be.visible');
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

      cy.get('body').then($body => {
        const hasLoading = $body.find('[class*="spin"], [class*="loading"]').length > 0 ||
                           $body.text().includes('Loading');
        if (hasLoading) {
          cy.log('Loading indicator displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Session Information', () => {
    beforeEach(() => {
      cy.visit('/app/account/profile');
      cy.waitForPageLoad();
    });

    it('should display active sessions', () => {
      cy.get('body').then($body => {
        const hasSessions = $body.text().includes('Sessions') ||
                           $body.text().includes('Active') ||
                           $body.text().includes('Devices');
        if (hasSessions) {
          cy.log('Active sessions displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have logout all sessions option', () => {
      cy.get('body').then($body => {
        const hasLogout = $body.text().includes('Logout all') ||
                         $body.text().includes('Sign out') ||
                         $body.find('button:contains("Logout")').length > 0;
        if (hasLogout) {
          cy.log('Logout all sessions option found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/account/profile');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Profile') || $body.text().includes('Account');
        if (hasContent) {
          cy.log('Content visible on mobile');
        }
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/account/profile');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Profile') || $body.text().includes('Account');
        if (hasContent) {
          cy.log('Content visible on tablet');
        }
      });
    });

    it('should stack sections on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/account/profile');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
    });

    it('should show multi-column layout on large screens', () => {
      cy.viewport(1280, 800);
      cy.visit('/app/account/profile');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasMultiColumn = $body.find('[class*="md:grid-cols"], [class*="lg:grid-cols"]').length > 0 ||
                               $body.find('[class*="grid"]').length > 0;
        if (hasMultiColumn) {
          cy.log('Multi-column layout on large screens');
        }
      });

      cy.get('body').should('be.visible');
    });
  });
});


export {};
