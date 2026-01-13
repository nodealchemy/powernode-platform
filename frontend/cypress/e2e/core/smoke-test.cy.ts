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
    cy.visit('/login');
    cy.get('[data-testid="email-input"]').type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();

    // After login, user is redirected to either /app or /dashboard
    cy.url({ timeout: 10000 }).should('match', /\/(app|dashboard)/);
  });
});
