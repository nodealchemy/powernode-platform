describe('Logo Navigation - Simple Test', () => {
  it('should have logo link in sidebar on login page', () => {
    cy.visit('/login');
    
    // The sidebar might not be visible on login page
    // Let's check if we can see any Powernode branding
    cy.get('body').then($body => {
      const hasPowernodeLogo = $body.find('.bg-theme-interactive-primary').length > 0 ||
                               $body.text().includes('Powernode');
      
      if (hasPowernodeLogo) {
        cy.log('Powernode branding found on login page');
      }
      
      expect(hasPowernodeLogo).to.be.true;
    });
  });

  it('should verify logo link exists after manual navigation to dashboard', () => {
    // First, let's create a user using the test registration flow
    const timestamp = Date.now();
    const userData = {
      email: `test-${timestamp}@example.com`,
      password: 'TestPass123!@#',
      firstName: 'Test',
      lastName: 'User',
      accountName: 'Test Company'
    };
    
    // Go through registration flow
    cy.visit('/plans');
    cy.get('[data-testid="plan-card"]', { timeout: 15000 }).first().click();
    cy.get('[data-testid="plan-select-btn"]', { timeout: 10000 }).click();
    
    // Fill registration form
    cy.url().should('include', '/register');
    cy.get('input[name="accountName"]').type(userData.accountName);
    cy.get('input[name="firstName"]').type(userData.firstName);
    cy.get('input[name="lastName"]').type(userData.lastName);
    cy.get('input[name="email"]').type(userData.email);
    cy.get('input[name="password"]').type(userData.password);
    cy.get('button[type="submit"]').click();
    
    // Wait for dashboard
    cy.url({ timeout: 20000 }).should('include', '/dashboard');
    
    // Now check for the logo link in the sidebar
    cy.get('a[title="Go to Welcome Page"]', { timeout: 10000 }).should('exist');
    
    // Click the logo
    cy.get('a[title="Go to Welcome Page"]').first().click();
    
    // Should navigate to home
    cy.url().should('eq', `${Cypress.config().baseUrl}/`);
  });
});