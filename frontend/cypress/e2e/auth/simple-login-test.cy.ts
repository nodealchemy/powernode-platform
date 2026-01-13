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
    
    // Try to find the test IDs
    cy.get('body').then($body => {
      if ($body.find('[data-testid="email-input"]').length) {
        cy.log('✓ Email test ID found');
        cy.get('[data-testid="email-input"]').should('be.visible');
      } else {
        cy.log('✗ Email test ID not found - checking placeholder');
        cy.get('input[placeholder*="email" i]').should('be.visible');
      }
      
      if ($body.find('[data-testid="password-input"]').length) {
        cy.log('✓ Password test ID found');
        cy.get('[data-testid="password-input"]').should('be.visible');
      } else {
        cy.log('✗ Password test ID not found - checking placeholder');
        cy.get('input[placeholder*="password" i]').should('be.visible');
      }
      
      if ($body.find('[data-testid="login-submit-btn"]').length) {
        cy.log('✓ Submit test ID found');
        cy.get('[data-testid="login-submit-btn"]').should('be.visible');
      } else {
        cy.log('✗ Submit test ID not found - using type selector');
        cy.get('button[type="submit"]').should('be.visible');
      }
    });
  });
});