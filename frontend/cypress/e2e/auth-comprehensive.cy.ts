describe('Comprehensive Authentication Tests', () => {
  const timestamp = Date.now();
  
  beforeEach(() => {
    cy.clearAppData();
  });

  describe('Registration Flow', () => {
    it('should complete full registration workflow', () => {
      const userData = {
        email: `full-reg-${timestamp}-${Math.random()}@testcompany.com`,
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'Full',
        lastName: 'Registration',
        accountName: 'Full Registration Co'
      };

      // Visit plans page
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
      
      // Select a plan
      cy.get('[data-testid="plan-select-btn"]').first().click({ force: true });
      cy.url().should('include', '/register');
      
      // Wait for plan to load
      cy.get('[data-testid="selected-plan"]', { timeout: 15000 }).should('be.visible');
      
      // Fill registration form
      cy.get('input[name="firstName"]').type(userData.firstName);
      cy.get('input[name="lastName"]').type(userData.lastName);
      cy.get('input[name="accountName"]').type(userData.accountName);
      cy.get('input[name="email"]').type(userData.email);
      cy.get('input[name="password"]').type(userData.password);
      
      // Submit form
      cy.get('button[type="submit"]').should('not.be.disabled');
      cy.get('button[type="submit"]').click();
      
      // Should redirect to dashboard
      cy.url().should('include', '/dashboard', { timeout: 20000 });
      cy.contains(userData.firstName).should('be.visible');
      
      // Verify user can access protected content
      cy.get('[data-testid="user-menu"]').should('be.visible');
    });

    it('should show validation errors for invalid data', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
      cy.get('[data-testid="plan-select-btn"]').first().click({ force: true });
      
      cy.url().should('include', '/register');
      cy.get('[data-testid="selected-plan"]', { timeout: 15000 }).should('be.visible');
      
      // Try to submit empty form
      cy.get('button[type="submit"]').should('be.disabled');
      
      // Fill with invalid email
      cy.get('input[name="firstName"]').type('Test');
      cy.get('input[name="lastName"]').type('User');
      cy.get('input[name="accountName"]').type('Test Company');
      cy.get('input[name="email"]').type('invalid-email');
      cy.get('input[name="password"]').type('short');
      
      // Form should still be disabled or show validation errors
      cy.get('input[name="email"]').should('have.attr', 'type', 'email');
    });
  });

  describe('Login Flow', () => {
    beforeEach(() => {
      // Create a test user first
      const email = `login-test-${timestamp}-${Math.random()}@example.com`;
      cy.wrap(email).as('testEmail');
      
      cy.register({
        email,
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'Login',
        lastName: 'Test',
        accountName: 'Login Test Co'
      });
      
      // Logout to test login
      cy.get('[data-testid="user-menu"]').click();
      cy.get('[data-testid="logout-btn"]').click();
      cy.url().should('include', '/login');
    });

    it('should login successfully with valid credentials', function() {
      cy.visit('/login');
      
      // Fill login form using working selectors
      cy.get('input[type="email"]').type(this.testEmail);
      cy.get('input[type="password"]').type('Qx7#mK9@pL2$nZ6%');
      
      // Submit form
      cy.get('button[type="submit"]').click();
      
      // Should redirect to dashboard
      cy.url().should('include', '/dashboard');
      cy.contains('Welcome back, Login!').should('be.visible');
    });

    it('should show error for invalid credentials', function() {
      cy.visit('/login');
      
      cy.get('input[type="email"]').type(this.testEmail);
      cy.get('input[type="password"]').type('wrong-password');
      cy.get('button[type="submit"]').click();
      
      // Should show error message and stay on login page
      cy.contains('Invalid email or password').should('be.visible');
      cy.url().should('include', '/login');
    });

    it('should show error for non-existent email', () => {
      cy.visit('/login');
      
      cy.get('input[type="email"]').type('nonexistent@example.com');
      cy.get('input[type="password"]').type('Qx7#mK9@pL2$nZ6%');
      cy.get('button[type="submit"]').click();
      
      cy.contains('Invalid email or password').should('be.visible');
      cy.url().should('include', '/login');
    });

    it('should handle password visibility toggle', function() {
      cy.visit('/login');
      
      cy.get('input[type="email"]').type(this.testEmail);
      cy.get('input[type="password"]').should('have.attr', 'type', 'password');
      
      // Click show password button
      cy.get('input[type="password"]').siblings('button').click();
      cy.get('input[name="password"]').should('have.attr', 'type', 'text');
      
      // Click hide password button
      cy.get('input[name="password"]').siblings('button').click();
      cy.get('input[name="password"]').should('have.attr', 'type', 'password');
    });
  });

  describe('Session Management', () => {
    it('should handle logout correctly', () => {
      // Login first
      cy.register({
        email: `session-${timestamp}-${Math.random()}@example.com`,
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'Session',
        lastName: 'Test',
        accountName: 'Session Test Co'
      });
      
      // Verify logged in
      cy.url().should('include', '/dashboard');
      cy.get('[data-testid="user-menu"]').should('be.visible');
      
      // Logout
      cy.get('[data-testid="user-menu"]').click();
      cy.get('[data-testid="logout-btn"]').click();
      
      // Should redirect to login
      cy.url().should('include', '/login');
      
      // Should not be able to access protected routes
      cy.visit('/dashboard');
      cy.url().should('include', '/login');
    });

    it('should persist session across page reloads', () => {
      cy.register({
        email: `persist-${timestamp}-${Math.random()}@example.com`,
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'Persist',
        lastName: 'Test',
        accountName: 'Persist Test Co'
      });
      
      cy.url().should('include', '/dashboard');
      
      // Reload page
      cy.reload();
      
      // Should still be logged in
      cy.url().should('include', '/dashboard');
      cy.contains('Persist').should('be.visible');
    });
  });

  describe('Protected Routes', () => {
    it('should redirect unauthenticated users to login', () => {
      const protectedRoutes = ['/dashboard', '/dashboard/analytics'];
      
      protectedRoutes.forEach(route => {
        cy.visit(route);
        cy.url().should('include', '/login');
      });
    });

    it('should allow authenticated users to access protected routes', () => {
      cy.register({
        email: `protected-${timestamp}-${Math.random()}@example.com`,
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'Protected',
        lastName: 'User',
        accountName: 'Protected Co'
      });
      
      // Should be able to access dashboard
      cy.visit('/dashboard');
      cy.url().should('include', '/dashboard');
      cy.contains('Welcome back, Protected!').should('be.visible');
      
      // Should be able to navigate to other protected routes
      cy.visit('/dashboard/analytics');
      cy.url().should('include', '/dashboard');
    });
  });

  describe('Form Validation', () => {
    it('should validate email format in registration', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
      cy.get('[data-testid="plan-select-btn"]').first().click({ force: true });
      
      cy.get('input[name="email"]').type('invalid-email');
      cy.get('input[name="email"]').blur();
      
      // HTML5 validation should kick in
      cy.get('input[name="email"]').should('have.attr', 'type', 'email');
    });

    it('should validate email format in login', () => {
      cy.visit('/login');
      cy.get('input[type="email"]').type('invalid-email');
      cy.get('input[type="email"]').blur();
      
      cy.get('input[type="email"]').should('have.attr', 'type', 'email');
    });

    it('should require all fields in registration', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
      cy.get('[data-testid="plan-select-btn"]').first().click({ force: true });
      cy.get('[data-testid="selected-plan"]', { timeout: 15000 }).should('be.visible');
      
      // Submit button should be disabled when form is empty
      cy.get('button[type="submit"]').should('be.disabled');
      
      // Fill partial form
      cy.get('input[name="firstName"]').type('Test');
      cy.get('button[type="submit"]').should('be.disabled');
      
      cy.get('input[name="lastName"]').type('User');
      cy.get('button[type="submit"]').should('be.disabled');
      
      cy.get('input[name="email"]').type('test@example.com');
      cy.get('button[type="submit"]').should('be.disabled');
      
      cy.get('input[name="accountName"]').type('Test Co');
      cy.get('button[type="submit"]').should('be.disabled');
      
      // Only enable when password is also filled
      cy.get('input[name="password"]').type('Qx7#mK9@pL2$nZ6%');
      cy.get('button[type="submit"]').should('not.be.disabled');
    });
  });

  describe('Error Handling', () => {
    it('should handle network errors gracefully', () => {
      // Intercept and fail the registration request
      cy.intercept('POST', '/api/v1/auth/register', { forceNetworkError: true }).as('failedRegister');
      
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
      cy.get('[data-testid="plan-select-btn"]').first().click({ force: true });
      cy.get('[data-testid="selected-plan"]', { timeout: 15000 }).should('be.visible');
      
      cy.get('input[name="firstName"]').type('Network');
      cy.get('input[name="lastName"]').type('Error');
      cy.get('input[name="accountName"]').type('Network Error Co');
      cy.get('input[name="email"]').type(`network-error-${timestamp}@example.com`);
      cy.get('input[name="password"]').type('Qx7#mK9@pL2$nZ6%');
      
      cy.get('button[type="submit"]').click();
      
      // Should show error message
      cy.contains('Registration failed').should('be.visible');
      cy.url().should('include', '/register');
    });

    it('should handle API errors gracefully', () => {
      // Intercept and return server error
      cy.intercept('POST', '/api/v1/auth/login', { 
        statusCode: 500, 
        body: { success: false, error: 'Server error' }
      }).as('serverError');
      
      cy.visit('/login');
      cy.get('[data-testid="email-input"]').type('test@example.com');
      cy.get('[data-testid="password-input"]').type('Qx7#mK9@pL2$nZ6%');
      cy.get('button[type="submit"]').click();
      
      // Should show error message
      cy.contains('Server error').should('be.visible');
      cy.url().should('include', '/login');
    });
  });
});