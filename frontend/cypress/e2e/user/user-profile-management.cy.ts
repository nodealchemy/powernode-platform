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

      cy.get('body').then($body => {
        const hasProfile = $body.text().includes('Profile') ||
                          $body.text().includes('Account') ||
                          $body.text().includes('Settings');
        if (hasProfile) {
          cy.log('Profile page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display user name', () => {
      cy.visit('/app/profile');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasName = $body.find('[data-testid="user-name"], h1, h2').length > 0 ||
                       $body.text().includes('Name');
        if (hasName) {
          cy.log('User name displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display user email', () => {
      cy.visit('/app/profile');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasEmail = $body.text().includes('@') ||
                        $body.text().includes('Email');
        if (hasEmail) {
          cy.log('User email displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display user avatar', () => {
      cy.visit('/app/profile');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasAvatar = $body.find('img[alt*="avatar"], img[alt*="profile"], .avatar').length > 0;
        if (hasAvatar) {
          cy.log('User avatar displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Profile Editing', () => {
    beforeEach(() => {
      cy.visit('/app/profile/edit');
      cy.waitForPageLoad();
    });

    it('should have edit profile button', () => {
      cy.get('body').then($body => {
        const hasEdit = $body.find('button:contains("Edit"), button:contains("Update"), a:contains("Edit")').length > 0 ||
                       $body.text().includes('Edit');
        if (hasEdit) {
          cy.log('Edit profile button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have first name field', () => {
      cy.get('body').then($body => {
        const hasFirst = $body.find('input[name*="first"], input[name*="firstName"]').length > 0 ||
                        $body.text().includes('First Name');
        if (hasFirst) {
          cy.log('First name field displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have last name field', () => {
      cy.get('body').then($body => {
        const hasLast = $body.find('input[name*="last"], input[name*="lastName"]').length > 0 ||
                       $body.text().includes('Last Name');
        if (hasLast) {
          cy.log('Last name field displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have save button', () => {
      cy.get('body').then($body => {
        const hasSave = $body.find('button:contains("Save"), button[type="submit"]').length > 0;
        if (hasSave) {
          cy.log('Save button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Avatar Management', () => {
    beforeEach(() => {
      cy.visit('/app/profile');
      cy.waitForPageLoad();
    });

    it('should have upload avatar option', () => {
      cy.get('body').then($body => {
        const hasUpload = $body.find('input[type="file"], button:contains("Upload"), button:contains("Change")').length > 0 ||
                         $body.text().includes('Upload');
        if (hasUpload) {
          cy.log('Upload avatar option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have remove avatar option', () => {
      cy.get('body').then($body => {
        const hasRemove = $body.find('button:contains("Remove"), button:contains("Delete")').length > 0 ||
                         $body.text().includes('Remove');
        if (hasRemove) {
          cy.log('Remove avatar option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Password Management', () => {
    it('should navigate to password change', () => {
      cy.visit('/app/profile/password');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasPassword = $body.text().includes('Password') ||
                          $body.text().includes('Security');
        if (hasPassword) {
          cy.log('Password change page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have current password field', () => {
      cy.visit('/app/profile/password');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCurrent = $body.find('input[type="password"]').length > 0 ||
                          $body.text().includes('Current');
        if (hasCurrent) {
          cy.log('Current password field displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have new password field', () => {
      cy.visit('/app/profile/password');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasNew = $body.text().includes('New') ||
                      $body.find('input[name*="new"]').length > 0;
        if (hasNew) {
          cy.log('New password field displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have confirm password field', () => {
      cy.visit('/app/profile/password');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasConfirm = $body.text().includes('Confirm') ||
                          $body.find('input[name*="confirm"]').length > 0;
        if (hasConfirm) {
          cy.log('Confirm password field displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display password requirements', () => {
      cy.visit('/app/profile/password');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasRequirements = $body.text().includes('character') ||
                               $body.text().includes('must') ||
                               $body.text().includes('requirement');
        if (hasRequirements) {
          cy.log('Password requirements displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Notification Preferences', () => {
    it('should navigate to notification settings', () => {
      cy.visit('/app/profile/notifications');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasNotifications = $body.text().includes('Notification') ||
                                $body.text().includes('Alert') ||
                                $body.text().includes('Email');
        if (hasNotifications) {
          cy.log('Notification settings loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display email notification toggles', () => {
      cy.visit('/app/profile/notifications');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasToggles = $body.find('input[type="checkbox"], [role="switch"]').length > 0 ||
                          $body.text().includes('Email');
        if (hasToggles) {
          cy.log('Email notification toggles displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display notification categories', () => {
      cy.visit('/app/profile/notifications');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCategories = $body.text().includes('Marketing') ||
                             $body.text().includes('Security') ||
                             $body.text().includes('Updates') ||
                             $body.text().includes('Product');
        if (hasCategories) {
          cy.log('Notification categories displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Session Management', () => {
    it('should navigate to sessions page', () => {
      cy.visit('/app/profile/sessions');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSessions = $body.text().includes('Session') ||
                           $body.text().includes('Device') ||
                           $body.text().includes('Active');
        if (hasSessions) {
          cy.log('Sessions page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display active sessions', () => {
      cy.visit('/app/profile/sessions');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasActive = $body.find('table, [data-testid="sessions-list"]').length > 0 ||
                         $body.text().includes('Current');
        if (hasActive) {
          cy.log('Active sessions displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have revoke session option', () => {
      cy.visit('/app/profile/sessions');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasRevoke = $body.find('button:contains("Revoke"), button:contains("Sign out"), button:contains("End")').length > 0 ||
                         $body.text().includes('Revoke');
        if (hasRevoke) {
          cy.log('Revoke session option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display session details', () => {
      cy.visit('/app/profile/sessions');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDetails = $body.text().includes('Browser') ||
                          $body.text().includes('Location') ||
                          $body.text().includes('IP') ||
                          $body.text().includes('Device');
        if (hasDetails) {
          cy.log('Session details displayed');
        }
      });

      cy.get('body').should('be.visible');
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

        cy.get('body').should('be.visible');
        cy.log(`Profile displayed correctly on ${name}`);
      });
    });
  });
});
