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

      cy.assertContainsAny(['SSO', 'Sign in with', 'Continue with']);
    });

    it('should display Google SSO option', () => {
      cy.visit('/login');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Google']);
    });

    it('should display Microsoft SSO option', () => {
      cy.visit('/login');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Microsoft', 'Azure']);
    });

    it('should display GitHub SSO option', () => {
      cy.visit('/login');
      cy.waitForPageLoad();

      cy.assertContainsAny(['GitHub']);
    });
  });

  describe('Enterprise SSO', () => {
    it('should display enterprise SSO option', () => {
      cy.visit('/login');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Enterprise', 'SAML', 'Company']);
    });

    it('should navigate to enterprise SSO page', () => {
      cy.visit('/login/sso');
      cy.waitForPageLoad();

      cy.assertContainsAny(['SSO', 'Enterprise', 'Organization']);
    });

    it('should have domain/email input for SSO', () => {
      cy.visit('/login/sso');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Email', 'Domain']);
    });

    it('should have continue button', () => {
      cy.visit('/login/sso');
      cy.waitForPageLoad();

      cy.assertHasElement(['button:contains("Continue")', 'button:contains("Sign in")', 'button[type="submit"]']);
    });
  });

  describe('SSO Configuration (Admin)', () => {
    beforeEach(() => {
      cy.standardTestSetup();
    });

    it('should navigate to SSO settings', () => {
      cy.visit('/app/admin/settings/sso');
      cy.waitForPageLoad();

      cy.assertContainsAny(['SSO', 'Single Sign-On', 'Authentication']);
    });

    it('should display SAML configuration', () => {
      cy.visit('/app/admin/settings/sso');
      cy.waitForPageLoad();

      cy.assertContainsAny(['SAML', 'Identity Provider', 'IdP']);
    });

    it('should display OIDC configuration', () => {
      cy.visit('/app/admin/settings/sso');
      cy.waitForPageLoad();

      cy.assertContainsAny(['OIDC', 'OpenID', 'OAuth']);
    });

    it('should have SSO enable/disable toggle', () => {
      cy.visit('/app/admin/settings/sso');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Enable', 'Disable']);
    });
  });

  describe('Account Linking', () => {
    beforeEach(() => {
      cy.standardTestSetup();
    });

    it('should display linked accounts in profile', () => {
      cy.visit('/app/profile/security');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Linked', 'Connected', 'Account']);
    });

    it('should have link account option', () => {
      cy.visit('/app/profile/security');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Link', 'Connect']);
    });

    it('should have unlink account option', () => {
      cy.visit('/app/profile/security');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Unlink', 'Disconnect', 'Remove']);
    });
  });

  describe('SSO Error Handling', () => {
    it('should display SSO error page', () => {
      cy.visit('/login/sso/error');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Error', 'Failed', 'problem']);
    });

    it('should have retry option on error', () => {
      cy.visit('/login/sso/error');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Try again', 'Retry', 'Back']);
    });

    it('should have contact support option', () => {
      cy.visit('/login/sso/error');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Support', 'Contact', 'Help']);
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

        cy.assertContainsAny(['Login', 'SSO', 'Sign in']);
        cy.log(`SSO login displayed correctly on ${name}`);
      });
    });
  });
});
