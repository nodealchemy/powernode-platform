/// <reference types="cypress" />

/**
 * OAuth Authorization Consent Page Tests
 *
 * Tests for the OAuthConsentPage at /app/oauth/authorize.
 * This page displays an OAuth consent form where users approve
 * or deny third-party application access to their account.
 */

describe('OAuth Authorization Consent Tests', () => {
  const oauthParams = {
    client_id: 'test-client-id',
    redirect_uri: 'https://example.com/callback',
    scope: 'read write',
    response_type: 'code',
    state: 'test-csrf-state',
  };

  const oauthUrl = `/app/oauth/authorize?client_id=${oauthParams.client_id}&redirect_uri=${encodeURIComponent(oauthParams.redirect_uri)}&scope=${oauthParams.scope}&response_type=${oauthParams.response_type}&state=${oauthParams.state}`;

  beforeEach(() => {
    cy.standardTestSetup();

    // Mock OAuth application lookup
    cy.intercept('GET', '**/oauth/applications/lookup*', {
      statusCode: 200,
      body: {
        data: {
          name: 'Test Application',
          uid: oauthParams.client_id,
        },
      },
    }).as('lookupApp');

    // Mock OAuth authorize endpoint
    cy.intercept('POST', '**/oauth/authorize', {
      statusCode: 200,
      body: {
        redirect_uri: `${oauthParams.redirect_uri}?code=test-auth-code&state=${oauthParams.state}`,
      },
    }).as('authorizeApp');
  });

  describe('Page Load', () => {
    it('should load the OAuth consent page', () => {
      cy.visit(oauthUrl);
      cy.waitForPageLoad();
      cy.assertContainsAny(['Authorization', 'Request', 'access']);
    });

    it('should display authorization request heading', () => {
      cy.visit(oauthUrl);
      cy.waitForPageLoad();
      cy.assertContainsAny(['Authorization Request', 'Authorization']);
    });

    it('should display application name', () => {
      cy.visit(oauthUrl);
      cy.wait('@lookupApp');
      cy.assertContainsAny(['Test Application', 'wants to access']);
    });

    it('should display user info', () => {
      cy.visit(oauthUrl);
      cy.waitForPageLoad();
      cy.assertContainsAny(['Signed in as', 'email', '@']);
    });
  });

  describe('Scope Display', () => {
    it('should display requested permissions', () => {
      cy.visit(oauthUrl);
      cy.waitForPageLoad();
      cy.assertContainsAny(['Read access', 'Create and modify', 'read', 'write']);
    });

    it('should display scope descriptions', () => {
      cy.visit(oauthUrl);
      cy.waitForPageLoad();
      cy.assertContainsAny(['access to your data', 'modify data']);
    });

    it('should display permission icons', () => {
      cy.visit(oauthUrl);
      cy.waitForPageLoad();
      cy.assertHasElement(['svg', '[class*="icon"]', '[class*="check"]']);
    });
  });

  describe('Consent Actions', () => {
    beforeEach(() => {
      cy.visit(oauthUrl);
      cy.waitForPageLoad();
    });

    it('should have Approve button', () => {
      cy.get('button').contains(/approve/i).should('exist');
    });

    it('should have Deny button', () => {
      cy.get('button').contains(/deny/i).should('exist');
    });

    it('should submit approval when Approve clicked', () => {
      cy.get('button').contains(/approve/i).click();
      cy.wait('@authorizeApp');
    });

    it('should redirect on deny', () => {
      cy.get('button').contains(/deny/i).click();
      // Should redirect to callback with error
      cy.url().should('not.include', '/oauth/authorize');
    });
  });

  describe('Missing Parameters', () => {
    it('should show error when client_id is missing', () => {
      cy.visit('/app/oauth/authorize?redirect_uri=https://example.com/callback');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Missing', 'client_id', 'error', 'Error']);
    });
  });

  describe('Authentication Check', () => {
    it('should redirect unauthenticated users to login', () => {
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit(oauthUrl, { failOnStatusCode: false });
      cy.url().should('match', /\/(login|signin|auth)/);
    });
  });

  describe('Error Handling', () => {
    it('should handle application lookup failure gracefully', () => {
      cy.intercept('GET', '**/oauth/applications/lookup*', {
        statusCode: 404,
        body: { error: 'Application not found' },
      }).as('lookupFailed');

      cy.visit(oauthUrl);
      cy.waitForPageLoad();
      // Should fallback to showing client_id as app name
      cy.assertContainsAny(['Authorization', 'test-client-id', 'Request']);
    });

    it('should handle authorization failure', () => {
      cy.intercept('POST', '**/oauth/authorize', {
        statusCode: 500,
        body: { error: 'server_error', error_description: 'Authorization failed' },
      }).as('authorizeFailed');

      cy.visit(oauthUrl);
      cy.waitForPageLoad();
      cy.get('button').contains(/approve/i).click();
      cy.wait('@authorizeFailed');
      cy.assertContainsAny(['Error', 'Failed', 'error', 'Authorization failed']);
    });
  });

  describe('PKCE Support', () => {
    it('should handle PKCE parameters', () => {
      const pkceUrl = `${oauthUrl}&code_challenge=test-challenge&code_challenge_method=S256`;
      cy.visit(pkceUrl);
      cy.waitForPageLoad();
      cy.assertContainsAny(['Authorization Request', 'Authorization']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit(oauthUrl);
      cy.waitForPageLoad();
      cy.assertContainsAny(['Authorization', 'Approve', 'Deny']);
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit(oauthUrl);
      cy.waitForPageLoad();
      cy.assertContainsAny(['Authorization', 'Approve', 'Deny']);
    });
  });
});

export {};
