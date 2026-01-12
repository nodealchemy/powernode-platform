describe('Login Selector Test', () => {
  describe('Login Page Selectors', () => {
    beforeEach(() => {
      cy.visit('/login');
    });

    it('should have all required data-testid attributes on login page', () => {
      // Test data-testid selectors are present
      cy.get('[data-testid="email-input"]').should('be.visible');
      cy.get('[data-testid="password-input"]').should('be.visible');
      cy.get('[data-testid="login-submit-btn"]').should('be.visible');
      cy.get('[data-testid="remember-me-checkbox"]').should('exist');
      cy.get('[data-testid="forgot-password-link"]').should('be.visible');
    });

    it('should allow typing in login form fields', () => {
      cy.get('[data-testid="email-input"]').type('test@example.com').should('have.value', 'test@example.com');
      cy.get('[data-testid="password-input"]').type('password123').should('have.value', 'password123');
    });

    it('should show error for invalid credentials', () => {
      cy.get('[data-testid="email-input"]').type('invalid@example.com');
      cy.get('[data-testid="password-input"]').type('wrongpassword');
      cy.get('[data-testid="login-submit-btn"]').click();
      // Should stay on login page with error (not redirect to dashboard)
      cy.url({ timeout: 5000 }).should('include', '/login');
    });
  });

  describe('Plan Selection Page Selectors', () => {
    beforeEach(() => {
      cy.visit('/plans');
    });

    it('should have plan cards with data-testid', () => {
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('have.length.at.least', 1);
    });

    it('should have billing toggle buttons', () => {
      cy.get('[data-testid="billing-monthly"]').should('be.visible');
      cy.get('[data-testid="billing-yearly"]').should('be.visible');
    });

    it('should show continue button when plan is selected', () => {
      cy.get('[data-testid="plan-card"]').first().click();
      cy.get('[data-testid="continue-to-registration"]').should('be.visible');
    });
  });

  describe('Registration Page Selectors', () => {
    beforeEach(() => {
      // Navigate through plan selection to reach registration
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).first().click();
      cy.get('[data-testid="continue-to-registration"]').click();
      cy.url().should('include', '/register');
    });

    it('should have all required data-testid attributes on registration page', () => {
      cy.get('[data-testid="selected-plan"]', { timeout: 10000 }).should('be.visible');
      cy.get('[data-testid="account-name-input"]').should('be.visible');
      cy.get('[data-testid="name-input"]').should('be.visible');
      cy.get('[data-testid="register-email-input"]').should('be.visible');
      cy.get('[data-testid="register-password-input"]').should('be.visible');
      cy.get('[data-testid="register-submit-btn"]').should('be.visible');
    });

    it('should allow typing in registration form fields', () => {
      cy.get('[data-testid="account-name-input"]').type('Test Company');
      cy.get('[data-testid="name-input"]').type('Test User');
      cy.get('[data-testid="register-email-input"]').type('test@example.com');
      cy.get('[data-testid="register-password-input"]').type('SecurePassword123!');
      // Verify values
      cy.get('[data-testid="account-name-input"]').should('have.value', 'Test Company');
      cy.get('[data-testid="name-input"]').should('have.value', 'Test User');
    });
  });
});