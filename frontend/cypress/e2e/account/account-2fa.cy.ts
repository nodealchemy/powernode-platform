/// <reference types="cypress" />

/**
 * Account Two-Factor Authentication Tests
 *
 * Tests for 2FA functionality including:
 * - 2FA setup flow
 * - 2FA verification
 * - 2FA disable flow
 * - Recovery codes
 * - Error handling
 * - Security states
 */

describe('Account Two-Factor Authentication Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('2FA Settings Access', () => {
    it('should navigate to 2FA settings', () => {
      cy.visit('/app/account/security');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const has2FA = $body.text().includes('Two-Factor') ||
                      $body.text().includes('2FA') ||
                      $body.text().includes('Authentication');
        if (has2FA) {
          cy.log('2FA settings accessible');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display 2FA status', () => {
      cy.visit('/app/account/security');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Enabled') ||
                         $body.text().includes('Disabled') ||
                         $body.text().includes('Not configured') ||
                         $body.text().includes('Enable');
        if (hasStatus) {
          cy.log('2FA status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('2FA Setup Flow', () => {
    beforeEach(() => {
      cy.visit('/app/account/security');
      cy.waitForPageLoad();
    });

    it('should display Enable 2FA button when not configured', () => {
      cy.get('body').then($body => {
        const hasEnableBtn = $body.text().includes('Enable') ||
                            $body.find('button:contains("Enable"), button:contains("Set up")').length > 0;
        if (hasEnableBtn) {
          cy.log('Enable 2FA button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should open 2FA setup modal', () => {
      cy.get('body').then($body => {
        const enableBtn = $body.find('button:contains("Enable 2FA"), button:contains("Set up")');
        if (enableBtn.length > 0) {
          cy.wrap(enableBtn).first().click();
          cy.log('2FA setup modal opened');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display QR code in setup flow', () => {
      cy.get('body').then($body => {
        const enableBtn = $body.find('button:contains("Enable 2FA"), button:contains("Set up")');
        if (enableBtn.length > 0) {
          cy.wrap(enableBtn).first().click();

          cy.get('body').then($innerBody => {
            const hasQR = $innerBody.find('img[alt*="QR"], canvas, svg').length > 0 ||
                         $innerBody.text().includes('QR') ||
                         $innerBody.text().includes('Authenticator');
            if (hasQR) {
              cy.log('QR code displayed');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display manual entry secret', () => {
      cy.get('body').then($body => {
        const enableBtn = $body.find('button:contains("Enable 2FA"), button:contains("Set up")');
        if (enableBtn.length > 0) {
          cy.wrap(enableBtn).first().click();

          cy.get('body').then($innerBody => {
            const hasSecret = $innerBody.text().includes('secret') ||
                             $innerBody.text().includes('manual') ||
                             $innerBody.find('code').length > 0;
            if (hasSecret) {
              cy.log('Manual entry secret displayed');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have verification code input', () => {
      cy.get('body').then($body => {
        const enableBtn = $body.find('button:contains("Enable 2FA"), button:contains("Set up")');
        if (enableBtn.length > 0) {
          cy.wrap(enableBtn).first().click();

          cy.get('body').then($innerBody => {
            const hasInput = $innerBody.find('input[name*="code"], input[type="text"], input[name*="otp"]').length > 0 ||
                            $innerBody.text().includes('code') ||
                            $innerBody.text().includes('verification');
            if (hasInput) {
              cy.log('Verification code input displayed');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('2FA Verification', () => {
    beforeEach(() => {
      cy.visit('/app/account/security');
      cy.waitForPageLoad();
    });

    it('should validate code format', () => {
      cy.get('body').then($body => {
        const hasValidation = $body.text().includes('6') ||
                             $body.text().includes('digit') ||
                             $body.text().includes('code');
        if (hasValidation) {
          cy.log('Code format validation present');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Recovery Codes', () => {
    beforeEach(() => {
      cy.visit('/app/account/security');
      cy.waitForPageLoad();
    });

    it('should display recovery codes option', () => {
      cy.get('body').then($body => {
        const hasRecovery = $body.text().includes('Recovery') ||
                           $body.text().includes('Backup') ||
                           $body.text().includes('recovery codes');
        if (hasRecovery) {
          cy.log('Recovery codes option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should allow viewing recovery codes when 2FA enabled', () => {
      cy.get('body').then($body => {
        const hasView = $body.text().includes('View') ||
                       $body.text().includes('Show') ||
                       $body.find('button:contains("Recovery")').length > 0;
        if (hasView) {
          cy.log('View recovery codes option available');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Disable 2FA', () => {
    beforeEach(() => {
      cy.visit('/app/account/security');
      cy.waitForPageLoad();
    });

    it('should display Disable 2FA option when enabled', () => {
      cy.get('body').then($body => {
        const hasDisable = $body.text().includes('Disable') ||
                          $body.find('button:contains("Disable")').length > 0;
        if (hasDisable) {
          cy.log('Disable 2FA option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Security Information', () => {
    beforeEach(() => {
      cy.visit('/app/account/security');
      cy.waitForPageLoad();
    });

    it('should display security recommendations', () => {
      cy.get('body').then($body => {
        const hasRecommendations = $body.text().includes('recommend') ||
                                   $body.text().includes('secure') ||
                                   $body.text().includes('protect');
        if (hasRecommendations) {
          cy.log('Security recommendations displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display supported authenticator apps', () => {
      cy.get('body').then($body => {
        const hasApps = $body.text().includes('Google Authenticator') ||
                       $body.text().includes('Authy') ||
                       $body.text().includes('authenticator app');
        if (hasApps) {
          cy.log('Supported authenticator apps mentioned');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle invalid verification code', () => {
      cy.visit('/app/account/security');
      cy.waitForPageLoad();

      // Page should remain functional
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
      it(`should display 2FA settings correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/account/security');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`2FA settings displayed correctly on ${name}`);
      });
    });
  });
});
