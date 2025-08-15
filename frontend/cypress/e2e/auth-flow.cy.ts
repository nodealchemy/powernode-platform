describe('Authentication Flow', () => {
  beforeEach(() => {
    cy.clearAppData();
  });

  describe('User Registration', () => {
    it('should allow new user to register successfully', () => {
      cy.visit('/register');
      
      // Fill out registration form
      cy.get('input[name="firstName"]').type('John');
      cy.get('input[name="lastName"]').type('Doe');
      cy.get('input[name="accountName"]').type('Test Company');
      cy.get('input[name="email"]').type('john@testcompany.com');
      cy.get('input[name="password"]').type('password123');
      
      // Submit form
      cy.get('button[type="submit"]').click();
      
      // Should redirect to dashboard
      cy.url().should('include', '/dashboard');
      
      // Should show welcome message
      cy.contains('Welcome back, John!').should('be.visible');
      
      // Should show getting started checklist
      cy.contains('Getting Started').should('be.visible');
      cy.contains('Account created successfully').should('be.visible');
    });

    it('should show validation errors for invalid registration data', () => {
      cy.visit('/register');
      
      // Try to submit empty form
      cy.get('button[type="submit"]').click();
      
      // Should show HTML5 validation errors
      cy.get('input[name="firstName"]:invalid').should('exist');
      cy.get('input[name="lastName"]:invalid').should('exist');
      cy.get('input[name="email"]:invalid').should('exist');
      cy.get('input[name="password"]:invalid').should('exist');
    });

    it('should handle duplicate email registration', () => {
      // First, register a user
      cy.register({
        email: 'existing@example.com',
        password: 'password123',
        firstName: 'Existing',
        lastName: 'User',
        accountName: 'Existing Company',
      });
      
      // Logout
      cy.get('[data-testid="user-menu"]').click();
      cy.contains('Sign out').click();
      
      // Try to register with same email
      cy.visit('/register');
      cy.get('input[name="firstName"]').type('Another');
      cy.get('input[name="lastName"]').type('User');
      cy.get('input[name="accountName"]').type('Another Company');
      cy.get('input[name="email"]').type('existing@example.com');
      cy.get('input[name="password"]').type('password123');
      cy.get('button[type="submit"]').click();
      
      // Should show error message
      cy.contains('Email has already been taken').should('be.visible');
      cy.url().should('include', '/register');
    });
  });

  describe('User Login', () => {
    beforeEach(() => {
      // Create a test user
      cy.register({
        email: 'test@example.com',
        password: 'password123',
        firstName: 'Test',
        lastName: 'User',
        accountName: 'Test Company',
      });
      
      // Logout to test login
      cy.get('[data-testid="user-menu"]').click();
      cy.contains('Sign out').click();
    });

    it('should allow existing user to login successfully', () => {
      cy.visit('/login');
      
      // Fill out login form
      cy.get('input[placeholder="Email address"]').type('test@example.com');
      cy.get('input[placeholder="Password"]').type('password123');
      
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

    it('should show loading state during login', () => {
      cy.visit('/login');
      
      // Intercept login API call to add delay
      cy.intercept('POST', '/api/v1/auth/login', (req) => {
        req.reply((res) => {
          // Add a delay to see loading state
          setTimeout(() => {
            res.send({ fixture: 'login-response.json' });
          }, 1000);
        });
      }).as('loginRequest');
      
      cy.get('input[placeholder="Email address"]').type('test@example.com');
      cy.get('input[placeholder="Password"]').type('password123');
      cy.get('button[type="submit"]').click();
      
      // Should show loading state
      cy.contains('Signing in...').should('be.visible');
      cy.get('button[type="submit"]').should('be.disabled');
      
      cy.wait('@loginRequest');
    });
  });

  describe('Password Reset', () => {
    beforeEach(() => {
      cy.register({
        email: 'reset@example.com',
        password: 'oldpassword',
        firstName: 'Reset',
        lastName: 'User',
        accountName: 'Reset Company',
      });
      
      // Logout
      cy.get('[data-testid="user-menu"]').click();
      cy.contains('Sign out').click();
    });

    it('should allow user to request password reset', () => {
      cy.visit('/login');
      
      // Click forgot password link
      cy.contains('Forgot your password?').click();
      cy.url().should('include', '/forgot-password');
      
      // Enter email
      cy.get('input[name="email"]').type('reset@example.com');
      cy.get('button[type="submit"]').click();
      
      // Should show success message
      cy.contains('We\'ve sent a password reset link').should('be.visible');
    });

    it('should show success message even for non-existent email', () => {
      cy.visit('/forgot-password');
      
      // Enter non-existent email
      cy.get('input[name="email"]').type('nonexistent@example.com');
      cy.get('button[type="submit"]').click();
      
      // Should show success message (for security)
      cy.contains('We\'ve sent a password reset link').should('be.visible');
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
        password: 'password123',
        firstName: 'Protected',
        lastName: 'User',
        accountName: 'Protected Company',
      });
      
      // Should be able to access dashboard
      cy.visit('/dashboard');
      cy.url().should('include', '/dashboard');
      cy.contains('Welcome back, Protected!').should('be.visible');
      
      // Should be able to navigate to other protected routes
      cy.get('[data-testid="nav-analytics"]').click();
      cy.url().should('include', '/dashboard/analytics');
    });

    it('should redirect authenticated users away from public routes', () => {
      cy.register({
        email: 'redirect@example.com',
        password: 'password123',
        firstName: 'Redirect',
        lastName: 'User',
        accountName: 'Redirect Company',
      });
      
      // Try to access login page while authenticated
      cy.visit('/login');
      cy.url().should('include', '/dashboard');
      
      // Try to access register page while authenticated
      cy.visit('/register');
      cy.url().should('include', '/dashboard');
    });
  });

  describe('Session Management', () => {
    it('should maintain session across page refreshes', () => {
      cy.register({
        email: 'session@example.com',
        password: 'password123',
        firstName: 'Session',
        lastName: 'User',
        accountName: 'Session Company',
      });
      
      // Refresh the page
      cy.reload();
      
      // Should still be authenticated
      cy.url().should('include', '/dashboard');
      cy.contains('Welcome back, Session!').should('be.visible');
    });

    it('should handle logout properly', () => {
      cy.register({
        email: 'logout@example.com',
        password: 'password123',
        firstName: 'Logout',
        lastName: 'User',
        accountName: 'Logout Company',
      });
      
      // Logout
      cy.get('[data-testid="user-menu"]').click();
      cy.contains('Sign out').click();
      
      // Should redirect to login
      cy.url().should('include', '/login');
      
      // Should not be able to access protected routes
      cy.visit('/dashboard');
      cy.url().should('include', '/login');
    });

    it('should handle token expiration gracefully', () => {
      cy.register({
        email: 'expired@example.com',
        password: 'password123',
        firstName: 'Expired',
        lastName: 'User',
        accountName: 'Expired Company',
      });
      
      // Mock expired token response
      cy.intercept('GET', '/api/v1/auth/me', {
        statusCode: 401,
        body: { error: 'Token expired' },
      }).as('expiredToken');
      
      // Try to make an authenticated request
      cy.visit('/dashboard/analytics');
      
      cy.wait('@expiredToken');
      
      // Should redirect to login
      cy.url().should('include', '/login');
    });
  });
});