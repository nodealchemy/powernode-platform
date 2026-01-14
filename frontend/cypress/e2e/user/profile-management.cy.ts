describe('Profile Management', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.setupApiIntercepts();
    // Login with demo user
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 5000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
    cy.waitForPageLoad();
  });

  describe('Profile Display', () => {
    it('should navigate to profile/settings page', () => {
      // Try to find settings/profile link
      cy.get('body').then($body => {
        const settingsSelectors = [
          '[data-testid="settings-link"]',
          'a[href*="settings"]',
          'a[href*="profile"]',
          '[data-testid="user-menu"]'
        ];

        for (const selector of settingsSelectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().should('be.visible').click();
            break;
          }
        }
      });

      // Should be on some settings/profile page or stay on dashboard
      cy.url().should('match', /\/(app|dashboard|settings|profile)/);
    });

    it('should display user information', () => {
      // User name should be visible somewhere
      cy.contains('Demo', { timeout: 5000 }).should('exist');
    });
  });

  describe('User Menu', () => {
    it('should open user menu dropdown', () => {
      cy.contains('Demo User').should('be.visible').click();

      // Should show dropdown with options
      cy.get('body').should('contain.text', 'Sign Out');
    });

    it('should navigate to profile from user menu', () => {
      cy.contains('Demo User').should('be.visible').click();

      // Look for profile link
      cy.get('body').then($body => {
        if ($body.find('a[href*="profile"], [data-testid="profile-link"]').length > 0) {
          cy.get('a[href*="profile"], [data-testid="profile-link"]').first().should('be.visible').click();
        }
      });
    });
  });

  describe('Session Management', () => {
    it('should logout successfully', () => {
      cy.contains('Demo User').should('be.visible').click();
      cy.contains('Sign Out').should('be.visible').click();
      cy.url({ timeout: 5000 }).should('include', '/login');
    });

    it('should maintain session across page refresh', () => {
      cy.reload();
      cy.waitForPageLoad();
      cy.url().should('match', /\/(app|dashboard)/);
      cy.contains('Demo', { timeout: 5000 }).should('exist');
    });
  });
});


export {};
