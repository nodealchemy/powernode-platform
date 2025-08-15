describe('Logo Contrast and Hover State Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
  });

  it('should have proper hover state on login page logo', () => {
    cy.visit('/login');
    
    // Find the logo
    const logoSelector = '.bg-theme-interactive-primary';
    
    // Check initial state
    cy.get(logoSelector).first()
      .should('be.visible')
      .should('have.class', 'bg-theme-interactive-primary');
    
    // Check that it has hover classes defined
    cy.get(logoSelector).first()
      .should('have.class', 'group-hover:bg-theme-interactive-primary-hover');
    
    // Verify transform scale on hover
    cy.get(logoSelector).first()
      .should('have.class', 'group-hover:scale-105');
    
    // Verify shadow enhancement on hover
    cy.get(logoSelector).first()
      .should('have.class', 'group-hover:shadow-xl');
  });

  it('should have proper hover state on register page logo', () => {
    cy.visit('/register');
    
    // Check for plan selection redirect
    cy.url().then(url => {
      if (url.includes('/plans')) {
        cy.visit('/register?plan=test');
      }
    });
    
    // Find the logo
    const logoSelector = '.bg-theme-interactive-primary';
    
    cy.get('body').then($body => {
      if ($body.find(logoSelector).length > 0) {
        // Check hover classes
        cy.get(logoSelector).first()
          .should('have.class', 'bg-theme-interactive-primary')
          .should('have.class', 'group-hover:bg-theme-interactive-primary-hover')
          .should('have.class', 'group-hover:scale-105');
      }
    });
  });

  it('should maintain white text contrast on logo hover', () => {
    cy.visit('/login');
    
    // The white "P" text should remain white on hover
    cy.get('.bg-theme-interactive-primary span.text-white')
      .should('be.visible')
      .should('have.class', 'text-white');
    
    // Trigger hover
    cy.get('.bg-theme-interactive-primary').first().parent().trigger('mouseover');
    
    // Text should still be white
    cy.get('.bg-theme-interactive-primary span.text-white')
      .should('have.class', 'text-white');
  });

  it('should have smooth transition effects', () => {
    cy.visit('/login');
    
    // Check for transition classes
    cy.get('.bg-theme-interactive-primary').first()
      .should('have.class', 'transition-all')
      .should('have.class', 'duration-200');
  });

  it('should test contrast in both light and dark themes if available', () => {
    cy.visit('/login');
    
    // Test in default theme (light)
    cy.get('.bg-theme-interactive-primary').first()
      .should('be.visible');
    
    // Check if theme toggle exists on login page
    cy.get('body').then($body => {
      // Login page typically doesn't have theme toggle, but let's check
      const themeToggle = $body.find('[aria-label*="theme"], [title*="theme"], button:contains("theme")');
      
      if (themeToggle.length > 0) {
        // Toggle to dark theme
        cy.wrap(themeToggle).first().click();
        
        // Logo should still be visible and have proper contrast
        cy.get('.bg-theme-interactive-primary').first()
          .should('be.visible');
      } else {
        cy.log('Theme toggle not available on login page - testing in default theme only');
      }
    });
  });

  it('should verify visual feedback on interaction', () => {
    cy.visit('/login');
    
    const logo = cy.get('.bg-theme-interactive-primary').first().parent();
    
    // Check initial state
    logo.should('have.attr', 'href', '/welcome');
    
    // Hover interaction
    logo.trigger('mouseover');
    
    // Check that it's still clickable
    logo.should('not.be.disabled');
    
    // Mouse leave
    logo.trigger('mouseleave');
    
    // Focus interaction (keyboard navigation)
    logo.focus();
    logo.should('be.focused');
    
    // Blur
    logo.blur();
    logo.should('not.be.focused');
  });
});