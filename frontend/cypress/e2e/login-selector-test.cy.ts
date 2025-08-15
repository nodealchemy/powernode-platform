describe('Login Selector Test', () => {
  const timestamp = Date.now();
  
  it('should test login form selectors', () => {
    // First create a test user
    const email = `selector-test-${timestamp}@example.com`;
    
    cy.clearAppData();
    cy.register({
      email,
      password: 'Qx7#mK9@pL2$nZ6%',
      firstName: 'Selector',
      lastName: 'Test',
      accountName: 'Selector Test Co'
    });
    
    // Logout
    cy.get('[data-testid="user-menu"]').click();
    cy.get('[data-testid="logout-btn"]').click();
    
    // Now test login with new selectors
    cy.visit('/login');
    
    // Test new data-testid selectors
    cy.get('[data-testid="email-input"]').should('be.visible').type(email);
    cy.get('[data-testid="password-input"]').should('be.visible').type('Qx7#mK9@pL2$nZ6%');
    cy.get('[data-testid="login-submit-btn"]').should('be.visible').click();
    
    // Should login successfully
    cy.url().should('include', '/dashboard');
    cy.contains('Welcome back, Selector!').should('be.visible');
  });
});