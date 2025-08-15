describe('API Request Debug', () => {
  beforeEach(() => {
    cy.clearAppData();
  });

  it('should capture and debug the exact API request being made', () => {
    let interceptedRequest: any = null;

    // Intercept registration API and capture the request
    cy.intercept('POST', '/api/v1/auth/register', (req) => {
      interceptedRequest = {
        url: req.url,
        method: req.method,
        headers: req.headers,
        body: req.body
      };
      // Let the request continue
      return req.continue();
    }).as('registerAPI');

    // Start the flow
    cy.visit('/plans');
    cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
    cy.get('[data-testid="plan-select-btn"]').first().click({ force: true });
    
    cy.url().should('include', '/register');
    cy.get('[data-testid="selected-plan"]', { timeout: 15000 }).should('be.visible');
    
    // Fill the form with exactly what worked in cURL
    cy.get('input[name="accountName"]').clear({ force: true }).type('Debug Test Co', { force: true });
    cy.get('input[name="firstName"]').clear({ force: true }).type('Debug', { force: true });
    cy.get('input[name="lastName"]').clear({ force: true }).type('Tester', { force: true });
    cy.get('input[name="email"]').clear({ force: true }).type('api-debug@test.co', { force: true });
    cy.get('input[name="password"]').clear({ force: true }).type('Qx7#mK9@pL2$nZ6%', { force: true });
    
    // Submit form
    cy.get('button[type="submit"]').should('not.be.disabled');
    cy.get('button[type="submit"]').click({ force: true });
    
    // Wait for API call
    cy.wait('@registerAPI').then((interception) => {
      // Log the exact request details
      cy.log('API Request URL:', interception.request.url);
      cy.log('API Request Method:', interception.request.method);
      cy.log('API Request Headers:', JSON.stringify(interception.request.headers, null, 2));
      cy.log('API Request Body:', JSON.stringify(interception.request.body, null, 2));
      
      if (interception.response) {
        cy.log('API Response Status:', interception.response.statusCode);
        cy.log('API Response Body:', JSON.stringify(interception.response.body, null, 2));
        
        // If it's an error response, show it clearly
        if (interception.response.statusCode !== 200) {
          cy.log('ERROR DETAILS:', JSON.stringify(interception.response.body, null, 2));
        }
      }
    });
  });

  it('should test the exact working cURL request via Cypress API', () => {
    // Make the exact same API call that worked in cURL
    cy.request({
      method: 'POST',
      url: 'http://localhost:3000/api/v1/auth/register',
      headers: {
        'Content-Type': 'application/json'
      },
      body: {
        email: 'curl-debug@test.co',
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'Debug',
        lastName: 'Tester',
        accountName: 'Debug Test Co',
        planId: '01989991-0039-7f0f-ae0b-702330e26324',
        billingCycle: 'monthly'
      }
    }).then((response) => {
      cy.log('Direct API Success:', JSON.stringify(response.body, null, 2));
      expect([200, 201]).to.include(response.status);
      expect(response.body.success).to.be.true;
    });
  });
});