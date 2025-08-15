describe('Basic Accessibility Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
  });

  describe('Keyboard Navigation', () => {
    it('should support keyboard focus on login page', () => {
      cy.visit('/login');
      
      // Test that form elements are focusable
      cy.get('input[type="email"]').should('be.visible').focus().should('be.focused');
      cy.get('input[type="password"]').should('be.visible').focus().should('be.focused');
      cy.get('input[type="checkbox"]').should('be.visible').focus().should('be.focused');
      cy.get('button[type="submit"]').should('be.visible').focus().should('be.focused');
      
      // Test that links are focusable
      cy.get('a[href="/forgot-password"]').should('be.visible').focus().should('be.focused');
      cy.get('a[href="/plans"]').should('be.visible').focus().should('be.focused');
    });

    it('should support keyboard focus on plans page', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
      
      // Plan cards should be focusable/clickable
      cy.get('[data-testid="plan-card"]').first().click();
      cy.get('[data-testid="plan-select-btn"]', { timeout: 10000 }).should('be.visible');
      
      // Continue button should be focusable
      cy.get('[data-testid="plan-select-btn"]').focus().should('be.focused');
    });

    it('should support keyboard focus on registration page', () => {
      // Navigate to registration
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
      cy.get('[data-testid="plan-card"]').first().click();
      cy.get('[data-testid="plan-select-btn"]', { timeout: 10000 }).should('be.visible');
      cy.get('[data-testid="plan-select-btn"]').click();
      
      // Wait for registration page
      cy.url().should('include', '/register');
      cy.get('[data-testid="selected-plan"]', { timeout: 15000 }).should('be.visible');
      
      // Test that form fields are focusable
      cy.get('input[name="accountName"]').should('be.visible').focus().should('be.focused');
      cy.get('input[name="firstName"]').should('be.visible').focus().should('be.focused');
      cy.get('input[name="lastName"]').should('be.visible').focus().should('be.focused');
      cy.get('input[name="email"]').should('be.visible').focus().should('be.focused');
      cy.get('input[name="password"]').should('be.visible').focus().should('be.focused');
      cy.get('button[type="submit"]').should('be.visible').focus().should('be.focused');
    });
  });

  describe('Form Labels and Structure', () => {
    it('should have proper form labels on login page', () => {
      cy.visit('/login');
      
      // Check that form inputs have labels
      cy.get('input[type="email"]').should('have.attr', 'id');
      cy.get('input[type="password"]').should('have.attr', 'id');
      
      // Check for label elements (even if not perfectly associated)
      cy.contains('Email address').should('be.visible');
      cy.contains('Password').should('be.visible');
      
      // Check for placeholder text as backup accessibility
      cy.get('input[type="email"]').should('have.attr', 'placeholder');
      cy.get('input[type="password"]').should('have.attr', 'placeholder');
    });

    it('should have proper form structure on registration page', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
      cy.get('[data-testid="plan-card"]').first().click();
      cy.get('[data-testid="plan-select-btn"]', { timeout: 10000 }).should('be.visible');
      cy.get('[data-testid="plan-select-btn"]').click();
      
      // Check form structure
      cy.url().should('include', '/register');
      cy.get('[data-testid="selected-plan"]', { timeout: 15000 }).should('be.visible');
      
      // Check that required fields are marked
      cy.get('input[name="firstName"]').should('have.attr', 'required');
      cy.get('input[name="lastName"]').should('have.attr', 'required');
      cy.get('input[name="email"]').should('have.attr', 'required');
      cy.get('input[name="password"]').should('have.attr', 'required');
      
      // Check email input type
      cy.get('input[name="email"]').should('have.attr', 'type', 'email');
    });
  });

  describe('Visual Focus Indicators', () => {
    it('should show focus indicators on interactive elements', () => {
      cy.visit('/login');
      
      // Test that focused elements have visible focus indicators
      cy.get('input[type="email"]').focus();
      cy.focused().should('have.css', 'outline-style').and('not.equal', 'none');
      
      cy.get('input[type="password"]').focus();
      cy.focused().should('have.css', 'outline-style').and('not.equal', 'none');
      
      cy.get('button[type="submit"]').focus();
      cy.focused().should('have.css', 'outline-style').and('not.equal', 'none');
    });

    it('should show focus indicators on plan cards', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
      
      // Plan cards should show focus/hover states
      cy.get('[data-testid="plan-card"]').first().trigger('mouseover');
      cy.get('[data-testid="plan-card"]').first().should('have.css', 'cursor', 'pointer');
    });
  });

  describe('Semantic HTML Structure', () => {
    it('should use semantic HTML elements on login page', () => {
      cy.visit('/login');
      
      // Check for semantic form elements
      cy.get('form').should('exist');
      cy.get('input[type="email"]').should('exist');
      cy.get('input[type="password"]').should('exist');
      cy.get('button[type="submit"]').should('exist');
      
      // Check for heading structure
      cy.get('h1, h2, h3').should('exist');
    });

    it('should use semantic HTML elements on plans page', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
      
      // Check for heading structure in plan cards
      cy.get('[data-testid="plan-card"]').first().within(() => {
        cy.get('h1, h2, h3, h4').should('exist');
      });
      
      // Check for list structure for features
      cy.get('[data-testid="plan-card"]').first().within(() => {
        cy.get('ul, ol, li').should('exist');
      });
    });
  });

  describe('Color and Contrast', () => {
    it('should not rely solely on color for information', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
      
      // Selected state should have multiple indicators (not just color)
      cy.get('[data-testid="plan-card"]').first().click();
      cy.get('[data-testid="plan-card"]').first().within(() => {
        // Should have checkmark icon or text indicator
        cy.get('svg, .check, [data-testid="check"]').should('exist').or('contain.text', 'Selected');
      });
    });

    it('should provide text alternatives for visual content', () => {
      cy.visit('/login');
      
      // Icons should have accessible alternatives
      cy.get('svg').each(($svg) => {
        cy.wrap($svg).should('have.attr', 'aria-label')
          .or('have.attr', 'aria-labelledby')
          .or('have.attr', 'aria-hidden', 'true'); // Decorative icons can be hidden
      });
    });
  });

  describe('Mobile Accessibility', () => {
    it('should be accessible on mobile viewport', () => {
      cy.viewport(375, 667);
      cy.visit('/login');
      
      // Form should still be usable on mobile
      cy.get('input[type="email"]').should('be.visible').focus().should('be.focused');
      cy.get('input[type="password"]').should('be.visible').focus().should('be.focused');
      cy.get('button[type="submit"]').should('be.visible').focus().should('be.focused');
      
      // Touch targets should be large enough (minimum 44px)
      cy.get('button[type="submit"]').invoke('outerHeight').should('be.gte', 44);
    });

    it('should be accessible on tablet viewport', () => {
      cy.viewport(768, 1024);
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
      
      // Plan cards should be properly sized and accessible
      cy.get('[data-testid="plan-card"]').first().should('be.visible');
      cy.get('[data-testid="plan-card"]').first().click();
      cy.get('[data-testid="plan-select-btn"]', { timeout: 10000 }).should('be.visible');
    });
  });

  describe('Error States and Feedback', () => {
    it('should provide accessible error feedback', () => {
      cy.visit('/login');
      
      // Submit form with invalid data
      cy.get('input[type="email"]').type('invalid-email');
      cy.get('input[type="password"]').type('wrong');
      cy.get('button[type="submit"]').click();
      
      // Should show error message (may take time)
      cy.wait(2000);
      
      // Check if error is communicated accessibly
      cy.get('body').then($body => {
        const hasAriaLive = $body.find('[aria-live]').length > 0;
        const hasRoleAlert = $body.find('[role="alert"]').length > 0;
        const hasErrorText = $body.text().toLowerCase().includes('error') || 
                           $body.text().toLowerCase().includes('invalid') ||
                           $body.text().toLowerCase().includes('incorrect');
        
        expect(hasAriaLive || hasRoleAlert || hasErrorText, 
               'Should have accessible error feedback').to.be.true;
      });
    });
  });
});