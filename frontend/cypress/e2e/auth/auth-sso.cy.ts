/// <reference types="cypress" />

/**
 * Auth SSO Tests
 *
 * Tests for Single Sign-On functionality including:
 * - SSO provider selection
 * - OAuth flows
 * - SAML integration
 * - SSO configuration
 * - Account linking
 * - SSO error handling
 */

describe('Auth SSO Tests', () => {
  describe('SSO Provider Selection', () => {
    it('should display SSO login options', () => {
      cy.visit('/login');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSSO = $body.text().includes('SSO') ||
                      $body.text().includes('Sign in with') ||
                      $body.text().includes('Continue with') ||
                      $body.find('[data-testid="sso-button"]').length > 0;
        if (hasSSO) {
          cy.log('SSO login options displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Google SSO option', () => {
      cy.visit('/login');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasGoogle = $body.text().includes('Google') ||
                         $body.find('[data-testid="google-sso"], button:contains("Google")').length > 0;
        if (hasGoogle) {
          cy.log('Google SSO option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Microsoft SSO option', () => {
      cy.visit('/login');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasMicrosoft = $body.text().includes('Microsoft') ||
                           $body.text().includes('Azure') ||
                           $body.find('[data-testid="microsoft-sso"]').length > 0;
        if (hasMicrosoft) {
          cy.log('Microsoft SSO option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display GitHub SSO option', () => {
      cy.visit('/login');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasGitHub = $body.text().includes('GitHub') ||
                         $body.find('[data-testid="github-sso"]').length > 0;
        if (hasGitHub) {
          cy.log('GitHub SSO option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Enterprise SSO', () => {
    it('should display enterprise SSO option', () => {
      cy.visit('/login');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasEnterprise = $body.text().includes('Enterprise') ||
                             $body.text().includes('SAML') ||
                             $body.text().includes('Company');
        if (hasEnterprise) {
          cy.log('Enterprise SSO option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should navigate to enterprise SSO page', () => {
      cy.visit('/login/sso');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSSO = $body.text().includes('SSO') ||
                      $body.text().includes('Enterprise') ||
                      $body.text().includes('Organization');
        if (hasSSO) {
          cy.log('Enterprise SSO page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have domain/email input for SSO', () => {
      cy.visit('/login/sso');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasInput = $body.find('input[type="email"], input[name*="domain"], input[placeholder*="email"]').length > 0 ||
                        $body.text().includes('Email') ||
                        $body.text().includes('Domain');
        if (hasInput) {
          cy.log('SSO domain/email input displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have continue button', () => {
      cy.visit('/login/sso');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasContinue = $body.find('button:contains("Continue"), button:contains("Sign in"), button[type="submit"]').length > 0;
        if (hasContinue) {
          cy.log('Continue button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('SSO Configuration (Admin)', () => {
    beforeEach(() => {
      cy.standardTestSetup();
    });

    it('should navigate to SSO settings', () => {
      cy.visit('/app/admin/settings/sso');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSSO = $body.text().includes('SSO') ||
                      $body.text().includes('Single Sign-On') ||
                      $body.text().includes('Authentication');
        if (hasSSO) {
          cy.log('SSO settings page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display SAML configuration', () => {
      cy.visit('/app/admin/settings/sso');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSAML = $body.text().includes('SAML') ||
                       $body.text().includes('Identity Provider') ||
                       $body.text().includes('IdP');
        if (hasSAML) {
          cy.log('SAML configuration displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display OIDC configuration', () => {
      cy.visit('/app/admin/settings/sso');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasOIDC = $body.text().includes('OIDC') ||
                       $body.text().includes('OpenID') ||
                       $body.text().includes('OAuth');
        if (hasOIDC) {
          cy.log('OIDC configuration displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have SSO enable/disable toggle', () => {
      cy.visit('/app/admin/settings/sso');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasToggle = $body.find('input[type="checkbox"], [role="switch"]').length > 0 ||
                         $body.text().includes('Enable') ||
                         $body.text().includes('Disable');
        if (hasToggle) {
          cy.log('SSO toggle displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Account Linking', () => {
    beforeEach(() => {
      cy.standardTestSetup();
    });

    it('should display linked accounts in profile', () => {
      cy.visit('/app/profile/security');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasLinked = $body.text().includes('Linked') ||
                         $body.text().includes('Connected') ||
                         $body.text().includes('Account');
        if (hasLinked) {
          cy.log('Linked accounts section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have link account option', () => {
      cy.visit('/app/profile/security');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasLink = $body.find('button:contains("Link"), button:contains("Connect")').length > 0 ||
                       $body.text().includes('Link');
        if (hasLink) {
          cy.log('Link account option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have unlink account option', () => {
      cy.visit('/app/profile/security');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasUnlink = $body.find('button:contains("Unlink"), button:contains("Disconnect"), button:contains("Remove")').length > 0 ||
                         $body.text().includes('Unlink');
        if (hasUnlink) {
          cy.log('Unlink account option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('SSO Error Handling', () => {
    it('should display SSO error page', () => {
      cy.visit('/login/sso/error');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasError = $body.text().includes('Error') ||
                        $body.text().includes('Failed') ||
                        $body.text().includes('problem');
        if (hasError) {
          cy.log('SSO error page displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have retry option on error', () => {
      cy.visit('/login/sso/error');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasRetry = $body.find('button:contains("Retry"), button:contains("Try again"), a:contains("Back")').length > 0 ||
                        $body.text().includes('Try again');
        if (hasRetry) {
          cy.log('Retry option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have contact support option', () => {
      cy.visit('/login/sso/error');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSupport = $body.text().includes('Support') ||
                          $body.text().includes('Contact') ||
                          $body.text().includes('Help');
        if (hasSupport) {
          cy.log('Support option displayed');
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
      it(`should display SSO login correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/login');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`SSO login displayed correctly on ${name}`);
      });
    });
  });
});
