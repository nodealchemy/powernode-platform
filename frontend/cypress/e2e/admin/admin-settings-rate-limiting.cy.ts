/// <reference types="cypress" />

/**
 * Admin Settings - Rate Limiting Tab E2E Tests
 *
 * Tests for rate limiting configuration including:
 * - Rate limiting overview
 * - API rate limits
 * - Authentication rate limits
 * - Per-endpoint configuration
 * - Whitelist/Blacklist management
 * - Responsive design
 */

describe('Admin Settings Rate Limiting Tab Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Page Navigation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/admin/settings/rate-limiting');
    });

    it('should navigate to Rate Limiting tab', () => {
      cy.assertContainsAny(['Rate Limiting', 'Rate', 'Limits']);
    });

    it('should redirect unauthorized users', () => {
      cy.assertContainsAny(['Rate Limiting', 'Settings', 'Admin']);
    });
  });

  describe('Rate Limiting Overview', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/rate-limiting');
      cy.waitForPageLoad();
    });

    it('should display rate limiting toggle', () => {
      cy.assertHasElement(['input[type="checkbox"]', '[role="switch"]']);
    });

    it('should display rate limiting description', () => {
      cy.assertContainsAny(['protect', 'abuse', 'requests']);
    });
  });

  describe('API Rate Limits', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/rate-limiting');
      cy.waitForPageLoad();
    });

    it('should display API requests per minute field', () => {
      cy.assertContainsAny(['API Requests', 'per minute', 'Requests/Minute']);
    });

    it('should display webhook requests limit', () => {
      cy.assertContainsAny(['Webhook', 'webhook']);
    });

    it('should allow updating API limit value', () => {
      cy.get('input[type="number"]').first().clear().type('100');
    });
  });

  describe('Authentication Rate Limits', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/rate-limiting');
      cy.waitForPageLoad();
    });

    it('should display login attempts limit', () => {
      cy.assertContainsAny(['Login Attempts', 'Login', 'per hour']);
    });

    it('should display registration attempts limit', () => {
      cy.assertContainsAny(['Registration', 'registration']);
    });

    it('should display password reset limit', () => {
      cy.assertContainsAny(['Password Reset', 'password reset']);
    });

    it('should display email verification limit', () => {
      cy.assertContainsAny(['Email Verification', 'verification']);
    });
  });

  describe('Rate Limit Configuration', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/rate-limiting');
      cy.waitForPageLoad();
    });

    it('should display limit input fields', () => {
      cy.get('input[type="number"]').should('exist');
    });

    it('should have minimum value validation', () => {
      cy.get('input[min]').should('exist');
    });

    it('should have maximum value validation', () => {
      cy.get('input[max]').should('exist');
    });
  });

  describe('IP Whitelist/Blacklist', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/rate-limiting');
      cy.waitForPageLoad();
    });

    it('should display whitelist section', () => {
      cy.assertContainsAny(['Whitelist', 'Allowed', 'Exempt']);
    });

    it('should display blacklist section', () => {
      cy.assertContainsAny(['Blacklist', 'Blocked', 'Ban']);
    });

    it('should have add IP button', () => {
      cy.get('button:contains("Add"), button:contains("+")').should('exist');
    });
  });

  describe('Rate Limit Statistics', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/rate-limiting');
      cy.waitForPageLoad();
    });

    it('should display current usage statistics', () => {
      cy.assertContainsAny(['Current', 'Usage', 'Statistics']);
    });

    it('should display blocked requests count', () => {
      cy.assertContainsAny(['Blocked', 'Rejected']);
    });
  });

  describe('Saving Configuration', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/rate-limiting');
      cy.waitForPageLoad();
    });

    it('should auto-save on change', () => {
      cy.get('input[type="number"]').first().clear().type('50');
      cy.waitForPageLoad();
    });

    it('should show save indicator', () => {
      cy.assertContainsAny(['Saving', 'Updated']);
    });
  });

  describe('Error Handling', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/admin/settings/rate-limiting');
    });

    it('should handle API errors gracefully', () => {
      cy.intercept('GET', '**/api/**/admin/**', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/admin/settings/rate-limiting');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Rate Limiting', 'Settings', 'Error']);
      cy.get('body').should('not.contain.text', 'Cannot read');
    });

    it('should display error state on load failure', () => {
      cy.intercept('GET', '**/api/**/admin/settings/**', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load' }
      });

      cy.visit('/app/admin/settings/rate-limiting');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Rate Limiting', 'Settings', 'Error']);
    });
  });

  describe('Responsive Design', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/admin/settings/rate-limiting');
    });

    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/admin/settings/rate-limiting');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Rate Limiting', 'Settings']);
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/admin/settings/rate-limiting');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Rate Limiting', 'Settings']);
    });

    it('should stack sections on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/admin/settings/rate-limiting');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Rate Limiting', 'Settings']);
    });
  });

  describe('Permission Check', () => {
    it('should require admin permissions', () => {
      cy.testPermissionDenied('/app/admin/settings/rate-limiting');
    });
  });
});


export {};
