describe('Logo Navigation Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
  });

  it('should navigate to welcome page when clicking the logo', () => {
    // Create and login a test user
    const userData = {
      email: `logo-nav-${Date.now()}@example.com`,
      password: 'TestPassword123!',
      firstName: 'Logo',
      lastName: 'Test',
      accountName: 'Logo Test Co'
    };

    // Register and login
    cy.register(userData);
    
    // Should be on dashboard after registration
    cy.url().should('include', '/dashboard');
    
    // Find and click the logo in the sidebar
    cy.get('.bg-theme-interactive-primary').first().parent().should('exist');
    
    // Click the logo link
    cy.get('a[title="Go to Welcome Page"]').first().click();
    
    // Should navigate to the welcome/home page
    cy.url().should('eq', `${Cypress.config().baseUrl}/`);
    
    // Verify we're on the welcome page
    cy.get('body').should('satisfy', ($body) => {
      const text = $body.text();
      return text.includes('Welcome') || 
             text.includes('Get Started') || 
             text.includes('Powernode') ||
             text.includes('Sign');
    });
  });

  it('should have hover effects on the logo', () => {
    // Create and login a test user
    const userData = {
      email: `logo-hover-${Date.now()}@example.com`,
      password: 'TestPassword123!',
      firstName: 'Hover',
      lastName: 'Test',
      accountName: 'Hover Test Co'
    };

    cy.register(userData);
    cy.url().should('include', '/dashboard');
    
    // Check that the logo link exists
    cy.get('a[title="Go to Welcome Page"]').should('exist');
    
    // Check hover state (visual check)
    cy.get('a[title="Go to Welcome Page"]').first().trigger('mouseover');
    
    // The logo should have the group hover classes applied
    cy.get('a[title="Go to Welcome Page"]').first()
      .find('.bg-theme-interactive-primary')
      .should('have.class', 'group-hover:bg-theme-interactive-secondary');
  });

  it('should work from any dashboard page', () => {
    // Create and login a test user
    const userData = {
      email: `logo-pages-${Date.now()}@example.com`,
      password: 'TestPassword123!',
      firstName: 'Pages',
      lastName: 'Test',
      accountName: 'Pages Test Co'
    };

    cy.register(userData);
    
    // Navigate to different dashboard pages and test logo link
    const pages = [
      '/dashboard',
      '/dashboard/analytics',
      '/dashboard/account',
      '/dashboard/account/profile'
    ];

    pages.forEach(page => {
      cy.visit(page);
      cy.url().should('include', page);
      
      // Click logo to go to welcome page
      cy.get('a[title="Go to Welcome Page"]').first().click();
      cy.url().should('eq', `${Cypress.config().baseUrl}/`);
      
      // Go back to test next page
      cy.go('back');
    });
  });
});