describe('Debug Registration Form', () => {
  beforeEach(() => {
    cy.clearAppData();
  });

  it('should debug registration form submission', () => {
    // Visit plans page and select a plan
    cy.visit('/plans');
    cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
    cy.get('[data-testid="plan-select-btn"]').first().click({ force: true });
    cy.url().should('include', '/register');
    
    // Wait for plan to be loaded
    cy.get('[data-testid="selected-plan"]', { timeout: 15000 }).should('be.visible');
    
    // Fill form
    cy.get('input[name="accountName"]').clear({ force: true }).type('Debug Company', { force: true });
    cy.get('input[name="firstName"]').clear({ force: true }).type('Debug', { force: true });
    cy.get('input[name="lastName"]').clear({ force: true }).type('User', { force: true });
    cy.get('input[name="email"]').clear({ force: true }).type('debug@example.com', { force: true });
    cy.get('input[name="password"]').clear({ force: true }).type('Qx7#mK9@pL2$nZ6%', { force: true });
    
    // Check submit button state
    cy.get('button[type="submit"]').should('not.be.disabled', { timeout: 10000 });
    
    // Log form values
    cy.get('input[name="accountName"]').should('have.value', 'Debug Company');
    cy.get('input[name="firstName"]').should('have.value', 'Debug');
    cy.get('input[name="lastName"]').should('have.value', 'User');
    cy.get('input[name="email"]').should('have.value', 'debug@example.com');
    
    // Check Redux state
    cy.window().then((win) => {
      const state = win.store?.getState();
      cy.log('Auth state:', JSON.stringify(state?.auth || {}));
    });
    
    // Try to submit form (just click, don't wait for navigation)
    cy.get('button[type="submit"]').click({ force: true });
    
    // Wait a moment and check if URL changed
    cy.wait(3000);
    cy.url().then((url) => {
      cy.log('Current URL after submit:', url);
    });
    
    // Check if there are any error messages on the page
    cy.get('body').then($body => {
      if ($body.find('[class*="error"]').length) {
        cy.get('[class*="error"]').each(($el) => {
          cy.log('Error message found:', $el.text());
        });
      } else {
        cy.log('No error messages found on page');
      }
    });
  });
});