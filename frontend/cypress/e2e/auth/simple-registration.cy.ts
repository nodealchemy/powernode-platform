describe('Simple Registration Test', () => {
  beforeEach(() => {
    cy.clearAppData();
  });

  it('should register using the register command', () => {
    const timestamp = Date.now();
    cy.register({
      email: `simple-${timestamp}@example.com`,
      password: 'Qx7#mK9@pL2$nZ6%',
      name: 'Simple User',
      accountName: 'Simple Company',
    });

    // After registration, user is either:
    // - redirected to /app or /dashboard (if auto-verified or email verification disabled)
    // - redirected to /verify-email (if email verification required)
    cy.url().should('match', /\/(app|dashboard|verify-email)/);
  });
});


export {};
