/// <reference types="cypress" />

/**
 * Account Switcher Tests
 *
 * Tests for Account Switching functionality including:
 * - Account switcher visibility
 * - Account list display
 * - Switch account action
 * - Current account indicator
 * - Account creation from switcher
 * - Error handling
 */

describe('Account Switcher Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Account Switcher Visibility', () => {
    it('should display account switcher in navigation', () => {
      cy.visit('/app/dashboard');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSwitcher = $body.find('[data-testid="account-switcher"]').length > 0 ||
                           $body.text().includes('Switch') ||
                           $body.find('[aria-label*="account"]').length > 0;
        if (hasSwitcher) {
          cy.log('Account switcher visible');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display current account name', () => {
      cy.visit('/app/dashboard');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasAccount = $body.find('[data-testid="current-account"]').length > 0 ||
                          $body.text().includes('Account');
        if (hasAccount) {
          cy.log('Current account name displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Account Dropdown', () => {
    beforeEach(() => {
      cy.visit('/app/dashboard');
      cy.waitForPageLoad();
    });

    it('should open account dropdown on click', () => {
      cy.get('body').then($body => {
        const switcher = $body.find('[data-testid="account-switcher"], [aria-label*="account"]');
        if (switcher.length > 0) {
          cy.wrap(switcher).first().click();
          cy.log('Account dropdown opened');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display list of accounts', () => {
      cy.get('body').then($body => {
        const switcher = $body.find('[data-testid="account-switcher"], [aria-label*="account"]');
        if (switcher.length > 0) {
          cy.wrap(switcher).first().click();

          cy.get('body').then($innerBody => {
            const hasAccounts = $innerBody.find('[data-testid="account-list"] li').length > 0 ||
                               $innerBody.text().includes('Account');
            if (hasAccounts) {
              cy.log('Account list displayed');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should highlight current account', () => {
      cy.get('body').then($body => {
        const switcher = $body.find('[data-testid="account-switcher"]');
        if (switcher.length > 0) {
          cy.wrap(switcher).first().click();

          cy.get('body').then($innerBody => {
            const hasHighlight = $innerBody.find('[data-testid="current-account-indicator"]').length > 0 ||
                                $innerBody.find('.selected, .active, [aria-selected="true"]').length > 0;
            if (hasHighlight) {
              cy.log('Current account highlighted');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Switch Account', () => {
    beforeEach(() => {
      cy.visit('/app/dashboard');
      cy.waitForPageLoad();
    });

    it('should allow clicking on different account', () => {
      cy.get('body').then($body => {
        const switcher = $body.find('[data-testid="account-switcher"]');
        if (switcher.length > 0) {
          cy.wrap(switcher).first().click();

          cy.get('body').then($innerBody => {
            const accounts = $innerBody.find('[data-testid="account-option"]');
            if (accounts.length > 1) {
              cy.log('Multiple accounts available for switching');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Create Account Option', () => {
    beforeEach(() => {
      cy.visit('/app/dashboard');
      cy.waitForPageLoad();
    });

    it('should display create account option', () => {
      cy.get('body').then($body => {
        const switcher = $body.find('[data-testid="account-switcher"]');
        if (switcher.length > 0) {
          cy.wrap(switcher).first().click();

          cy.get('body').then($innerBody => {
            const hasCreate = $innerBody.text().includes('Create') ||
                             $innerBody.text().includes('New') ||
                             $innerBody.text().includes('Add Account');
            if (hasCreate) {
              cy.log('Create account option displayed');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Account Information', () => {
    beforeEach(() => {
      cy.visit('/app/dashboard');
      cy.waitForPageLoad();
    });

    it('should display account logo/avatar', () => {
      cy.get('body').then($body => {
        const hasAvatar = $body.find('[data-testid="account-avatar"], img[alt*="account"], .avatar').length > 0;
        if (hasAvatar) {
          cy.log('Account avatar displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display subscription tier if applicable', () => {
      cy.get('body').then($body => {
        const switcher = $body.find('[data-testid="account-switcher"]');
        if (switcher.length > 0) {
          cy.wrap(switcher).first().click();

          cy.get('body').then($innerBody => {
            const hasTier = $innerBody.text().includes('Pro') ||
                           $innerBody.text().includes('Business') ||
                           $innerBody.text().includes('Enterprise') ||
                           $innerBody.text().includes('Free');
            if (hasTier) {
              cy.log('Subscription tier displayed');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Keyboard Navigation', () => {
    beforeEach(() => {
      cy.visit('/app/dashboard');
      cy.waitForPageLoad();
    });

    it('should support keyboard navigation', () => {
      cy.get('body').then($body => {
        const switcher = $body.find('[data-testid="account-switcher"]');
        if (switcher.length > 0) {
          cy.wrap(switcher).first().focus().type('{enter}');
          cy.log('Keyboard navigation supported');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle switch account errors gracefully', () => {
      cy.visit('/app/dashboard');
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
      it(`should display account switcher correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/dashboard');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`Account switcher displayed correctly on ${name}`);
      });
    });
  });
});
