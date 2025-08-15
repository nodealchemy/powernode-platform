describe('Simple Registration Test', () => {
  beforeEach(() => {
    cy.clearAppData();
  });

  it('should register using the register command', () => {
    cy.register({
      email: 'simple@example.com',
      password: 'Qx7#mK9@pL2$nZ6%',
      firstName: 'Simple',
      lastName: 'User',
      accountName: 'Simple Company',
    });
    
    // Should be on dashboard
    cy.url().should('include', '/dashboard');
    cy.contains('Simple').should('be.visible');
  });
});