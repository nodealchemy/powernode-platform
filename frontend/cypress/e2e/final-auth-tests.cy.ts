describe('Final Authentication Tests', () => {
  const timestamp = Date.now();
  
  beforeEach(() => {
    cy.clearAppData();
  });

  describe('User Registration', () => {
    it('should allow new user to register successfully', () => {
      cy.register({
        email: `john-${timestamp}@testcompany.com`,
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'John',
        lastName: 'Doe',
        accountName: 'Test Company',
      });
      
      // Should be on dashboard
      cy.url().should('include', '/dashboard');
      
      // Should show user info
      cy.contains('John').should('be.visible');
    });

    it('should handle duplicate email registration', () => {
      // First, register a user
      const email = `existing-${timestamp}-${Math.random()}@example.com`;
      cy.register({
        email,
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'Existing',
        lastName: 'User',
        accountName: 'Existing Company',
      });
      
      // Logout
      cy.get('[data-testid="user-menu"]').click();
      cy.get('[data-testid="logout-btn"]').click();
      
      // Try to register with same email using the UI (to test error handling)
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
      cy.get('[data-testid="plan-select-btn"]').first().click({ force: true });
      cy.url().should('include', '/register');
      
      cy.get('[data-testid="selected-plan"]', { timeout: 15000 }).should('be.visible');
      cy.get('input[name="firstName"]').clear({ force: true }).type('Another', { force: true });
      cy.get('input[name="lastName"]').clear({ force: true }).type('User', { force: true });
      cy.get('input[name="accountName"]').clear({ force: true }).type('Another Company', { force: true });
      cy.get('input[name="email"]').clear({ force: true }).type(email, { force: true });
      cy.get('input[name="password"]').clear({ force: true }).type('Qx7#mK9@pL2$nZ6%', { force: true });
      
      cy.get('button[type="submit"]').should('not.be.disabled', { timeout: 10000 });
      cy.get('button[type="submit"]').click({ force: true });
      
      // Should show error message (wait for it to appear)
      cy.contains('already been taken', { timeout: 10000 }).should('be.visible');
      cy.url().should('include', '/register');
    });
  });

  describe('User Login', () => {
    beforeEach(() => {
      // Create a test user with unique email
      const email = `test-login-${timestamp}-${Math.random()}@example.com`;
      cy.register({
        email,
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'Test',
        lastName: 'User',
        accountName: 'Test Company',
      });
      
      // Store email for use in tests
      cy.wrap(email).as('testEmail');
      
      // Logout to test login
      cy.get('[data-testid="user-menu"]').click();
      cy.get('[data-testid="logout-btn"]').click();
    });

    it('should allow existing user to login successfully', function() {
      cy.visit('/login');
      
      // Fill out login form
      cy.get('input[placeholder="Email address"]').type(this.testEmail);
      cy.get('input[placeholder="Password"]').type('Qx7#mK9@pL2$nZ6%');
      
      // Submit form
      cy.get('button[type="submit"]').click();
      
      // Should redirect to dashboard
      cy.url().should('include', '/dashboard');
      cy.contains('Welcome back, Test!').should('be.visible');
    });

    it('should show error for invalid credentials', function() {
      cy.visit('/login');
      
      // Fill out login form with wrong password
      cy.get('input[placeholder="Email address"]').type(this.testEmail);
      cy.get('input[placeholder="Password"]').type('wrongpassword');
      
      // Submit form
      cy.get('button[type="submit"]').click();
      
      // Should show error message
      cy.contains('Invalid email or password').should('be.visible');
      cy.url().should('include', '/login');
    });
  });

  describe('Protected Routes', () => {
    it('should redirect unauthenticated users to login', () => {
      cy.visit('/dashboard');
      cy.url().should('include', '/login');
      
      cy.visit('/dashboard/analytics');
      cy.url().should('include', '/login');
    });

    it('should allow authenticated users to access protected routes', () => {
      cy.register({
        email: `protected-${timestamp}-${Math.random()}@example.com`,
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'Protected',
        lastName: 'User',
        accountName: 'Protected Company',
      });
      
      // Should be able to access dashboard
      cy.visit('/dashboard');
      cy.url().should('include', '/dashboard');
      cy.contains('Welcome back, Protected!').should('be.visible');
    });
  });

  describe('Session Management', () => {
    it('should handle logout properly', () => {
      cy.register({
        email: `logout-${timestamp}-${Math.random()}@example.com`,
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'Logout',
        lastName: 'User',
        accountName: 'Logout Company',
      });
      
      // Logout
      cy.get('[data-testid="user-menu"]').click();
      cy.get('[data-testid="logout-btn"]').click();
      
      // Should redirect to login
      cy.url().should('include', '/login');
      
      // Should not be able to access protected routes
      cy.visit('/dashboard');
      cy.url().should('include', '/login');
    });
  });

  describe('API Direct Tests', () => {
    it('should register via API and access dashboard', () => {
      cy.request({
        method: 'POST',
        url: 'http://localhost:3000/api/v1/auth/register',
        headers: {
          'Content-Type': 'application/json'
        },
        body: {
          email: `api-${timestamp}-${Math.random()}@example.com`,
          password: 'Qx7#mK9@pL2$nZ6%',
          firstName: 'API',
          lastName: 'Test',
          accountName: 'API Test Company',
          planId: '01989991-0039-7f0f-ae0b-702330e26324',
          billingCycle: 'monthly'
        }
      }).then((response) => {
        expect([200, 201]).to.include(response.status);
        expect(response.body.success).to.be.true;
        expect(response.body.access_token).to.exist;
        
        // Set token and verify UI access
        cy.window().then((win) => {
          win.localStorage.setItem('accessToken', response.body.access_token);
        });
        
        cy.visit('/dashboard');
        cy.url().should('include', '/dashboard');
        cy.contains('API').should('be.visible');
      });
    });

    it('should login via API', () => {
      // First create user via API
      const email = `login-api-${timestamp}-${Math.random()}@example.com`;
      cy.request({
        method: 'POST',
        url: 'http://localhost:3000/api/v1/auth/register',
        body: {
          email,
          password: 'Qx7#mK9@pL2$nZ6%',
          firstName: 'Login',
          lastName: 'API',
          accountName: 'Login API Company',
          planId: '01989991-0039-7f0f-ae0b-702330e26324',
          billingCycle: 'monthly'
        }
      }).then(() => {
        // Now test login
        cy.request({
          method: 'POST',
          url: 'http://localhost:3000/api/v1/auth/login',
          body: {
            email,
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
        });
      });
    });
  });
});