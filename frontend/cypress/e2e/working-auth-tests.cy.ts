describe('Working Authentication Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
  });

  describe('User Registration', () => {
    it('should allow new user to register successfully', () => {
      cy.register({
        email: 'john@testcompany.com',
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
      cy.register({
        email: 'existing@example.com',
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
      cy.get('input[name="email"]').clear({ force: true }).type('existing@example.com', { force: true });
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
      // Create a test user
      cy.register({
        email: 'test@example.com',
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'Test',
        lastName: 'User',
        accountName: 'Test Company',
      });
      
      // Logout to test login
      cy.get('[data-testid="user-menu"]').click();
      cy.get('[data-testid="logout-btn"]').click();
    });

    it('should allow existing user to login successfully', () => {
      cy.visit('/login');
      
      // Fill out login form
      cy.get('input[placeholder="Email address"]').type('test@example.com');
      cy.get('input[placeholder="Password"]').type('Qx7#mK9@pL2$nZ6%');
      
      // Submit form
      cy.get('button[type="submit"]').click();
      
      // Should redirect to dashboard
      cy.url().should('include', '/dashboard');
      cy.contains('Welcome back, Test!').should('be.visible');
    });

    it('should show error for invalid credentials', () => {
      cy.visit('/login');
      
      // Fill out login form with wrong password
      cy.get('input[placeholder="Email address"]').type('test@example.com');
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
        email: 'protected@example.com',
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
        email: 'logout@example.com',
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
});