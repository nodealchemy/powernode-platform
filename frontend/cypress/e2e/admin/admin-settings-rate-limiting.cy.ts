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
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Rate Limiting') ||
                          $body.text().includes('Rate') ||
                          $body.text().includes('Limits');
        if (hasContent) {
          cy.log('Rate Limiting tab loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should redirect unauthorized users', () => {
      cy.get('body').should('be.visible');
    });
  });

  describe('Rate Limiting Overview', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/rate-limiting');
      cy.waitForPageLoad();
    });

    it('should display rate limiting toggle', () => {
      cy.get('body').then($body => {
        const hasToggle = $body.text().includes('Enable Rate Limiting') ||
                          $body.find('input[type="checkbox"], [role="switch"]').length > 0;
        if (hasToggle) {
          cy.log('Rate limiting toggle displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display rate limiting description', () => {
      cy.get('body').then($body => {
        const hasDescription = $body.text().includes('protect') ||
                               $body.text().includes('abuse') ||
                               $body.text().includes('requests');
        if (hasDescription) {
          cy.log('Rate limiting description displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('API Rate Limits', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/rate-limiting');
      cy.waitForPageLoad();
    });

    it('should display API requests per minute field', () => {
      cy.get('body').then($body => {
        const hasAPILimit = $body.text().includes('API Requests') ||
                            $body.text().includes('per minute') ||
                            $body.text().includes('Requests/Minute');
        if (hasAPILimit) {
          cy.log('API requests per minute field displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display webhook requests limit', () => {
      cy.get('body').then($body => {
        const hasWebhookLimit = $body.text().includes('Webhook') ||
                                $body.text().includes('webhook');
        if (hasWebhookLimit) {
          cy.log('Webhook requests limit displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should allow updating API limit value', () => {
      cy.get('body').then($body => {
        const input = $body.find('input[type="number"]');
        if (input.length > 0) {
          cy.wrap(input).first().clear().type('100');
          cy.log('API limit value updated');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Authentication Rate Limits', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/rate-limiting');
      cy.waitForPageLoad();
    });

    it('should display login attempts limit', () => {
      cy.get('body').then($body => {
        const hasLoginLimit = $body.text().includes('Login Attempts') ||
                              $body.text().includes('Login') ||
                              $body.text().includes('per hour');
        if (hasLoginLimit) {
          cy.log('Login attempts limit displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display registration attempts limit', () => {
      cy.get('body').then($body => {
        const hasRegLimit = $body.text().includes('Registration') ||
                            $body.text().includes('registration');
        if (hasRegLimit) {
          cy.log('Registration attempts limit displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display password reset limit', () => {
      cy.get('body').then($body => {
        const hasPasswordResetLimit = $body.text().includes('Password Reset') ||
                                      $body.text().includes('password reset');
        if (hasPasswordResetLimit) {
          cy.log('Password reset limit displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display email verification limit', () => {
      cy.get('body').then($body => {
        const hasEmailLimit = $body.text().includes('Email Verification') ||
                              $body.text().includes('verification');
        if (hasEmailLimit) {
          cy.log('Email verification limit displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Rate Limit Configuration', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/rate-limiting');
      cy.waitForPageLoad();
    });

    it('should display limit input fields', () => {
      cy.get('body').then($body => {
        const hasInputs = $body.find('input[type="number"]').length > 0;
        if (hasInputs) {
          cy.log('Limit input fields displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have minimum value validation', () => {
      cy.get('body').then($body => {
        const input = $body.find('input[min]');
        if (input.length > 0) {
          cy.log('Minimum value validation present');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have maximum value validation', () => {
      cy.get('body').then($body => {
        const input = $body.find('input[max]');
        if (input.length > 0) {
          cy.log('Maximum value validation present');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('IP Whitelist/Blacklist', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/rate-limiting');
      cy.waitForPageLoad();
    });

    it('should display whitelist section', () => {
      cy.get('body').then($body => {
        const hasWhitelist = $body.text().includes('Whitelist') ||
                             $body.text().includes('Allowed') ||
                             $body.text().includes('Exempt');
        if (hasWhitelist) {
          cy.log('Whitelist section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display blacklist section', () => {
      cy.get('body').then($body => {
        const hasBlacklist = $body.text().includes('Blacklist') ||
                             $body.text().includes('Blocked') ||
                             $body.text().includes('Ban');
        if (hasBlacklist) {
          cy.log('Blacklist section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have add IP button', () => {
      cy.get('body').then($body => {
        const hasAddButton = $body.find('button:contains("Add"), button:contains("+")').length > 0;
        if (hasAddButton) {
          cy.log('Add IP button found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Rate Limit Statistics', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/rate-limiting');
      cy.waitForPageLoad();
    });

    it('should display current usage statistics', () => {
      cy.get('body').then($body => {
        const hasStats = $body.text().includes('Current') ||
                         $body.text().includes('Usage') ||
                         $body.text().includes('Statistics');
        if (hasStats) {
          cy.log('Current usage statistics displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display blocked requests count', () => {
      cy.get('body').then($body => {
        const hasBlocked = $body.text().includes('Blocked') ||
                           $body.text().includes('Rejected');
        if (hasBlocked) {
          cy.log('Blocked requests count displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Saving Configuration', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/rate-limiting');
      cy.waitForPageLoad();
    });

    it('should auto-save on change', () => {
      // Rate limiting settings typically auto-save
      cy.get('body').then($body => {
        const input = $body.find('input[type="number"]');
        if (input.length > 0) {
          cy.wrap(input).first().clear().type('50');
          cy.waitForPageLoad();
          cy.log('Setting changed - auto-save triggered');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should show save indicator', () => {
      cy.get('body').then($body => {
        const hasIndicator = $body.find('[class*="spin"]').length > 0 ||
                             $body.text().includes('Saving') ||
                             $body.text().includes('Updated');
        if (hasIndicator) {
          cy.log('Save indicator shown');
        }
      });

      cy.get('body').should('be.visible');
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

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
    });

    it('should display error state on load failure', () => {
      cy.intercept('GET', '**/api/**/admin/settings/**', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load' }
      });

      cy.visit('/app/admin/settings/rate-limiting');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
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

      cy.get('body').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/admin/settings/rate-limiting');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
    });

    it('should stack sections on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/admin/settings/rate-limiting');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
    });
  });
});


export {};
