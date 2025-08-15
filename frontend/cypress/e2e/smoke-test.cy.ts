describe('Smoke Test', () => {
  it('should load the welcome page', () => {
    cy.visit('/');
    cy.contains('Welcome to Powernode').should('be.visible');
  });

  it('should navigate to login page', () => {
    cy.visit('/login');
    cy.contains('Sign in to your account').should('be.visible');
    cy.get('[data-testid="email-input"]').should('be.visible');
    cy.get('[data-testid="password-input"]').should('be.visible');
  });

  it('should login with demo account', () => {
    cy.visit('/login');
    cy.get('[data-testid="email-input"]').type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-button"]').click();
    
    cy.url({ timeout: 10000 }).should('include', '/dashboard');
    cy.contains('Dashboard', { timeout: 10000 }).should('be.visible');
  });
});