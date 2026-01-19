describe('Plan Selection Workflow Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.setupApiIntercepts();
  });

  describe('Plans Page', () => {
    it('should display available plans', () => {
      cy.visit('/plans');
      
      // Should show plan cards
      cy.get('[data-testid="plan-card"]', { timeout: 5000 }).should('exist');
      cy.get('[data-testid="plan-card"]').should('have.length.at.least', 1);
      
      // Each plan card should have essential information
      cy.get('[data-testid="plan-card"]').first().within(() => {
        // Should show plan name
        cy.get('h3, h2, .plan-name').should('exist');
        
        // Should show price or "Free"
        cy.contains(/\$|\d+|Free/i).should('exist');
      });
      
      // Plan cards should be clickable for selection
      cy.get('[data-testid="plan-card"]').should('have.length.at.least', 1);
    });

    it('should handle plan selection', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 5000 }).should('exist');

      // Click on first plan card to select it
      cy.get('[data-testid="plan-card"]').first().should('be.visible').click();

      // Should show the continue button after selection
      cy.get('[data-testid="continue-to-registration"]', { timeout: 5000 }).should('be.visible');

      // Click continue to proceed to registration
      cy.get('[data-testid="continue-to-registration"]').should('be.visible').click();

      // Should navigate to registration with plan selected
      cy.url().should('include', '/register');
      cy.url().should('include', 'plan=');

      // Should show selected plan information
      cy.get('[data-testid="selected-plan"]', { timeout: 5000 }).should('be.visible');
    });

    it('should show plan details and features', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 5000 }).should('exist');
      
      // Check each plan card for details
      cy.get('[data-testid="plan-card"]').each(($card) => {
        cy.wrap($card).within(() => {
          // Should show some kind of feature list or description
          cy.get('ul, .features, .description, p').should('exist');
        });
      });
    });

    it('should handle different billing cycles if available', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 5000 }).should('exist');
      
      // Check for billing cycle toggles
      cy.get('body').then($body => {
        if ($body.find('[data-testid="billing-toggle"]').length > 0) {
          cy.get('[data-testid="billing-toggle"]').should('be.visible');
          
          // Test switching billing cycles
          cy.get('[data-testid="billing-toggle"]').click();
          
          // Plans should still be visible
          cy.get('[data-testid="plan-card"]').should('exist');
        } else {
          cy.log('No billing toggle found - single billing cycle');
        }
      });
    });
  });

  describe('Plan Selection Flow', () => {
    it('should complete full plan selection to registration flow', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 5000 }).should('exist');

      // Get plan details before selecting
      let _planName: string;
      cy.get('[data-testid="plan-card"]').first().within(() => {
        cy.get('h3, h2, .plan-name').first().invoke('text').then(text => {
          _planName = text.trim();
        });
      });

      // Select plan by clicking the card
      cy.get('[data-testid="plan-card"]').first().should('be.visible').click();

      // Wait for continue button to appear and click it
      cy.get('[data-testid="continue-to-registration"]', { timeout: 5000 }).should('be.visible');
      cy.get('[data-testid="continue-to-registration"]').should('be.visible').click();

      // Verify plan selection carried over to registration
      cy.url().should('include', '/register');
      cy.get('[data-testid="selected-plan"]', { timeout: 5000 }).should('be.visible');

      // Complete registration using data-testid selectors
      const timestamp = Date.now();
      cy.get('[data-testid="name-input"]').type('Plan Tester');
      cy.get('[data-testid="account-name-input"]').type('Plan Test Co');
      cy.get('[data-testid="register-email-input"]').type(`plan-test-${timestamp}@example.com`);
      cy.get('[data-testid="register-password-input"]').type('Qx7#mK9@pL2$nZ6%');

      cy.get('[data-testid="register-submit-btn"]').should('not.be.disabled');
      cy.get('[data-testid="register-submit-btn"]').click();

      // Should complete registration (redirects to /app or /dashboard)
      cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
    });

    it('should redirect to plan selection when accessing registration directly', () => {
      // Try to access registration without plan
      cy.visit('/register');
      
      // Should redirect to plans page
      cy.url().should('include', '/plans');
    });

    it('should preserve plan selection through browser refresh', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 5000 }).should('exist');

      // Select first plan
      cy.get('[data-testid="plan-card"]').first().should('be.visible').click();
      cy.get('[data-testid="continue-to-registration"]', { timeout: 5000 }).should('be.visible');
      cy.get('[data-testid="continue-to-registration"]').should('be.visible').click();

      cy.url().should('include', '/register');
      cy.get('[data-testid="selected-plan"]', { timeout: 5000 }).should('be.visible');

      // Refresh the page
      cy.reload();

      // Plan should still be selected (URL contains plan parameter)
      cy.url().should('include', '/register');
      cy.url().should('include', 'plan=');
      cy.get('[data-testid="selected-plan"]').should('be.visible');
    });

    it('should allow changing plan selection', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 5000 }).should('exist');

      // Select first plan
      cy.get('[data-testid="plan-card"]').first().should('be.visible').click();
      cy.get('[data-testid="continue-to-registration"]', { timeout: 5000 }).should('be.visible');
      cy.get('[data-testid="continue-to-registration"]').should('be.visible').click();

      cy.url().should('include', '/register');

      // Go back to plans
      cy.visit('/plans');

      // Select different plan if available
      cy.get('[data-testid="plan-card"]').then($cards => {
        if ($cards.length > 1) {
          // Select second plan
          cy.get('[data-testid="plan-card"]').eq(1).should('be.visible').click();
          cy.get('[data-testid="continue-to-registration"]', { timeout: 5000 }).should('be.visible');
          cy.get('[data-testid="continue-to-registration"]').should('be.visible').click();

          // Should update registration with new plan
          cy.url().should('include', '/register');
          cy.get('[data-testid="selected-plan"]').should('be.visible');
        }
      });
    });
  });

  describe('Plan Comparison', () => {
    it('should allow comparing multiple plans', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 5000 }).should('exist');
      
      // Check if multiple plans are available
      cy.get('[data-testid="plan-card"]').then($cards => {
        if ($cards.length > 1) {
          // Compare features across plans
          cy.get('[data-testid="plan-card"]').each(($card, _index) => {
            cy.wrap($card).within(() => {
              cy.get('h3, h2, .plan-name').should('exist');
              cy.contains(/\$|\d+|Free/i).should('exist');
            });
          });
        }
      });
    });
  });

  describe('Plan Loading States', () => {
    it('should handle slow plan loading', () => {
      // Intercept plans API with delay
      cy.intercept('GET', '/api/v1/public/plans', (req) => {
        req.on('response', (res) => {
          res.setDelay(2000);
        });
      }).as('slowPlans');
      
      cy.visit('/plans');
      
      // Should eventually show plans
      cy.get('[data-testid="plan-card"]', { timeout: 5000 }).should('exist');
      cy.wait('@slowPlans');
    });

    it('should handle plan loading errors', () => {
      // Intercept and fail plans API
      cy.intercept('GET', '/api/v1/public/plans', { forceNetworkError: true }).as('failedPlans');
      
      cy.visit('/plans');
      
      // Should show loading state initially or handle gracefully
      cy.get('body').should('be.visible');
      
      // Wait a moment for the error to potentially manifest
      cy.waitForStableDOM();
      
      // Page should still be functional (either show error or fallback content)
      cy.get('body').should('not.be.empty');
    });
  });

  describe('Pricing Display', () => {
    it('should show proper pricing format', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 5000 }).should('exist');
      
      cy.get('[data-testid="plan-card"]').each(($card) => {
        cy.wrap($card).within(() => {
          // Should show price in proper format or "Free"
          cy.contains(/\$|\d+|Free/i).should('exist');
        });
      });
    });

    it('should handle different currencies if supported', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 5000 }).should('exist');
      
      // Check for currency symbols
      cy.get('[data-testid="plan-card"]').first().within(() => {
        cy.contains(/\$|€|£|USD|EUR|GBP|Free/i).should('exist');
      });
    });
  });

  describe('Plan Features', () => {
    it('should display plan features clearly', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 5000 }).should('exist');
      
      cy.get('[data-testid="plan-card"]').first().within(() => {
        // Should have some kind of feature list
        cy.get('ul, .features, li').should('exist');
      });
    });

    it('should highlight popular or recommended plans', () => {
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"]', { timeout: 5000 }).should('exist');
      
      // Check for popular/recommended badges
      cy.get('body').then($body => {
        const badgeSelectors = [
          '[data-testid="popular-badge"]',
          '[data-testid="recommended-badge"]',
          '.popular',
          '.recommended'
        ];
        
        badgeSelectors.forEach(selector => {
          if ($body.find(selector).length > 0) {
            cy.get(selector).should('be.visible');
          }
        });
      });
    });
  });
});

export {};
