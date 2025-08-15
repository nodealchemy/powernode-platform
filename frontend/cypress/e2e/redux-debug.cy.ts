describe('Redux Registration Debug', () => {
  beforeEach(() => {
    cy.clearAppData();
  });

  it('should debug Redux register action step by step', () => {
    // Intercept and log all API calls
    cy.intercept('GET', '/api/v1/public/plans').as('getPlans');
    cy.intercept('POST', '/api/v1/auth/register').as('registerAPI');
    
    // Start flow
    cy.visit('/plans');
    cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
    cy.get('[data-testid="plan-select-btn"]').first().click({ force: true });
    
    cy.url().should('include', '/register');
    cy.get('[data-testid="selected-plan"]', { timeout: 15000 }).should('be.visible');
    
    // Fill form
    cy.get('input[name="accountName"]').clear({ force: true }).type('Redux Debug Co', { force: true });
    cy.get('input[name="firstName"]').clear({ force: true }).type('Redux', { force: true });
    cy.get('input[name="lastName"]').clear({ force: true }).type('Tester', { force: true });
    cy.get('input[name="email"]').clear({ force: true }).type('redux@test.co', { force: true });
    cy.get('input[name="password"]').clear({ force: true }).type('Qx7#mK9@pL2$nZ6%', { force: true });
    
    // Check Redux state before submit
    cy.window().then((win) => {
      const state = win.store?.getState();
      cy.log('Pre-submit Redux state:', JSON.stringify({
        auth: {
          isAuthenticated: state?.auth?.isAuthenticated,
          user: state?.auth?.user,
          isLoading: state?.auth?.isLoading,
          error: state?.auth?.error
        }
      }));
    });
    
    // Submit form
    cy.get('button[type="submit"]').should('not.be.disabled');
    cy.get('button[type="submit"]').click({ force: true });
    
    // Check Redux state immediately after click
    cy.wait(100);
    cy.window().then((win) => {
      const state = win.store?.getState();
      cy.log('Post-click Redux state:', JSON.stringify({
        auth: {
          isAuthenticated: state?.auth?.isAuthenticated,
          user: state?.auth?.user,
          isLoading: state?.auth?.isLoading,
          error: state?.auth?.error
        }
      }));
    });
    
    // Wait for API and check response
    cy.wait('@registerAPI', { timeout: 15000 }).then((interception) => {
      cy.log('API Request:', JSON.stringify(interception.request.body, null, 2));
      cy.log('API Response Status:', interception.response?.statusCode);
      cy.log('API Response Body:', JSON.stringify(interception.response?.body, null, 2));
      
      // Check Redux state after API response
      cy.window().then((win) => {
        const state = win.store?.getState();
        cy.log('Post-API Redux state:', JSON.stringify({
          auth: {
            isAuthenticated: state?.auth?.isAuthenticated,
            user: state?.auth?.user?.firstName || 'no user',
            isLoading: state?.auth?.isLoading,
            error: state?.auth?.error,
            accessToken: state?.auth?.accessToken ? 'present' : 'missing'
          }
        }));
      });
      
      // Give Redux time to process
      cy.wait(2000);
      
      // Check final state
      cy.window().then((win) => {
        const state = win.store?.getState();
        cy.log('Final Redux state:', JSON.stringify({
          auth: {
            isAuthenticated: state?.auth?.isAuthenticated,
            user: state?.auth?.user?.firstName || 'no user',
            isLoading: state?.auth?.isLoading,
            error: state?.auth?.error,
            accessToken: state?.auth?.accessToken ? 'present' : 'missing'
          },
          ui: {
            notifications: state?.ui?.notifications || []
          }
        }));
        
        // Check localStorage
        const accessToken = win.localStorage.getItem('accessToken');
        const refreshToken = win.localStorage.getItem('refreshToken');
        cy.log('LocalStorage tokens:', {
          accessToken: accessToken ? 'present' : 'missing',
          refreshToken: refreshToken ? 'present' : 'missing'
        });
      });
      
      // Check final URL
      cy.url().then(url => {
        cy.log('Final URL:', url);
        if (!url.includes('/dashboard')) {
          cy.log('PROBLEM: Still on register page, navigation did not work');
        } else {
          cy.log('SUCCESS: Navigated to dashboard');
        }
      });
    });
  });
  
  it('should test manual Redux dispatch', () => {
    cy.visit('/register?plan=01989991-0039-7f0f-ae0b-702330e26324&billing=monthly');
    
    // Wait for page to load
    cy.get('[data-testid="selected-plan"]', { timeout: 15000 }).should('be.visible');
    
    // Manually dispatch register action via Redux
    cy.window().then((win) => {
      const { store } = win;
      
      // Mock the registration payload
      const registrationPayload = {
        email: 'manual@test.co',
        password: 'Qx7#mK9@pL2$nZ6%',
        firstName: 'Manual',
        lastName: 'Test',
        accountName: 'Manual Test Co',
        planId: '01989991-0039-7f0f-ae0b-702330e26324',
        billingCycle: 'monthly'
      };
      
      cy.log('Dispatching manual register action...');
      
      // Import the register action (need to access it from window.__store__ or similar)
      // This is a test of Redux flow without React form submission
      cy.request({
        method: 'POST',
        url: 'http://localhost:3000/api/v1/auth/register',
        body: registrationPayload
      }).then((response) => {
        cy.log('Manual API call result:', response.body);
        
        // Manually update Redux state as if the action succeeded
        const mockAction = {
          type: 'auth/register/fulfilled',
          payload: response.body
        };
        
        store.dispatch(mockAction);
        
        // Check if Redux state updated
        cy.wait(100);
        cy.window().then((win) => {
          const state = win.store.getState();
          cy.log('Manual dispatch result:', {
            isAuthenticated: state.auth.isAuthenticated,
            user: state.auth.user?.firstName || 'no user',
            error: state.auth.error
          });
        });
        
        // Try manual navigation
        cy.visit('/dashboard');
        cy.url().should('include', '/dashboard');
      });
    });
  });
});