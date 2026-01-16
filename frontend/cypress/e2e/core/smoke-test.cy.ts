describe('Smoke Test', () => {
  it('should load the welcome page', () => {
    cy.visit('/');
    cy.contains('Welcome to Powernode').should('be.visible');
  });

  it('should navigate to login page', () => {
    cy.visit('/login');
    cy.contains('Sign in to Dashboard').should('be.visible');
    cy.get('input[name="email"]').should('be.visible');
    cy.get('input[name="password"]').should('be.visible');
  });

  it('should login with demo account', () => {
    // Login using standardized command
    cy.loginAsDemo();

    // After login, user is redirected to either /app or /dashboard
    cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
  });
});


export {};
