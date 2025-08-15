describe('Accessibility Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
  });

  describe('Public Pages Accessibility', () => {
    it('should have no accessibility violations on login page', () => {
      cy.visit('/login');
      
      // Wait for page to fully load
      cy.get('input[type="email"]').should('be.visible');
      cy.get('input[type="password"]').should('be.visible');
      
      // Inject axe and check for accessibility violations
      cy.injectAxe();
      cy.checkA11y();
    });

    it('should have no accessibility violations on plans page', () => {
      cy.visit('/plans');
      
      // Wait for plans to load
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
      
      // Check accessibility
      cy.checkA11y();
      
      // Test focus management
      cy.get('[data-testid="plan-card"]').first().focus().should('be.focused');
      
      // Check with plan selected
      cy.get('[data-testid="plan-card"]').first().click();
      cy.get('[data-testid="plan-select-btn"]', { timeout: 10000 }).should('be.visible');
      
      cy.checkA11y();
    });

    it('should have no accessibility violations on registration page', () => {
      // Navigate to registration through plan selection
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
      cy.get('[data-testid="plan-card"]').first().click();
      cy.get('[data-testid="plan-select-btn"]', { timeout: 10000 }).should('be.visible');
      cy.get('[data-testid="plan-select-btn"]').click();
      
      // Wait for registration page
      cy.url().should('include', '/register');
      cy.get('[data-testid="selected-plan"]', { timeout: 15000 }).should('be.visible');
      
      // Check accessibility
      cy.checkA11y();
      
      // Test form field accessibility
      cy.get('input[name="firstName"]').should('have.attr', 'required');
      cy.get('input[name="email"]').should('have.attr', 'type', 'email');
      
      // Check labels are properly associated
      cy.get('label[for="firstName"]').should('exist');
      cy.get('label[for="email"]').should('exist');
    });
  });

  describe('Authenticated Pages Accessibility', () => {
    beforeEach(() => {
      // Register and login a test user
      const timestamp = Date.now();
      cy.register({
        email: `a11y-test-${timestamp}@example.com`,
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'A11y',
        lastName: 'Tester',
        accountName: 'A11y Test Co'
      });
      
      // Re-inject axe after navigation
      cy.injectAxe();
    });

    it('should have no accessibility violations on dashboard', () => {
      cy.url().should('include', '/dashboard');
      
      // Wait for dashboard to load
      cy.get('[data-testid="user-menu"]').should('be.visible');
      
      // Check accessibility
      cy.checkA11y();
      
      // Test user menu accessibility
      cy.get('[data-testid="user-menu"]').focus().should('be.focused');
      cy.get('[data-testid="user-menu"]').click();
      
      // Check dropdown accessibility
      cy.get('[data-testid="logout-btn"]').should('be.visible');
      cy.checkA11y();
    });
  });

  describe('Keyboard Navigation', () => {
    it('should support keyboard navigation on login page', () => {
      cy.visit('/login');
      
      // Test that form elements are focusable
      cy.get('input[type="email"]').focus().should('be.focused');
      cy.get('input[type="password"]').focus().should('be.focused');
      cy.get('input[type="checkbox"]').focus().should('be.focused');
      cy.get('button[type="submit"]').focus().should('be.focused');
    });

    it('should support keyboard navigation on plans page', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
      
      // Should be able to navigate plan cards with keyboard
      cy.get('[data-testid="plan-card"]').first().focus();
      cy.focused().should('contain.text', 'Free').or('contain.text', '$');
      
      // Should be able to activate plan with Enter/Space
      cy.focused().type('{enter}');
      cy.get('[data-testid="plan-select-btn"]', { timeout: 10000 }).should('be.visible');
      
      // Continue button should be focusable
      cy.get('[data-testid="plan-select-btn"]').focus().should('be.focused');
    });

    it('should support keyboard navigation on registration page', () => {
      // Navigate to registration
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
      cy.get('[data-testid="plan-card"]').first().click();
      cy.get('[data-testid="plan-select-btn"]', { timeout: 10000 }).should('be.visible');
      cy.get('[data-testid="plan-select-btn"]').click();
      
      // Tab through registration form
      cy.get('body').tab();
      cy.focused().should('have.attr', 'name', 'accountName');
      
      cy.focused().tab();
      cy.focused().should('have.attr', 'name', 'firstName');
      
      cy.focused().tab();
      cy.focused().should('have.attr', 'name', 'lastName');
      
      cy.focused().tab();
      cy.focused().should('have.attr', 'name', 'email');
      
      cy.focused().tab();
      cy.focused().should('have.attr', 'name', 'password');
    });
  });

  describe('Screen Reader Support', () => {
    it('should have proper ARIA labels and roles', () => {
      cy.visit('/login');
      
      // Check for proper ARIA labels
      cy.get('input[type="email"]').should('have.attr', 'aria-label').or('be.labelledBy');
      cy.get('input[type="password"]').should('have.attr', 'aria-label').or('be.labelledBy');
      cy.get('button[type="submit"]').should('have.attr', 'aria-label').or('contain.text', 'Sign in');
      
      // Check for proper heading structure
      cy.get('h1, h2, h3').should('exist');
      
      // Check for landmarks
      cy.get('main, [role="main"]').should('exist');
    });

    it('should have proper form labels and descriptions', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
      cy.get('[data-testid="plan-card"]').first().click();
      cy.get('[data-testid="plan-select-btn"]', { timeout: 10000 }).should('be.visible');
      cy.get('[data-testid="plan-select-btn"]').click();
      
      // Check form labels
      cy.get('label[for="firstName"]').should('be.visible');
      cy.get('label[for="lastName"]').should('be.visible');
      cy.get('label[for="email"]').should('be.visible');
      cy.get('label[for="password"]').should('be.visible');
      
      // Check required field indicators
      cy.get('input[required]').should('have.attr', 'aria-required', 'true').or('have.attr', 'required');
    });

    it('should announce loading states to screen readers', () => {
      // Intercept plans API with delay
      cy.intercept('GET', '/api/v1/public/plans', (req) => {
        req.reply((res) => {
          return new Promise(resolve => {
            setTimeout(() => resolve(res), 1000);
          });
        });
      }).as('slowPlans');
      
      cy.visit('/plans');
      
      // Check for loading announcement
      cy.get('[aria-live]', { timeout: 5000 }).should('exist').or('contain.text', 'Loading');
      
      cy.wait('@slowPlans');
    });
  });

  describe('Color Contrast and Visual Accessibility', () => {
    it('should meet WCAG color contrast requirements', () => {
      cy.visit('/login');
      
      // Check color contrast specifically
      cy.checkA11y(null, {
        rules: {
          'color-contrast': { enabled: true }
        }
      });
      
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
      
      cy.checkA11y(null, {
        rules: {
          'color-contrast': { enabled: true }
        }
      });
    });

    it('should work with high contrast mode', () => {
      // Simulate high contrast mode
      cy.visit('/login');
      
      cy.window().then(win => {
        const style = win.document.createElement('style');
        style.textContent = `
          * {
            filter: contrast(2) !important;
          }
        `;
        win.document.head.appendChild(style);
      });
      
      // Elements should still be visible and functional
      cy.get('input[type="email"]').should('be.visible');
      cy.get('input[type="password"]').should('be.visible');
      cy.get('button[type="submit"]').should('be.visible');
      
      // Check accessibility
      cy.checkA11y();
    });

    it('should work without color as the only visual indicator', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
      cy.get('[data-testid="plan-card"]').first().click();
      cy.get('[data-testid="plan-select-btn"]', { timeout: 10000 }).should('be.visible');
      cy.get('[data-testid="plan-select-btn"]').click();
      
      // Fill form with invalid data
      cy.get('input[name="email"]').type('invalid-email');
      cy.get('input[name="password"]').type('short');
      
      // Error states should have text/icon indicators, not just color
      cy.get('input[name="email"]:invalid').should('exist');
      
      // Check for error text or icons
      cy.get('.error, [role="alert"], .invalid').should('exist').or('contain.text', 'error').or('contain.text', 'invalid');
    });
  });

  describe('Focus Management', () => {
    it('should maintain proper focus order', () => {
      cy.visit('/login');
      
      let focusOrder: string[] = [];
      
      // Track focus order
      cy.get('input, button, a, [tabindex]:not([tabindex="-1"])')
        .each(($el) => {
          cy.wrap($el).focus();
          cy.focused().then(($focused) => {
            focusOrder.push($focused.attr('name') || $focused.attr('type') || $focused.text());
          });
        });
      
      // Focus order should be logical
      expect(focusOrder).to.include.members(['email', 'password', 'submit']);
    });

    it('should trap focus in modals', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
      
      // Check if comparison modal exists and test focus trap
      cy.get('body').then($body => {
        if ($body.find('[data-testid="compare-btn"]').length > 0) {
          cy.get('[data-testid="compare-btn"]').click();
          
          // Focus should be trapped within modal
          cy.get('[role="dialog"]').should('exist');
          cy.focused().should('be.visible');
          
          // Tab should cycle within modal
          cy.focused().tab();
          cy.focused().should('exist');
        } else {
          cy.log('No modal found to test focus trap');
        }
      });
    });

    it('should restore focus after modal closes', () => {
      // This test would be implemented when modals are available
      cy.log('Focus restoration test - implement when modals are available');
    });
  });

  describe('Motion and Animation Accessibility', () => {
    it('should respect prefers-reduced-motion', () => {
      // Test with reduced motion preference
      cy.visit('/login', {
        onBeforeLoad: (win) => {
          Object.defineProperty(win, 'matchMedia', {
            writable: true,
            value: cy.stub().returns({
              matches: true,
              media: '(prefers-reduced-motion: reduce)',
              onchange: null,
              addListener: cy.stub(),
              removeListener: cy.stub(),
            }),
          });
        },
      });
      
      // Animations should be reduced or disabled
      cy.get('*').should('not.have.css', 'animation-duration', '300ms');
      cy.get('*').should('not.have.css', 'transition-duration', '300ms');
      
      cy.checkA11y();
    });

    it('should not have flashing content that could trigger seizures', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
      
      // Check for potential seizure-inducing animations
      cy.checkA11y(null, {
        rules: {
          'blink': { enabled: true },
          'marquee': { enabled: true }
        }
      });
    });
  });
});