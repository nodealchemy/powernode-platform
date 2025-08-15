describe('Visual Regression Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
  });

  describe('Public Pages', () => {
    it('should match login page layout', () => {
      cy.visit('/login');
      
      // Wait for page to fully load
      cy.get('input[type="email"]').should('be.visible');
      cy.get('input[type="password"]').should('be.visible');
      cy.get('button[type="submit"]').should('be.visible');
      
      // Take screenshot for visual comparison
      cy.screenshot('login-page', {
        capture: 'viewport',
        clip: { x: 0, y: 0, width: 1280, height: 720 }
      });
      
      // Test responsive design - tablet
      cy.viewport(768, 1024);
      cy.screenshot('login-page-tablet', {
        capture: 'viewport'
      });
      
      // Test responsive design - mobile
      cy.viewport(375, 667);
      cy.screenshot('login-page-mobile', {
        capture: 'viewport'
      });
    });

    it('should match plan selection page layout', () => {
      cy.visit('/plans');
      
      // Wait for plans to load
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
      
      // Take full page screenshot
      cy.screenshot('plans-page-desktop', {
        capture: 'fullPage'
      });
      
      // Test different viewports
      cy.viewport(768, 1024);
      cy.screenshot('plans-page-tablet', {
        capture: 'fullPage'
      });
      
      cy.viewport(375, 667);
      cy.screenshot('plans-page-mobile', {
        capture: 'fullPage'
      });
      
      // Test plan selection state
      cy.viewport(1280, 720);
      cy.get('[data-testid="plan-card"]').first().click();
      cy.get('[data-testid="plan-select-btn"]', { timeout: 10000 }).should('be.visible');
      
      cy.screenshot('plans-page-plan-selected', {
        capture: 'fullPage'
      });
    });

    it('should match registration page layout', () => {
      // Navigate through plan selection to registration
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
      cy.get('[data-testid="plan-card"]').first().click();
      cy.get('[data-testid="plan-select-btn"]', { timeout: 10000 }).should('be.visible');
      cy.get('[data-testid="plan-select-btn"]').click();
      
      // Wait for registration page to load
      cy.url().should('include', '/register');
      cy.get('[data-testid="selected-plan"]', { timeout: 15000 }).should('be.visible');
      
      // Screenshot empty form
      cy.screenshot('registration-page-empty', {
        capture: 'fullPage'
      });
      
      // Fill form partially and screenshot
      cy.get('input[name="firstName"]').type('Visual');
      cy.get('input[name="lastName"]').type('Test');
      cy.get('input[name="accountName"]').type('Visual Test Co');
      cy.get('input[name="email"]').type('visual.test@example.com');
      
      cy.screenshot('registration-page-partial', {
        capture: 'fullPage'
      });
      
      // Complete form
      cy.get('input[name="password"]').type('Qx7#mK9@pL2$nZ6%');
      
      cy.screenshot('registration-page-complete', {
        capture: 'fullPage'
      });
    });
  });

  describe('Authenticated Pages', () => {
    beforeEach(() => {
      // Register and login a test user
      const timestamp = Date.now();
      cy.register({
        email: `visual-test-${timestamp}@example.com`,
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'Visual',
        lastName: 'Tester',
        accountName: 'Visual Test Co'
      });
    });

    it('should match dashboard layout', () => {
      cy.url().should('include', '/dashboard');
      
      // Wait for dashboard to fully load
      cy.get('[data-testid="user-menu"]').should('be.visible');
      cy.contains('Welcome back, Visual!').should('be.visible');
      
      // Screenshot main dashboard
      cy.screenshot('dashboard-main', {
        capture: 'fullPage'
      });
      
      // Test responsive layouts
      cy.viewport(768, 1024);
      cy.screenshot('dashboard-main-tablet', {
        capture: 'fullPage'
      });
      
      cy.viewport(375, 667);
      cy.screenshot('dashboard-main-mobile', {
        capture: 'fullPage'
      });
      
      // Test user menu dropdown
      cy.viewport(1280, 720);
      cy.get('[data-testid="user-menu"]').click();
      cy.screenshot('dashboard-user-menu-open', {
        capture: 'viewport'
      });
    });
  });

  describe('Component States', () => {
    it('should capture form validation states', () => {
      cy.visit('/login');
      
      // Empty form state
      cy.screenshot('form-state-empty');
      
      // Invalid email state
      cy.get('input[type="email"]').type('invalid-email').blur();
      cy.get('input[type="password"]').type('short');
      cy.screenshot('form-state-invalid');
      
      // Valid form state
      cy.get('input[type="email"]').clear().type('valid@example.com');
      cy.get('input[type="password"]').clear().type('ValidPassword123!');
      cy.screenshot('form-state-valid');
    });

    it('should capture loading states', () => {
      // Intercept plans API with delay to capture loading state
      cy.intercept('GET', '/api/v1/public/plans', (req) => {
        req.reply((res) => {
          return new Promise(resolve => {
            setTimeout(() => resolve(res), 2000);
          });
        });
      }).as('slowPlans');
      
      cy.visit('/plans');
      
      // Capture loading state
      cy.screenshot('plans-loading-state');
      
      // Wait for plans to load and capture loaded state
      cy.wait('@slowPlans');
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
      cy.screenshot('plans-loaded-state');
    });

    it('should capture error states', () => {
      // Test login error state
      cy.visit('/login');
      cy.get('input[type="email"]').type('test@example.com');
      cy.get('input[type="password"]').type('wrongpassword');
      cy.get('button[type="submit"]').click();
      
      // Wait for error message
      cy.wait(2000);
      cy.screenshot('login-error-state');
    });

    it('should capture hover and focus states', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
      
      // Hover state
      cy.get('[data-testid="plan-card"]').first().trigger('mouseover');
      cy.screenshot('plan-card-hover');
      
      // Focus state for form elements
      cy.visit('/login');
      cy.get('input[type="email"]').focus();
      cy.screenshot('input-focus-state');
      
      // Button focus state
      cy.get('button[type="submit"]').focus();
      cy.screenshot('button-focus-state');
    });
  });

  describe('Theme Variations', () => {
    beforeEach(() => {
      // Register and login to access theme switcher
      const timestamp = Date.now();
      cy.register({
        email: `theme-test-${timestamp}@example.com`,
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'Theme',
        lastName: 'Tester',
        accountName: 'Theme Test Co'
      });
    });

    it('should capture light and dark theme variations', () => {
      // Capture light theme (default)
      cy.screenshot('dashboard-light-theme', {
        capture: 'fullPage'
      });
      
      // Check if dark theme toggle exists and switch to dark mode
      cy.get('body').then($body => {
        if ($body.find('[data-testid="theme-toggle"]').length > 0) {
          cy.get('[data-testid="theme-toggle"]').click();
          cy.wait(500); // Wait for theme transition
          
          // Capture dark theme
          cy.screenshot('dashboard-dark-theme', {
            capture: 'fullPage'
          });
          
          // Test dark theme on different pages
          cy.visit('/login');
          cy.screenshot('login-dark-theme');
          
          cy.visit('/plans');
          cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
          cy.screenshot('plans-dark-theme', {
            capture: 'fullPage'
          });
        } else {
          cy.log('Theme toggle not found - single theme mode');
        }
      });
    });
  });

  describe('Cross-browser Visual Consistency', () => {
    it('should maintain layout consistency across viewport sizes', () => {
      const viewports = [
        { width: 1920, height: 1080, name: 'desktop-xl' },
        { width: 1280, height: 720, name: 'desktop' },
        { width: 1024, height: 768, name: 'tablet-landscape' },
        { width: 768, height: 1024, name: 'tablet-portrait' },
        { width: 375, height: 667, name: 'mobile' },
        { width: 320, height: 568, name: 'mobile-small' }
      ];
      
      viewports.forEach(viewport => {
        cy.viewport(viewport.width, viewport.height);
        
        // Test login page across viewports
        cy.visit('/login');
        cy.get('input[type="email"]').should('be.visible');
        cy.screenshot(`login-${viewport.name}`);
        
        // Test plans page across viewports
        cy.visit('/plans');
        cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
        cy.screenshot(`plans-${viewport.name}`, {
          capture: 'fullPage'
        });
      });
    });
  });
});