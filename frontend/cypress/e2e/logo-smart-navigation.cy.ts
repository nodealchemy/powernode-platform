describe('Logo Smart Navigation', () => {
  beforeEach(() => {
    cy.clearAppData();
  });

  it('should navigate to welcome page when not authenticated', () => {
    // Visit login page (not authenticated)
    cy.visit('/login');
    
    // Click the logo
    cy.get('a[href="/welcome"]').first().should('exist');
    cy.get('.bg-theme-interactive-primary').first().parent().click();
    
    // Should navigate to welcome page
    cy.url().should('include', '/welcome');
    
    // Verify we're on the welcome page
    cy.get('body').should('satisfy', ($body) => {
      const text = $body.text();
      return text.includes('Welcome') || 
             text.includes('Get Started') || 
             text.includes('Powernode');
    });
  });

  it('should navigate to dashboard when authenticated', () => {
    // Create and register a test user
    const timestamp = Date.now();
    const userData = {
      email: `logo-test-${timestamp}@example.com`,
      password: 'TestPass123!@#',
      firstName: 'Logo',
      lastName: 'Test',
      accountName: 'Logo Test Co'
    };
    
    // Register through the flow
    cy.visit('/plans');
    cy.get('[data-testid="plan-card"]', { timeout: 15000 }).first().click();
    cy.get('[data-testid="plan-select-btn"]', { timeout: 10000 }).click();
    
    // Fill registration form
    cy.url().should('include', '/register');
    cy.get('input[name="accountName"]').type(userData.accountName);
    cy.get('input[name="firstName"]').type(userData.firstName);
    cy.get('input[name="lastName"]').type(userData.lastName);
    cy.get('input[name="email"]').type(userData.email);
    cy.get('input[name="password"]').type(userData.password);
    cy.get('button[type="submit"]').click();
    
    // Wait for dashboard
    cy.url({ timeout: 20000 }).should('include', '/dashboard');
    
    // Now the logo should navigate to dashboard (since we're authenticated)
    cy.get('a[title="Go to Dashboard"]', { timeout: 10000 }).should('exist');
    
    // Navigate to a different page first
    cy.visit('/dashboard/account');
    cy.url().should('include', '/dashboard/account');
    
    // Click the logo
    cy.get('a[title="Go to Dashboard"]').first().click();
    
    // Should navigate back to main dashboard
    cy.url().should('match', /\/dashboard\/?$/);
  });

  it('should have correct hover effects on logo', () => {
    // Visit login page
    cy.visit('/login');
    
    // Check that logo exists and has hover class
    cy.get('.bg-theme-interactive-primary').first()
      .parent()
      .should('have.class', 'group');
    
    // Trigger hover
    cy.get('.bg-theme-interactive-primary').first()
      .parent()
      .trigger('mouseover');
    
    // Check that hover classes are defined
    cy.get('.bg-theme-interactive-primary').first()
      .should('have.class', 'group-hover:bg-theme-interactive-secondary');
  });

  it('should show correct title attribute based on auth status', () => {
    // Not authenticated - should show "Go to Welcome Page" on login page
    cy.visit('/login');
    cy.get('a[href="/welcome"]').should('exist');
    
    // Create and login user
    const timestamp = Date.now();
    const userData = {
      email: `title-test-${timestamp}@example.com`,
      password: 'TestPass123!@#',
      firstName: 'Title',
      lastName: 'Test',
      accountName: 'Title Test Co'
    };
    
    // Register
    cy.visit('/plans');
    cy.get('[data-testid="plan-card"]', { timeout: 15000 }).first().click();
    cy.get('[data-testid="plan-select-btn"]', { timeout: 10000 }).click();
    
    cy.url().should('include', '/register');
    cy.get('input[name="accountName"]').type(userData.accountName);
    cy.get('input[name="firstName"]').type(userData.firstName);
    cy.get('input[name="lastName"]').type(userData.lastName);
    cy.get('input[name="email"]').type(userData.email);
    cy.get('input[name="password"]').type(userData.password);
    cy.get('button[type="submit"]').click();
    
    // Wait for dashboard
    cy.url({ timeout: 20000 }).should('include', '/dashboard');
    
    // Authenticated - should show "Go to Dashboard"
    cy.get('a[title="Go to Dashboard"]').should('exist');
  });
});