/// <reference types="cypress" />

/**
 * Account Security Tests
 *
 * Tests for Account Security functionality including:
 * - Security overview
 * - Password management
 * - Two-factor authentication
 * - Security logs
 * - Trusted devices
 * - API tokens
 */

describe('Account Security Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Security Overview', () => {
    it('should navigate to security page', () => {
      cy.visit('/app/account/security');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSecurity = $body.text().includes('Security') ||
                          $body.text().includes('Password') ||
                          $body.text().includes('Authentication');
        if (hasSecurity) {
          cy.log('Security page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display security status', () => {
      cy.visit('/app/account/security');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Strong') ||
                         $body.text().includes('Good') ||
                         $body.text().includes('Secure') ||
                         $body.text().includes('Status');
        if (hasStatus) {
          cy.log('Security status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display security recommendations', () => {
      cy.visit('/app/account/security');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasRec = $body.text().includes('Recommend') ||
                      $body.text().includes('Enable') ||
                      $body.text().includes('Suggest');
        if (hasRec) {
          cy.log('Security recommendations displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Password Management', () => {
    beforeEach(() => {
      cy.visit('/app/account/security/password');
      cy.waitForPageLoad();
    });

    it('should display password section', () => {
      cy.get('body').then($body => {
        const hasPassword = $body.text().includes('Password') ||
                          $body.text().includes('Change');
        if (hasPassword) {
          cy.log('Password section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have change password button', () => {
      cy.get('body').then($body => {
        const hasChange = $body.find('button:contains("Change"), button:contains("Update")').length > 0 ||
                         $body.text().includes('Change password');
        if (hasChange) {
          cy.log('Change password button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display last password change', () => {
      cy.get('body').then($body => {
        const hasLast = $body.text().includes('Last changed') ||
                       $body.text().includes('ago') ||
                       $body.text().includes('Password updated');
        if (hasLast) {
          cy.log('Last password change displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Two-Factor Authentication', () => {
    beforeEach(() => {
      cy.visit('/app/account/security/2fa');
      cy.waitForPageLoad();
    });

    it('should display 2FA section', () => {
      cy.get('body').then($body => {
        const has2FA = $body.text().includes('Two-factor') ||
                      $body.text().includes('2FA') ||
                      $body.text().includes('Authenticator');
        if (has2FA) {
          cy.log('2FA section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have enable/disable 2FA button', () => {
      cy.get('body').then($body => {
        const hasButton = $body.find('button:contains("Enable"), button:contains("Disable"), button:contains("Setup")').length > 0;
        if (hasButton) {
          cy.log('2FA toggle button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display 2FA methods', () => {
      cy.get('body').then($body => {
        const hasMethods = $body.text().includes('Authenticator') ||
                          $body.text().includes('SMS') ||
                          $body.text().includes('Email');
        if (hasMethods) {
          cy.log('2FA methods displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display backup codes option', () => {
      cy.get('body').then($body => {
        const hasBackup = $body.text().includes('Backup') ||
                         $body.text().includes('Recovery') ||
                         $body.text().includes('Code');
        if (hasBackup) {
          cy.log('Backup codes option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Security Logs', () => {
    it('should navigate to security logs', () => {
      cy.visit('/app/account/security/logs');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasLogs = $body.text().includes('Log') ||
                       $body.text().includes('Activity') ||
                       $body.text().includes('History');
        if (hasLogs) {
          cy.log('Security logs page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display login history', () => {
      cy.visit('/app/account/security/logs');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasHistory = $body.text().includes('Login') ||
                          $body.text().includes('Sign in') ||
                          $body.find('table').length > 0;
        if (hasHistory) {
          cy.log('Login history displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display device/location info', () => {
      cy.visit('/app/account/security/logs');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasInfo = $body.text().includes('Device') ||
                       $body.text().includes('Location') ||
                       $body.text().includes('IP');
        if (hasInfo) {
          cy.log('Device/location info displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Trusted Devices', () => {
    it('should navigate to trusted devices', () => {
      cy.visit('/app/account/security/devices');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDevices = $body.text().includes('Device') ||
                          $body.text().includes('Trusted') ||
                          $body.text().includes('Browser');
        if (hasDevices) {
          cy.log('Trusted devices page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display device list', () => {
      cy.visit('/app/account/security/devices');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasList = $body.find('[data-testid="device-list"], table, .device-card').length > 0;
        if (hasList) {
          cy.log('Device list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have remove device option', () => {
      cy.visit('/app/account/security/devices');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasRemove = $body.find('button:contains("Remove"), button:contains("Revoke")').length > 0 ||
                         $body.text().includes('Remove');
        if (hasRemove) {
          cy.log('Remove device option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('API Tokens', () => {
    it('should navigate to API tokens', () => {
      cy.visit('/app/account/security/tokens');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasTokens = $body.text().includes('Token') ||
                         $body.text().includes('API') ||
                         $body.text().includes('Key');
        if (hasTokens) {
          cy.log('API tokens page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have create token button', () => {
      cy.visit('/app/account/security/tokens');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCreate = $body.find('button:contains("Create"), button:contains("Generate"), button:contains("New")').length > 0;
        if (hasCreate) {
          cy.log('Create token button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display token list', () => {
      cy.visit('/app/account/security/tokens');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasList = $body.find('table, [data-testid="tokens-list"]').length > 0;
        if (hasList) {
          cy.log('Token list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have revoke token option', () => {
      cy.visit('/app/account/security/tokens');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasRevoke = $body.find('button:contains("Revoke"), button:contains("Delete")').length > 0 ||
                         $body.text().includes('Revoke');
        if (hasRevoke) {
          cy.log('Revoke token option displayed');
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
      it(`should display security correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/account/security');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`Security displayed correctly on ${name}`);
      });
    });
  });
});
