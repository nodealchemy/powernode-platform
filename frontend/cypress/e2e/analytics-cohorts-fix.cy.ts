describe('Analytics Dashboard - Cohorts Tab Fix', () => {
  beforeEach(() => {
    cy.clearAppData();
  });

  it('should handle Cohorts tab without errors', () => {
    // Create and register a test user
    const timestamp = Date.now();
    const userData = {
      email: `cohort-test-${timestamp}@example.com`,
      password: 'TestPass123!@#',
      firstName: 'Cohort',
      lastName: 'Test',
      accountName: 'Cohort Test Co'
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
    
    // Navigate to Analytics page
    cy.visit('/dashboard/analytics');
    cy.url().should('include', '/analytics');
    
    // Wait for page to load
    cy.get('body').should('contain.text', 'Analytics');
    
    // Find and click the Cohorts tab
    cy.get('button').contains('Cohorts').should('exist').click();
    
    // Verify no errors occur
    cy.get('body').should('not.contain.text', 'TypeError');
    cy.get('body').should('not.contain.text', 'Cannot read');
    cy.get('body').should('not.contain.text', 'undefined');
    
    // Check that either data or empty state is shown
    cy.get('body').then($body => {
      // Check for either cohort chart or empty state message
      const hasChart = $body.find('.chart-container').length > 0;
      const hasEmptyState = $body.text().includes('No cohort data available') || 
                            $body.text().includes('Data will appear');
      
      expect(hasChart || hasEmptyState, 'Should show either chart or empty state').to.be.true;
    });
  });

  it('should display proper empty state when no cohort data', () => {
    // Create and register a test user
    const timestamp = Date.now();
    const userData = {
      email: `cohort-empty-${timestamp}@example.com`,
      password: 'TestPass123!@#',
      firstName: 'Empty',
      lastName: 'Test',
      accountName: 'Empty Test Co'
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
    
    cy.url({ timeout: 20000 }).should('include', '/dashboard');
    
    // Navigate to Analytics -> Cohorts
    cy.visit('/dashboard/analytics');
    cy.get('button').contains('Cohorts').click();
    
    // Should show either data or a friendly empty state
    cy.get('.chart-container').should('exist');
    
    // If no data, should show helpful message
    cy.get('body').then($body => {
      if ($body.text().includes('No cohort data available')) {
        cy.contains('No cohort data available').should('be.visible');
        // Should also have helpful context
        cy.get('body').should('satisfy', ($el) => {
          const text = $el.text();
          return text.includes('will appear') || 
                 text.includes('once') || 
                 text.includes('customer');
        });
      }
    });
  });

  it('should not break when switching between analytics tabs', () => {
    // Create test user
    const timestamp = Date.now();
    const userData = {
      email: `tab-switch-${timestamp}@example.com`,
      password: 'TestPass123!@#',
      firstName: 'TabSwitch',
      lastName: 'Test',
      accountName: 'Tab Switch Co'
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
    
    cy.url({ timeout: 20000 }).should('include', '/dashboard');
    
    // Navigate to Analytics
    cy.visit('/dashboard/analytics');
    
    // Test switching between all tabs
    const tabs = ['Revenue', 'Growth', 'Churn', 'Customers', 'Cohorts'];
    
    tabs.forEach(tab => {
      cy.get('button').contains(tab).click();
      
      // Should not show any errors
      cy.get('body').should('not.contain.text', 'TypeError');
      cy.get('body').should('not.contain.text', 'Cannot read');
      
      // Wait a bit for content to load
      cy.wait(500);
    });
    
    // Go back to Cohorts tab one more time
    cy.get('button').contains('Cohorts').click();
    cy.get('.chart-container').should('exist');
  });
});