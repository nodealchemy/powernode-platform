describe('Form Submission Debug', () => {
  beforeEach(() => {
    cy.clearAppData();
  });

  it('should debug form submission step by step', () => {
    // Monitor all console logs
    cy.window().then((win) => {
      cy.stub(win.console, 'log').as('consoleLog');
      cy.stub(win.console, 'error').as('consoleError');
      cy.stub(win.console, 'warn').as('consoleWarn');
    });

    // Intercept all API calls to see what's being sent
    cy.intercept('GET', '/api/v1/public/plans').as('getPlans');
    cy.intercept('POST', '/api/v1/auth/register').as('registerAPI');
    cy.intercept('GET', '/api/v1/auth/me').as('getCurrentUser');

    // Start the flow
    cy.visit('/plans');
    
    // Wait for plans to load (either by API or already cached)
    cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
    
    // Check if plans API was called (but don't fail if it wasn't)
    cy.then(() => {
      cy.get('@getPlans.all').then((calls) => {
        if (calls.length > 0) {
          cy.log('Plans API was called:', calls[0]);
        } else {
          cy.log('Plans API was not called (possibly cached)');
        }
      });
    });
    cy.get('[data-testid="plan-select-btn"]').first().click({ force: true });
    
    cy.url().should('include', '/register');
    cy.get('[data-testid="selected-plan"]', { timeout: 15000 }).should('be.visible');
    
    // Fill the form
    cy.get('input[name="accountName"]').clear({ force: true }).type('Debug Test Co', { force: true });
    cy.get('input[name="firstName"]').clear({ force: true }).type('Debug', { force: true });
    cy.get('input[name="lastName"]').clear({ force: true }).type('Tester', { force: true });
    cy.get('input[name="email"]').clear({ force: true }).type('debug@test.co', { force: true });
    cy.get('input[name="password"]').clear({ force: true }).type('Qx7#mK9@pL2$nZ6%', { force: true });
    
    // Verify form is valid
    cy.get('button[type="submit"]').should('not.be.disabled');
    
    // Check Redux state before submit
    cy.window().then((win) => {
      const state = win.store?.getState();
      cy.log('Pre-submit Redux state:', JSON.stringify({
        isAuthenticated: state?.auth?.isAuthenticated,
        user: state?.auth?.user,
        isLoading: state?.auth?.isLoading,
        error: state?.auth?.error
      }));
    });

    // Click submit and immediately check for changes
    cy.get('button[type="submit"]').click({ force: true });
    
    // Wait briefly and check Redux state again
    cy.wait(1000);
    cy.window().then((win) => {
      const state = win.store?.getState();
      cy.log('Post-click Redux state:', JSON.stringify({
        isAuthenticated: state?.auth?.isAuthenticated,
        user: state?.auth?.user,
        isLoading: state?.auth?.isLoading,
        error: state?.auth?.error
      }));
    });

    // Check if API call was made
    cy.wait('@registerAPI', { timeout: 15000 }).then((interception) => {
      cy.log('Registration API called with:', interception.request.body);
      cy.log('Registration API response:', interception.response?.body);
      
      expect(interception.response?.statusCode).to.eq(200);
      
      // Check Redux state after API response
      cy.window().then((win) => {
        const state = win.store?.getState();
        cy.log('Post-API Redux state:', JSON.stringify({
          isAuthenticated: state?.auth?.isAuthenticated,
          user: state?.auth?.user,
          isLoading: state?.auth?.isLoading,
          error: state?.auth?.error
        }));
      });
      
      // Give time for navigation
      cy.wait(2000);
      
      // Check final state
      cy.url().then(url => cy.log('Final URL:', url));
      cy.window().then((win) => {
        const state = win.store?.getState();
        cy.log('Final Redux state:', JSON.stringify({
          isAuthenticated: state?.auth?.isAuthenticated,
          user: state?.auth?.user?.firstName,
          isLoading: state?.auth?.isLoading,
          error: state?.auth?.error
        }));
      });
    });

    // Check for console errors
    cy.get('@consoleError').then((spy) => {
      if (spy.callCount > 0) {
        cy.log('Console errors found:', spy.getCalls().map(call => call.args));
      } else {
        cy.log('No console errors found');
      }
    });

    // Final assertion - if this fails, we have our debugging info
    cy.url().should('include', '/dashboard', { timeout: 5000 });
  });
});