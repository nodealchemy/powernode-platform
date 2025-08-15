describe('Direct API Authentication Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
  });

  it('should register and authenticate via direct API calls', () => {
    // Test 1: Direct registration via API
    cy.request({
      method: 'POST',
      url: 'http://localhost:3000/api/v1/auth/register',
      body: {
        email: 'api-test@example.com',
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'API',
        lastName: 'Test',
        accountName: 'API Test Company',
        planId: '01989991-0039-7f0f-ae0b-702330e26324',
        billingCycle: 'monthly'
      }
    }).then((response) => {
      expect(response.status).to.eq(200);
      expect(response.body.success).to.be.true;
      expect(response.body.user.emailVerified).to.be.true;
      expect(response.body.access_token).to.exist;
      
      const accessToken = response.body.access_token;
      const user = response.body.user;
      
      cy.log('Registration successful:', {
        email: user.email,
        name: user.fullName,
        emailVerified: user.emailVerified
      });

      // Test 2: Set tokens in localStorage and visit dashboard
      cy.window().then((win) => {
        win.localStorage.setItem('accessToken', accessToken);
      });

      // Test 3: Visit dashboard and verify authentication
      cy.visit('/dashboard');
      cy.url().should('include', '/dashboard');
      cy.contains(user.firstName).should('be.visible');
      
      cy.log('Dashboard access successful');
    });
  });

  it('should test login flow with pre-registered user', () => {
    // First register a user via API
    cy.request({
      method: 'POST', 
      url: 'http://localhost:3000/api/v1/auth/register',
      body: {
        email: 'login-test@example.com',
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'Login',
        lastName: 'Test', 
        accountName: 'Login Test Company',
        planId: '01989991-0039-7f0f-ae0b-702330e26324',
        billingCycle: 'monthly'
      }
    }).then((response) => {
      expect(response.status).to.eq(200);
      
      // Now test login via API
      cy.request({
        method: 'POST',
        url: 'http://localhost:3000/api/v1/auth/login', 
        body: {
          email: 'login-test@example.com',
          password: 'Qx7#mK9@pL2$nZ6%'
        }
      }).then((loginResponse) => {
        expect(loginResponse.status).to.eq(200);
        expect(loginResponse.body.success).to.be.true;
        expect(loginResponse.body.access_token).to.exist;
        
        // Set token and verify UI access
        cy.window().then((win) => {
          win.localStorage.setItem('accessToken', loginResponse.body.access_token);
        });
        
        cy.visit('/dashboard');
        cy.url().should('include', '/dashboard');
        cy.contains('Login').should('be.visible');
        
        cy.log('Login flow successful');
      });
    });
  });

  it('should test protected route access', () => {
    // Visit dashboard without authentication
    cy.visit('/dashboard');
    cy.url().should('include', '/login');
    cy.log('Unauthenticated redirect working');
    
    // Register and test authenticated access
    cy.request({
      method: 'POST',
      url: 'http://localhost:3000/api/v1/auth/register', 
      body: {
        email: 'protected@example.com',
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'Protected',
        lastName: 'Test',
        accountName: 'Protected Test Company', 
        planId: '01989991-0039-7f0f-ae0b-702330e26324',
        billingCycle: 'monthly'
      }
    }).then((response) => {
      cy.window().then((win) => {
        win.localStorage.setItem('accessToken', response.body.access_token);
      });
      
      // Test various protected routes
      cy.visit('/dashboard');
      cy.url().should('include', '/dashboard');
      
      cy.visit('/dashboard/analytics'); 
      cy.url().should('include', '/dashboard');
      
      cy.log('Protected routes working correctly');
    });
  });
});