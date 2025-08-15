describe('Register Command Debug', () => {
  beforeEach(() => {
    cy.clearAppData();
  });

  it('should debug the cy.register command step by step', () => {
    // Test the exact same steps as the register command but manually
    
    // First visit plans page and select a plan (if redirected from /register)
    cy.visit('/plans');
    
    // Wait for plans to load and select the first available plan
    cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
    cy.get('[data-testid="plan-select-btn"]').first().click();
    
    // Should be redirected to register page with plan selected
    cy.url().should('include', '/register');
    
    // Wait for plan to be loaded and displayed (this enables the submit button)
    cy.get('[data-testid="selected-plan"]').should('be.visible');
    
    // Fill out the registration form with delay to avoid race conditions
    const userData = {
      accountName: 'Command Debug Co',
      firstName: 'Command',
      lastName: 'Debug',
      email: 'command@debug.co',
      password: 'Qx7#mK9@pL2$nZ6%'
    };
    
    cy.get('input[name="accountName"]').should('be.visible').clear({ force: true }).type(userData.accountName, { force: true });
    cy.get('input[name="firstName"]').should('be.visible').clear({ force: true }).type(userData.firstName, { force: true });
    cy.get('input[name="lastName"]').should('be.visible').clear({ force: true }).type(userData.lastName, { force: true });
    cy.get('input[name="email"]').should('be.visible').clear({ force: true }).type(userData.email, { force: true });
    cy.get('input[name="password"]').should('be.visible').clear({ force: true }).type(userData.password, { force: true });
    
    // Wait for form validation to pass before submitting
    cy.get('button[type="submit"]').should('not.be.disabled', { timeout: 10000 });
    cy.get('button[type="submit"]').click({ force: true });
    
    // Registration should now auto-verify email in test mode
    // No need for manual email verification bypass
    
    cy.url().should('include', '/dashboard', { timeout: 20000 });
  });

  it('should test the actual cy.register command', () => {
    cy.register({
      email: 'register-cmd@test.co',
      password: 'Qx7#mK9@pL2$nZ6%',
      firstName: 'Register',
      lastName: 'Cmd',
      accountName: 'Register Cmd Co',
    });
    
    // Should be on dashboard
    cy.url().should('include', '/dashboard');
    
    // Should show user info
    cy.contains('Register').should('be.visible');
  });
  
  it('should compare API direct vs command approaches', () => {
    // First do it via API
    cy.request({
      method: 'POST',
      url: 'http://localhost:3000/api/v1/auth/register',
      headers: {
        'Content-Type': 'application/json'
      },
      body: {
        email: 'api-comparison@test.co',
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'API',
        lastName: 'Comparison',
        accountName: 'API Comparison Co',
        planId: '01989991-0039-7f0f-ae0b-702330e26324',
        billingCycle: 'monthly'
      }
    }).then((response) => {
      expect([200, 201]).to.include(response.status);
      expect(response.body.success).to.be.true;
      
      // Set tokens
      cy.window().then((win) => {
        win.localStorage.setItem('accessToken', response.body.access_token);
      });
      
      // Visit dashboard directly
      cy.visit('/dashboard');
      cy.url().should('include', '/dashboard');
      cy.contains('API').should('be.visible');
      
      // Clear for next test
      cy.clearAppData();
    });
    
    // Now test via command
    cy.register({
      email: 'cmd-comparison@test.co',
      password: 'Qx7#mK9@pL2$nZ6%',
      firstName: 'Cmd',
      lastName: 'Comparison',
      accountName: 'Cmd Comparison Co',
    });
    
    cy.url().should('include', '/dashboard');
    cy.contains('Cmd').should('be.visible');
  });
});