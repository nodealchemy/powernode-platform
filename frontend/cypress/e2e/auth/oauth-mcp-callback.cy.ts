/// <reference types="cypress" />

/**
 * MCP OAuth Callback Page E2E Tests
 *
 * Tests for the /oauth/mcp/callback route which handles OAuth authentication
 * callbacks from external MCP server providers.
 */

describe('MCP OAuth Callback Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Processing State', () => {
    it('should display processing state when callback is being processed', () => {
      // Mock the API call to delay response
      cy.intercept('GET', '/api/v1/mcp/oauth/callback*', {
        delay: 2000,
        statusCode: 200,
        body: {
          success: true,
          mcp_server_id: 'server-123',
          mcp_server_name: 'Test Server',
          oauth_connected: true,
          message: 'OAuth connected successfully',
        },
      }).as('oauthCallback');

      cy.visit('/oauth/mcp/callback?code=test-code&state=test-state');
      cy.contains('Completing authentication').should('be.visible');
    });

    it('should display MCP OAuth Authentication title', () => {
      cy.intercept('GET', '/api/v1/mcp/oauth/callback*', {
        delay: 1000,
        statusCode: 200,
        body: { success: true, mcp_server_id: 'server-123', mcp_server_name: 'Test', oauth_connected: true, message: 'OK' },
      }).as('oauthCallback');

      cy.visit('/oauth/mcp/callback?code=test-code&state=test-state');
      cy.contains('MCP OAuth Authentication').should('be.visible');
    });
  });

  describe('Success State', () => {
    beforeEach(() => {
      cy.intercept('GET', '/api/v1/mcp/oauth/callback*', {
        statusCode: 200,
        body: {
          success: true,
          mcp_server_id: 'server-123',
          mcp_server_name: 'GitHub MCP Server',
          oauth_connected: true,
          message: 'OAuth connected successfully',
        },
      }).as('oauthCallback');
    });

    it('should display success message after successful authentication', () => {
      cy.visit('/oauth/mcp/callback?code=valid-code&state=valid-state');
      cy.wait('@oauthCallback');
      cy.contains('Authentication Successful').should('be.visible');
    });

    it('should display connected server name', () => {
      cy.visit('/oauth/mcp/callback?code=valid-code&state=valid-state');
      cy.wait('@oauthCallback');
      cy.contains('GitHub MCP Server').should('be.visible');
    });

    it('should display auto-close message', () => {
      cy.visit('/oauth/mcp/callback?code=valid-code&state=valid-state');
      cy.wait('@oauthCallback');
      cy.contains('This window will close automatically').should('be.visible');
    });

    it('should have manual close link', () => {
      cy.visit('/oauth/mcp/callback?code=valid-code&state=valid-state');
      cy.wait('@oauthCallback');
      cy.contains('Close now').should('be.visible');
    });
  });

  describe('Error State - Missing Parameters', () => {
    it('should display error when code is missing', () => {
      cy.visit('/oauth/mcp/callback?state=test-state');
      cy.contains('Authentication Failed').should('be.visible');
      cy.contains('Missing required OAuth parameters').should('be.visible');
    });

    it('should display error when state is missing', () => {
      cy.visit('/oauth/mcp/callback?code=test-code');
      cy.contains('Authentication Failed').should('be.visible');
      cy.contains('Missing required OAuth parameters').should('be.visible');
    });

    it('should display error when both parameters are missing', () => {
      cy.visit('/oauth/mcp/callback');
      cy.contains('Authentication Failed').should('be.visible');
      cy.contains('Missing required OAuth parameters').should('be.visible');
    });
  });

  describe('Error State - OAuth Provider Error', () => {
    it('should display error from OAuth provider', () => {
      cy.visit('/oauth/mcp/callback?error=access_denied&error_description=User%20denied%20access');
      cy.contains('Authentication Failed').should('be.visible');
      cy.contains('User denied access').should('be.visible');
    });

    it('should display error code if no description provided', () => {
      cy.visit('/oauth/mcp/callback?error=server_error');
      cy.contains('Authentication Failed').should('be.visible');
      cy.contains('server_error').should('be.visible');
    });

    it('should have Close Window button on error', () => {
      cy.visit('/oauth/mcp/callback?error=access_denied');
      cy.contains('Close Window').should('be.visible');
    });
  });

  describe('Error State - API Failure', () => {
    it('should display error when API call fails', () => {
      cy.intercept('GET', '/api/v1/mcp/oauth/callback*', {
        statusCode: 500,
        body: {
          success: false,
          error: 'Internal server error',
        },
      }).as('oauthCallbackError');

      cy.visit('/oauth/mcp/callback?code=test-code&state=test-state');
      cy.wait('@oauthCallbackError');
      cy.contains('Authentication Failed').should('be.visible');
    });

    it('should display API error message', () => {
      cy.intercept('GET', '/api/v1/mcp/oauth/callback*', {
        statusCode: 401,
        body: {
          success: false,
          error: 'Invalid authorization code',
        },
      }).as('oauthCallbackError');

      cy.visit('/oauth/mcp/callback?code=invalid-code&state=test-state');
      cy.wait('@oauthCallbackError');
      cy.contains('Authentication Failed').should('be.visible');
    });
  });

  describe('Responsive Layout', () => {
    beforeEach(() => {
      cy.intercept('GET', '/api/v1/mcp/oauth/callback*', {
        statusCode: 200,
        body: { success: true, mcp_server_id: 'server-123', mcp_server_name: 'Test', oauth_connected: true, message: 'OK' },
      }).as('oauthCallback');
    });

    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/oauth/mcp/callback?code=test-code&state=test-state');
      cy.wait('@oauthCallback');
      cy.contains('Authentication Successful').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/oauth/mcp/callback?code=test-code&state=test-state');
      cy.wait('@oauthCallback');
      cy.contains('Authentication Successful').should('be.visible');
    });
  });
});

export {};
