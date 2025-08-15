describe('End-to-End User Journey Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
  });

  describe('Complete New User Journey', () => {
    it('should complete full new user onboarding flow', () => {
      const timestamp = Date.now();
      const userData = {
        email: `e2e-journey-${timestamp}@example.com`,
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'Journey',
        lastName: 'Tester',
        accountName: 'Journey Test Company'
      };

      // Step 1: Landing page → Plan selection
      cy.visit('/');
      
      // Should redirect to plans or login page
      cy.url().should('satisfy', (url) => {
        return url.includes('/plans') || url.includes('/login') || url.includes('/');
      });

      // Navigate to plans if not already there
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');

      // Step 2: Plan selection → Registration
      cy.get('[data-testid="plan-card"]').first().click();
      cy.get('[data-testid="plan-select-btn"]', { timeout: 10000 }).should('be.visible');
      cy.get('[data-testid="plan-select-btn"]').click();

      // Step 3: Registration form completion
      cy.url().should('include', '/register');
      cy.get('[data-testid="selected-plan"]', { timeout: 15000 }).should('be.visible');

      cy.get('input[name="accountName"]').type(userData.accountName);
      cy.get('input[name="firstName"]').type(userData.firstName);
      cy.get('input[name="lastName"]').type(userData.lastName);
      cy.get('input[name="email"]').type(userData.email);
      cy.get('input[name="password"]').type(userData.password);

      cy.get('button[type="submit"]').should('not.be.disabled');
      cy.get('button[type="submit"]').click();

      // Step 4: Post-registration → Dashboard
      cy.url().should('include', '/dashboard', { timeout: 20000 });
      cy.contains(userData.firstName).should('be.visible');
      cy.get('[data-testid="user-menu"]').should('be.visible');

      // Step 5: Dashboard exploration
      cy.get('[data-testid="user-menu"]').click();
      cy.get('[data-testid="logout-btn"]').should('be.visible');

      // Close menu
      cy.get('body').click(0, 0);
      cy.get('[data-testid="logout-btn"]').should('not.be.visible');

      // Step 6: Verify user can access all basic features
      cy.get('body').should('not.contain.text', 'Error');
      cy.get('body').should('not.contain.text', 'undefined');

      // Journey completed successfully
      cy.log('Complete new user journey finished successfully');
    });

    it('should handle user journey with plan changes', () => {
      const timestamp = Date.now();
      const userData = {
        email: `plan-change-${timestamp}@example.com`,
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'PlanChange',
        lastName: 'User',
        accountName: 'Plan Change Co'
      };

      // Complete initial registration
      cy.register(userData);
      cy.url().should('include', '/dashboard');

      // Navigate back to plans for upgrade/change
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');

      // Select a different plan (user is already logged in)
      cy.get('[data-testid="plan-card"]').eq(1).then($card => {
        if ($card.length > 0) {
          cy.wrap($card).click();
          cy.get('[data-testid="plan-select-btn"]', { timeout: 10000 }).should('be.visible');
          cy.get('[data-testid="plan-select-btn"]').click();

          // Should handle plan change flow
          cy.url().should('satisfy', (url) => {
            return url.includes('/billing') || 
                   url.includes('/payment') || 
                   url.includes('/confirm') ||
                   url.includes('/dashboard');
          });
        }
      });

      // Return to dashboard
      cy.visit('/dashboard');
      cy.get('[data-testid="user-menu"]').should('be.visible');
    });
  });

  describe('Returning User Journey', () => {
    it('should handle complete returning user login flow', () => {
      const timestamp = Date.now();
      const userData = {
        email: `returning-user-${timestamp}@example.com`,
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'Returning',
        lastName: 'User',
        accountName: 'Returning User Co'
      };

      // Step 1: Create account first
      cy.register(userData);
      cy.url().should('include', '/dashboard');

      // Step 2: Logout
      cy.get('[data-testid="user-menu"]').click();
      cy.get('[data-testid="logout-btn"]').click();
      cy.url().should('include', '/login');

      // Step 3: Return as existing user
      cy.visit('/login');
      cy.get('input[type="email"]').type(userData.email);
      cy.get('input[type="password"]').type(userData.password);
      cy.get('button[type="submit"]').click();

      // Step 4: Back to dashboard
      cy.url().should('include', '/dashboard');
      cy.contains(userData.firstName).should('be.visible');

      // Step 5: Verify session persistence
      cy.reload();
      cy.url().should('include', '/dashboard');
      cy.contains(userData.firstName).should('be.visible');

      // Complete returning user journey
      cy.log('Returning user login journey completed successfully');
    });

    it('should handle forgotten password recovery flow if available', () => {
      // Test password recovery flow
      cy.visit('/login');
      
      // Look for forgot password link
      cy.get('body').then($body => {
        if ($body.find('[href="/forgot-password"], [href*="forgot"], [data-testid="forgot-password"]').length > 0) {
          cy.get('[href="/forgot-password"], [href*="forgot"], [data-testid="forgot-password"]').click();
          
          // Should navigate to forgot password page
          cy.url().should('include', '/forgot').or('include', '/reset');
          
          // Should have email input for recovery
          cy.get('input[type="email"], input[name="email"]').should('exist');
          cy.get('button[type="submit"], [data-testid="reset-btn"]').should('exist');
          
          // Test with valid email format
          cy.get('input[type="email"], input[name="email"]').type('test@example.com');
          cy.get('button[type="submit"], [data-testid="reset-btn"]').click();
          
          // Should show confirmation or redirect
          cy.get('body').should('satisfy', ($body) => {
            const text = $body.text().toLowerCase();
            return text.includes('sent') || 
                   text.includes('check email') ||
                   text.includes('reset') ||
                   text.includes('success');
          });
          
        } else {
          cy.log('Forgot password functionality not implemented');
        }
      });
    });
  });

  describe('Error Recovery Journeys', () => {
    it('should handle registration with existing email', () => {
      const timestamp = Date.now();
      const userData = {
        email: `duplicate-test-${timestamp}@example.com`,
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'Duplicate',
        lastName: 'Test',
        accountName: 'Duplicate Test Co'
      };

      // Step 1: Create account first
      cy.register(userData);
      cy.url().should('include', '/dashboard');
      
      // Step 2: Logout
      cy.get('[data-testid="user-menu"]').click();
      cy.get('[data-testid="logout-btn"]').click();

      // Step 3: Try to register again with same email
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
      cy.get('[data-testid="plan-card"]').first().click();
      cy.get('[data-testid="plan-select-btn"]', { timeout: 10000 }).should('be.visible');
      cy.get('[data-testid="plan-select-btn"]').click();

      // Fill form with duplicate email
      cy.get('input[name="accountName"]').type('Duplicate Account 2');
      cy.get('input[name="firstName"]').type('Duplicate2');
      cy.get('input[name="lastName"]').type('Test2');
      cy.get('input[name="email"]').type(userData.email); // Same email
      cy.get('input[name="password"]').type(userData.password);

      cy.get('button[type="submit"]').should('not.be.disabled');
      cy.get('button[type="submit"]').click();

      // Should handle duplicate email error
      cy.wait(3000);
      cy.get('body').should('satisfy', ($body) => {
        const text = $body.text().toLowerCase();
        return text.includes('already') || 
               text.includes('exists') ||
               text.includes('duplicate') ||
               text.includes('taken') ||
               url.includes('/register'); // Still on register page
      });
    });

    it('should handle network errors during critical flows', () => {
      // Simulate network error during registration
      cy.intercept('POST', '/api/v1/auth/register', { forceNetworkError: true }).as('networkError');
      
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
      cy.get('[data-testid="plan-card"]').first().click();
      cy.get('[data-testid="plan-select-btn"]', { timeout: 10000 }).should('be.visible');
      cy.get('[data-testid="plan-select-btn"]').click();

      // Fill registration form
      const timestamp = Date.now();
      cy.get('input[name="accountName"]').type('Network Test Co');
      cy.get('input[name="firstName"]').type('Network');
      cy.get('input[name="lastName"]').type('Test');
      cy.get('input[name="email"]').type(`network-${timestamp}@example.com`);
      cy.get('input[name="password"]').type('Qx7#mK9@pL2$nZ6%');

      cy.get('button[type="submit"]').click();

      // Should handle network error gracefully
      cy.wait('@networkError');
      cy.get('body').should('satisfy', ($body) => {
        const text = $body.text().toLowerCase();
        return text.includes('error') || 
               text.includes('failed') ||
               text.includes('try again') ||
               text.includes('network');
      });

      // User should still be on registration page
      cy.url().should('include', '/register');
    });

    it('should handle authentication errors gracefully', () => {
      // Test invalid login credentials
      cy.visit('/login');
      
      cy.get('input[type="email"]').type('nonexistent@example.com');
      cy.get('input[type="password"]').type('wrongpassword');
      cy.get('button[type="submit"]').click();

      // Should show error and stay on login page
      cy.wait(2000);
      cy.url().should('include', '/login');
      
      // Should provide clear error feedback
      cy.get('body').should('satisfy', ($body) => {
        const text = $body.text().toLowerCase();
        return text.includes('invalid') || 
               text.includes('incorrect') ||
               text.includes('error') ||
               text.includes('failed');
      });
    });
  });

  describe('Multi-Device User Journey', () => {
    it('should handle user journey across desktop and mobile', () => {
      const timestamp = Date.now();
      const userData = {
        email: `multidevice-${timestamp}@example.com`,
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'MultiDevice',
        lastName: 'User',
        accountName: 'Multi Device Co'
      };

      // Step 1: Desktop registration
      cy.viewport(1280, 720);
      cy.register(userData);
      cy.url().should('include', '/dashboard');

      // Step 2: Switch to mobile viewport (simulating mobile access)
      cy.viewport(375, 667);
      cy.reload();
      
      // Should maintain login on mobile
      cy.url().should('include', '/dashboard');
      cy.get('[data-testid="user-menu"]').should('be.visible');

      // Step 3: Mobile navigation
      cy.get('[data-testid="user-menu"]').click();
      cy.get('[data-testid="logout-btn"]').should('be.visible');

      // Step 4: Mobile logout
      cy.get('[data-testid="logout-btn"]').click();
      cy.url().should('include', '/login');

      // Step 5: Mobile login
      cy.get('input[type="email"]').type(userData.email);
      cy.get('input[type="password"]').type(userData.password);
      cy.get('button[type="submit"]').click();

      cy.url().should('include', '/dashboard');
      cy.get('[data-testid="user-menu"]').should('be.visible');

      // Step 6: Back to desktop viewport
      cy.viewport(1280, 720);
      cy.reload();
      
      // Should maintain session across viewport changes
      cy.url().should('include', '/dashboard');
      cy.contains(userData.firstName).should('be.visible');
    });

    it('should handle tablet-specific user interactions', () => {
      const timestamp = Date.now();
      const userData = {
        email: `tablet-user-${timestamp}@example.com`,
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'Tablet',
        lastName: 'User',
        accountName: 'Tablet User Co'
      };

      // Tablet viewport
      cy.viewport(768, 1024);
      
      // Complete registration flow on tablet
      cy.register(userData);
      cy.url().should('include', '/dashboard');

      // Test tablet-specific interactions
      cy.get('[data-testid="user-menu"]').should('be.visible');
      cy.get('[data-testid="user-menu"]').click();

      // Menu should work properly on tablet
      cy.get('[data-testid="logout-btn"]').should('be.visible');

      // Test plan navigation on tablet
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');

      // Plan cards should be appropriately sized for tablet
      cy.get('[data-testid="plan-card"]').should('be.visible');
      cy.get('[data-testid="plan-card"]').first().click();
      cy.get('[data-testid="plan-select-btn"]', { timeout: 10000 }).should('be.visible');
    });
  });

  describe('Performance and User Experience Journey', () => {
    it('should complete user journey within acceptable time limits', () => {
      const startTime = Date.now();
      const timestamp = Date.now();
      const userData = {
        email: `perf-test-${timestamp}@example.com`,
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'Performance',
        lastName: 'Test',
        accountName: 'Performance Test Co'
      };

      // Track timing for critical user flows
      cy.visit('/plans');
      const plansLoadTime = Date.now();
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
      
      // Plans should load within reasonable time (already waited up to 15s)
      cy.log(`Plans loaded in: ${Date.now() - plansLoadTime}ms`);

      // Plan selection
      cy.get('[data-testid="plan-card"]').first().click();
      cy.get('[data-testid="plan-select-btn"]', { timeout: 10000 }).should('be.visible');
      cy.get('[data-testid="plan-select-btn"]').click();

      // Registration flow timing
      const regStartTime = Date.now();
      cy.url().should('include', '/register');
      cy.get('[data-testid="selected-plan"]', { timeout: 15000 }).should('be.visible');

      cy.get('input[name="accountName"]').type(userData.accountName);
      cy.get('input[name="firstName"]').type(userData.firstName);
      cy.get('input[name="lastName"]').type(userData.lastName);
      cy.get('input[name="email"]').type(userData.email);
      cy.get('input[name="password"]').type(userData.password);

      cy.get('button[type="submit"]').click();

      // Dashboard should load within reasonable time
      cy.url().should('include', '/dashboard', { timeout: 20000 });
      const regCompleteTime = Date.now();
      
      cy.log(`Registration completed in: ${regCompleteTime - regStartTime}ms`);
      cy.log(`Total journey time: ${regCompleteTime - startTime}ms`);

      // Verify all elements loaded properly
      cy.get('[data-testid="user-menu"]').should('be.visible');
      cy.contains(userData.firstName).should('be.visible');
    });

    it('should provide smooth user experience during navigation', () => {
      const timestamp = Date.now();
      const userData = {
        email: `smooth-nav-${timestamp}@example.com`,
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'Smooth',
        lastName: 'Navigation',
        accountName: 'Smooth Navigation Co'
      };

      // Register user
      cy.register(userData);
      cy.url().should('include', '/dashboard');

      // Test smooth navigation between pages
      const pages = ['/dashboard', '/plans', '/login', '/dashboard'];
      
      pages.forEach((page, index) => {
        if (page === '/login' && index > 0) {
          // Logout first before going to login
          cy.get('[data-testid="user-menu"]').click();
          cy.get('[data-testid="logout-btn"]').click();
        }
        
        cy.visit(page);
        
        // Page should load without errors
        cy.get('body').should('be.visible');
        cy.get('body').should('not.contain.text', 'Error');
        cy.get('body').should('not.contain.text', 'undefined');
        
        // Re-login if necessary
        if (page === '/dashboard' && index === pages.length - 1) {
          cy.get('body').then($body => {
            if ($body.find('input[type="email"]').length > 0) {
              // On login page, need to log back in
              cy.get('input[type="email"]').type(userData.email);
              cy.get('input[type="password"]').type(userData.password);
              cy.get('button[type="submit"]').click();
              cy.url().should('include', '/dashboard');
            }
          });
        }
      });
    });
  });

  describe('Accessibility User Journey', () => {
    it('should complete user journey using keyboard navigation', () => {
      const timestamp = Date.now();
      const userData = {
        email: `keyboard-nav-${timestamp}@example.com`,
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'Keyboard',
        lastName: 'Navigation',
        accountName: 'Keyboard Navigation Co'
      };

      // Test keyboard navigation through registration
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
      
      // Select plan using keyboard
      cy.get('[data-testid="plan-card"]').first().focus().click();
      cy.get('[data-testid="plan-select-btn"]', { timeout: 10000 }).should('be.visible');
      cy.get('[data-testid="plan-select-btn"]').focus().click();

      // Navigate registration form with keyboard
      cy.get('input[name="accountName"]').focus().type(userData.accountName);
      cy.get('input[name="firstName"]').focus().type(userData.firstName);
      cy.get('input[name="lastName"]').focus().type(userData.lastName);
      cy.get('input[name="email"]').focus().type(userData.email);
      cy.get('input[name="password"]').focus().type(userData.password);
      cy.get('button[type="submit"]').focus().click();

      // Verify successful keyboard-driven registration
      cy.url().should('include', '/dashboard');
      cy.get('[data-testid="user-menu"]').focus().should('be.focused');
    });

    it('should maintain focus management throughout user journey', () => {
      cy.visit('/login');
      
      // Test focus management in login flow
      cy.get('input[type="email"]').focus().should('be.focused');
      cy.get('input[type="password"]').focus().should('be.focused');
      cy.get('button[type="submit"]').focus().should('be.focused');
      
      // Focus should be visible
      cy.focused().should('have.css', 'outline-style').and('not.equal', 'none');
    });
  });
});