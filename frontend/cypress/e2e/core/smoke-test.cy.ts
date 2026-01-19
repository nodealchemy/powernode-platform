describe('Smoke Test', () => {
  it('should load the welcome page', () => {
    cy.visit('/');
    // Welcome page should load with Powernode branding or content
    cy.get('body', { timeout: 10000 }).should('be.visible');
    // Page should have either the welcome content, brand name, or navigation
    cy.assertContainsAny(['Powernode', 'Welcome', 'Plans', 'Sign In', 'Get Started']);
  });

  it('should navigate to login page', () => {
    cy.visit('/login');
    // Login page has "Sign in" text and form inputs
    cy.assertContainsAny(['Sign in', 'Login', 'Email']);
    cy.get('input[type="email"], input[name="email"], [data-testid="email-input"]')
      .first()
      .should('be.visible');
    cy.get('input[type="password"], input[name="password"], [data-testid="password-input"]')
      .first()
      .should('be.visible');
  });

  it('should login with demo account', () => {
    // Login using standardized command
    cy.loginAsDemo();

    // After login, user is redirected to either /app or /dashboard
    cy.url({ timeout: 10000 }).should('match', /\/(app|dashboard)/);
  });
});


export {};
