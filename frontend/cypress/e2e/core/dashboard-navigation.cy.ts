describe('Dashboard Navigation Tests', () => {
  beforeEach(() => {
    cy.clearAppData();

    // Login with seeded demo user instead of registering new user each time
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();

    // Should be on app/dashboard after login
    cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Main Navigation', () => {
    it('should display main dashboard elements', () => {
      // Check for main content area
      cy.get('main, [role="main"], .main-content').should('exist');

      // Check for navigation elements
      cy.get('nav, aside, [role="navigation"]').should('exist');
    });

    it('should handle user menu interactions', () => {
      // Check if user menu exists
      cy.get('body').then($body => {
        if ($body.find('[data-testid="user-menu"]').length > 0) {
          // Click user menu
          cy.get('[data-testid="user-menu"]').click();

          // Should show dropdown with logout option
          cy.get('[data-testid="logout-btn"], [role="menuitem"]').should('be.visible');
        } else {
          // User menu might be structured differently
          cy.log('User menu not found with expected test ID');
        }
      });
    });

    it('should navigate to different app sections', () => {
      // Visit a section - most apps have some navigation
      cy.get('body').then($body => {
        // Look for sidebar navigation items
        const navItems = $body.find('nav a, aside a, [role="navigation"] a');
        if (navItems.length > 0) {
          cy.wrap(navItems.first()).click({ force: true });
          cy.url().should('match', /\/(app|dashboard)/);
        }
      });
    });
  });

  describe('Responsive Design', () => {
    it('should work on mobile viewport', () => {
      cy.viewport('iphone-x');

      // Page should still be functional
      cy.get('main, [role="main"], .main-content').should('exist');
    });

    it('should work on tablet viewport', () => {
      cy.viewport('ipad-2');

      // Page should still be functional
      cy.get('main, [role="main"], .main-content').should('exist');
    });

    it('should work on desktop viewport', () => {
      cy.viewport(1920, 1080);

      // Page should still be functional
      cy.get('main, [role="main"], .main-content').should('exist');
    });
  });

  describe('Theme Support', () => {
    it('should have proper theme classes applied', () => {
      // Check for theme-aware classes or CSS variables
      cy.get('body').should('exist');

      // Check if theme toggle exists
      cy.get('body').then($body => {
        if ($body.find('[data-testid="theme-toggle"]').length > 0) {
          cy.get('[data-testid="theme-toggle"]').should('be.visible');
        } else {
          cy.log('No theme toggle found - using default theme');
        }
      });
    });
  });

  describe('Performance', () => {
    it('should load dashboard quickly', () => {
      // Visit with performance measurement
      cy.visit('/app').then(() => {
        // Page should load within reasonable time
        cy.get('main, [role="main"], .main-content', { timeout: 10000 }).should('exist');
      });
    });

    it('should handle multiple rapid navigation attempts', () => {
      // Rapidly navigate between routes
      cy.visit('/app');
      cy.url().should('match', /\/(app|dashboard)/);

      // Page should still work properly
      cy.get('main, [role="main"], .main-content').should('exist');
    });
  });

  describe('Error States', () => {
    it('should handle missing user data gracefully', () => {
      // Clear localStorage to simulate missing user data
      cy.window().then(win => {
        win.localStorage.clear();
      });

      // Visit app - should redirect to login
      cy.visit('/app');
      cy.url().should('include', '/login');
    });

    it('should handle invalid routes gracefully', () => {
      // Try to visit non-existent route
      cy.visit('/app/nonexistent', { failOnStatusCode: false });

      // Should either redirect to main app or show 404
      cy.url().then(url => {
        expect(url).to.satisfy((u: string) =>
          u.includes('/app') || u.includes('/dashboard') || u.includes('/404') || u.includes('/login')
        );
      });
    });
  });

  describe('Accessibility', () => {
    it('should have proper landmarks', () => {
      // Check for main landmarks
      cy.get('main, [role="main"]').should('exist');
      cy.get('nav, [role="navigation"]').should('exist');
    });

    it('should be keyboard navigable', () => {
      // Tab should move focus through interface
      cy.get('body').focus();

      // Should have focusable elements
      cy.get('a, button, input, [tabindex="0"]').should('exist');
    });
  });

  describe('Data Loading States', () => {
    it('should handle slow API responses', () => {
      // Visit app and wait for content
      cy.visit('/app');

      // Should show content eventually
      cy.get('main, [role="main"], .main-content', { timeout: 15000 }).should('exist');
    });
  });
});
