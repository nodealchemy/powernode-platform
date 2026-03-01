describe('Simple Login Test', () => {
  it('should visit login page and check elements', () => {
    cy.clearAppData();
    cy.visit('/login');
    
    // Check if login page loads
    cy.contains('Sign in').should('be.visible');
    
    // Check for form elements by different selectors
    cy.get('input[type="email"]').should('exist');
    cy.get('input[type="password"]').should('exist');
    cy.get('button[type="submit"]').should('exist');
    
    // Verify test IDs are present
    cy.get('[data-testid="email-input"]').should('be.visible');
    cy.get('[data-testid="password-input"]').should('be.visible');
    cy.get('[data-testid="login-submit-btn"]').should('be.visible');
  });
});

export {};
