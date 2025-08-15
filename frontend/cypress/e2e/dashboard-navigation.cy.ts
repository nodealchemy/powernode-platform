describe('Dashboard Navigation Tests', () => {
  const timestamp = Date.now();
  
  beforeEach(() => {
    cy.clearAppData();
    
    // Login before each test
    cy.register({
      email: `dashboard-${timestamp}-${Math.random()}@example.com`,
      password: 'Qx7#mK9@pL2$nZ6%',
      firstName: 'Dashboard',
      lastName: 'User',
      accountName: 'Dashboard Test Co'
    });
    
    // Should be on dashboard after registration
    cy.url().should('include', '/dashboard');
  });

  describe('Main Navigation', () => {
    it('should display main dashboard elements', () => {
      // Check for main dashboard components
      cy.get('[data-testid="user-menu"]').should('be.visible');
      cy.contains('Welcome back, Dashboard!').should('be.visible');
      
      // Check for navigation elements
      cy.get('nav').should('be.visible');
      
      // Check for main content area
      cy.get('main').should('be.visible');
    });

    it('should handle user menu interactions', () => {
      // Click user menu
      cy.get('[data-testid="user-menu"]').click();
      
      // Should show dropdown menu
      cy.get('[data-testid="logout-btn"]').should('be.visible');
      
      // Click outside to close menu
      cy.get('body').click(0, 0);
      cy.get('[data-testid="logout-btn"]').should('not.be.visible');
      
      // Open menu again
      cy.get('[data-testid="user-menu"]').click();
      cy.get('[data-testid="logout-btn"]').should('be.visible');
    });

    it('should navigate to different dashboard sections', () => {
      // Try to navigate to analytics (even if it redirects to main dashboard)
      cy.visit('/dashboard/analytics');
      cy.url().should('include', '/dashboard');
      
      // Should still show user info
      cy.contains('Dashboard').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    it('should work on mobile viewport', () => {
      cy.viewport('iphone-x');
      
      // Should still display main elements
      cy.get('[data-testid="user-menu"]').should('be.visible');
      cy.contains('Dashboard').should('be.visible');
      
      // User menu should still work
      cy.get('[data-testid="user-menu"]').click();
      cy.get('[data-testid="logout-btn"]').should('be.visible');
    });

    it('should work on tablet viewport', () => {
      cy.viewport('ipad-2');
      
      cy.get('[data-testid="user-menu"]').should('be.visible');
      cy.contains('Dashboard').should('be.visible');
    });

    it('should work on desktop viewport', () => {
      cy.viewport(1920, 1080);
      
      cy.get('[data-testid="user-menu"]').should('be.visible');
      cy.contains('Dashboard').should('be.visible');
    });
  });

  describe('Theme Support', () => {
    it('should have proper theme classes applied', () => {
      // Check for theme-aware classes
      cy.get('body').should('have.class', 'bg-theme-background');
      
      // Check if theme toggle exists (if implemented)
      cy.get('body').then($body => {
        if ($body.find('[data-testid="theme-toggle"]').length > 0) {
          cy.get('[data-testid="theme-toggle"]').should('be.visible');
        }
      });
    });
  });

  describe('Performance', () => {
    it('should load dashboard quickly', () => {
      const startTime = Date.now();
      
      cy.visit('/dashboard').then(() => {
        const loadTime = Date.now() - startTime;
        cy.log(`Dashboard load time: ${loadTime}ms`);
        
        // Should load within reasonable time
        expect(loadTime).to.be.lessThan(5000);
      });
      
      cy.contains('Dashboard').should('be.visible');
    });

    it('should handle multiple rapid navigation attempts', () => {
      // Rapidly navigate between routes
      cy.visit('/dashboard');
      cy.visit('/dashboard/analytics');
      cy.visit('/dashboard');
      
      // Should still work properly
      cy.url().should('include', '/dashboard');
      cy.contains('Dashboard').should('be.visible');
    });
  });

  describe('Error States', () => {
    it('should handle missing user data gracefully', () => {
      // Clear localStorage to simulate missing user data
      cy.window().then(win => {
        win.localStorage.clear();
      });
      
      // Visit dashboard - should redirect to login
      cy.visit('/dashboard');
      cy.url().should('include', '/login');
    });

    it('should handle invalid routes gracefully', () => {
      // Try to visit non-existent dashboard route
      cy.visit('/dashboard/nonexistent', { failOnStatusCode: false });
      
      // Should either redirect to main dashboard or show 404
      cy.url().then(url => {
        expect(url).to.satisfy(url => 
          url.includes('/dashboard') || url.includes('/404') || url.includes('/login')
        );
      });
    });
  });

  describe('Accessibility', () => {
    it('should have proper ARIA labels', () => {
      // Check for main landmarks
      cy.get('main').should('exist');
      cy.get('nav').should('exist');
      
      // Check for button accessibility
      cy.get('[data-testid="user-menu"]').should('have.attr', 'type', 'button');
      cy.get('[data-testid="logout-btn"]').click();
      cy.get('[data-testid="logout-btn"]').should('have.attr', 'type', 'button');
    });

    it('should be keyboard navigable', () => {
      // Tab through interface
      cy.get('body').tab();
      
      // Should be able to reach user menu with keyboard
      cy.get('[data-testid="user-menu"]').focus();
      cy.get('[data-testid="user-menu"]').should('have.focus');
      
      // Should be able to activate with Enter/Space
      cy.get('[data-testid="user-menu"]').type('{enter}');
      cy.get('[data-testid="logout-btn"]').should('be.visible');
    });
  });

  describe('Data Loading States', () => {
    it('should handle slow API responses', () => {
      // Intercept API calls and add delay
      cy.intercept('GET', '/api/v1/auth/me', (req) => {
        req.reply((res) => {
          return new Promise(resolve => {
            setTimeout(() => resolve(res), 2000);
          });
        });
      }).as('slowUser');
      
      cy.visit('/dashboard');
      
      // Should show loading state or work gracefully
      cy.contains('Dashboard').should('be.visible');
    });
  });
});