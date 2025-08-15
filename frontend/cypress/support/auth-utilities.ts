/// <reference types="cypress" />

// Authentication testing utilities and helper functions

declare global {
  namespace Cypress {
    interface Chainable {
      /**
       * Enhanced registration command with validation
       * @example cy.registerEnhanced(userData, { validateForm: true })
       */
      registerEnhanced(userData: {
        email: string;
        password: string;
        firstName: string;
        lastName: string;
        accountName: string;
      }, options?: {
        validateForm?: boolean;
        selectPlan?: boolean;
        waitForDashboard?: boolean;
      }): Chainable<void>;

      /**
       * Enhanced login with better error handling
       * @example cy.loginEnhanced('user@example.com', 'password', { rememberMe: true })
       */
      loginEnhanced(email: string, password: string, options?: {
        rememberMe?: boolean;
        expectSuccess?: boolean;
        waitForDashboard?: boolean;
      }): Chainable<void>;

      /**
       * Logout with verification
       * @example cy.logoutEnhanced()
       */
      logoutEnhanced(): Chainable<void>;

      /**
       * Check authentication state
       * @example cy.checkAuthState('authenticated')
       */
      checkAuthState(expectedState: 'authenticated' | 'unauthenticated'): Chainable<void>;

      /**
       * Validate password strength requirements
       * @example cy.validatePasswordStrength('weakpass', false)
       */
      validatePasswordStrength(password: string, shouldBeValid: boolean): Chainable<void>;

      /**
       * Test form validation states
       * @example cy.testFormValidation('registration')
       */
      testFormValidation(formType: 'login' | 'registration'): Chainable<void>;

      /**
       * Simulate authentication errors
       * @example cy.simulateAuthError('network')
       */
      simulateAuthError(errorType: 'network' | 'server' | 'validation'): Chainable<void>;

      /**
       * Wait for authentication to complete
       * @example cy.waitForAuth()
       */
      waitForAuth(): Chainable<void>;

      /**
       * Check for error feedback in forms
       * @example cy.checkErrorFeedback(['invalid', 'error'])
       */
      checkErrorFeedback(expectedMessages?: string[]): Chainable<void>;
    }
  }
}

// Enhanced registration command
Cypress.Commands.add('registerEnhanced', (userData, options = {}) => {
  const {
    validateForm = false,
    selectPlan = true,
    waitForDashboard = true
  } = options;

  if (selectPlan) {
    // Navigate through plan selection
    cy.visit('/plans');
    cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
    cy.get('[data-testid="plan-card"]').first().click();
    cy.get('[data-testid="plan-select-btn"]', { timeout: 10000 }).should('be.visible');
    cy.get('[data-testid="plan-select-btn"]').click();
  } else {
    cy.visit('/register');
  }

  // Wait for registration form
  cy.url().should('include', '/register');
  
  if (selectPlan) {
    cy.get('[data-testid="selected-plan"]', { timeout: 15000 }).should('be.visible');
  }

  if (validateForm) {
    // Test form validation before filling
    cy.get('button[type="submit"]').should('be.disabled');
  }

  // Fill registration form with enhanced error handling
  cy.get('input[name="accountName"]').should('be.visible').clear({ force: true }).type(userData.accountName, { force: true });
  cy.get('input[name="firstName"]').should('be.visible').clear({ force: true }).type(userData.firstName, { force: true });
  cy.get('input[name="lastName"]').should('be.visible').clear({ force: true }).type(userData.lastName, { force: true });
  cy.get('input[name="email"]').should('be.visible').clear({ force: true }).type(userData.email, { force: true });
  cy.get('input[name="password"]').should('be.visible').clear({ force: true }).type(userData.password, { force: true });

  if (validateForm) {
    // Verify form is ready for submission
    cy.get('button[type="submit"]').should('not.be.disabled');
  }

  // Submit registration
  cy.get('button[type="submit"]').click({ force: true });

  if (waitForDashboard) {
    // Wait for successful registration
    cy.url().should('include', '/dashboard', { timeout: 20000 });
    cy.get('[data-testid="user-menu"]').should('be.visible');
    cy.contains(userData.firstName).should('be.visible');
  }
});

// Enhanced login command
Cypress.Commands.add('loginEnhanced', (email: string, password: string, options = {}) => {
  const {
    rememberMe = false,
    expectSuccess = true,
    waitForDashboard = true
  } = options;

  cy.visit('/login');
  
  // Verify login form is available
  cy.get('input[type="email"]').should('be.visible').and('not.be.disabled');
  cy.get('input[type="password"]').should('be.visible').and('not.be.disabled');
  cy.get('button[type="submit"]').should('be.visible').and('not.be.disabled');

  // Fill login form
  cy.get('input[type="email"]').clear().type(email);
  cy.get('input[type="password"]').clear().type(password);

  // Handle remember me if requested
  if (rememberMe) {
    cy.get('body').then($body => {
      if ($body.find('input[type="checkbox"]').length > 0) {
        cy.get('input[type="checkbox"]').check();
      }
    });
  }

  // Submit login
  cy.get('button[type="submit"]').click();

  if (expectSuccess && waitForDashboard) {
    // Wait for successful login
    cy.url().should('include', '/dashboard', { timeout: 15000 });
    cy.get('[data-testid="user-menu"]').should('be.visible');
  }
});

// Enhanced logout command
Cypress.Commands.add('logoutEnhanced', () => {
  // Ensure we're logged in first
  cy.get('[data-testid="user-menu"]').should('be.visible').click();
  cy.get('[data-testid="logout-btn"]').should('be.visible').click();
  
  // Verify logout was successful
  cy.url().should('include', '/login');
  
  // Verify we can't access protected routes
  cy.visit('/dashboard');
  cy.url().should('include', '/login');
});

// Check authentication state
Cypress.Commands.add('checkAuthState', (expectedState: 'authenticated' | 'unauthenticated') => {
  if (expectedState === 'authenticated') {
    cy.visit('/dashboard');
    cy.url().should('include', '/dashboard');
    cy.get('[data-testid="user-menu"]').should('be.visible');
  } else {
    cy.visit('/dashboard');
    cy.url().should('include', '/login');
    cy.get('input[type="email"]').should('be.visible');
  }
});

// Validate password strength
Cypress.Commands.add('validatePasswordStrength', (password: string, shouldBeValid: boolean) => {
  cy.visit('/plans');
  cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
  cy.get('[data-testid="plan-card"]').first().click();
  cy.get('[data-testid="plan-select-btn"]', { timeout: 10000 }).should('be.visible');
  cy.get('[data-testid="plan-select-btn"]').click();

  // Fill required fields
  const timestamp = Date.now();
  cy.get('input[name="accountName"]').type('Test Company');
  cy.get('input[name="firstName"]').type('Test');
  cy.get('input[name="lastName"]').type('User');
  cy.get('input[name="email"]').type(`test-${timestamp}@example.com`);

  // Test password
  cy.get('input[name="password"]').type(password);

  // Check form state
  if (shouldBeValid) {
    cy.get('button[type="submit"]').should('not.be.disabled');
  } else {
    cy.get('button[type="submit"]').should('be.disabled');
  }
});

// Test form validation
Cypress.Commands.add('testFormValidation', (formType: 'login' | 'registration') => {
  if (formType === 'registration') {
    cy.visit('/plans');
    cy.get('[data-testid="plan-card"]', { timeout: 15000 }).should('exist');
    cy.get('[data-testid="plan-card"]').first().click();
    cy.get('[data-testid="plan-select-btn"]', { timeout: 10000 }).should('be.visible');
    cy.get('[data-testid="plan-select-btn"]').click();

    // Test empty form
    cy.get('button[type="submit"]').should('be.disabled');

    // Test partial form filling
    cy.get('input[name="firstName"]').type('Test');
    cy.get('button[type="submit"]').should('be.disabled');

    cy.get('input[name="lastName"]').type('User');
    cy.get('button[type="submit"]').should('be.disabled');

    // Test email validation
    cy.get('input[name="email"]').type('invalid-email');
    cy.get('input[name="email"]').blur();
    cy.get('input[name="email"]:invalid').should('exist');

    cy.get('input[name="email"]').clear().type('valid@example.com');
    cy.get('input[name="accountName"]').type('Test Company');
    cy.get('input[name="password"]').type('short');
    cy.get('button[type="submit"]').should('be.disabled');

    // Valid form
    cy.get('input[name="password"]').clear().type('Qx7#mK9@pL2$nZ6%');
    cy.get('button[type="submit"]').should('not.be.disabled');

  } else if (formType === 'login') {
    cy.visit('/login');

    // Test empty form
    cy.get('button[type="submit"]').should('be.enabled'); // Login usually allows empty submission to show errors

    // Test email validation
    cy.get('input[type="email"]').type('invalid-email');
    cy.get('input[type="email"]').blur();
    cy.get('input[type="email"]:invalid').should('exist');

    // Valid form
    cy.get('input[type="email"]').clear().type('valid@example.com');
    cy.get('input[type="password"]').type('validpassword');
    cy.get('button[type="submit"]').should('be.enabled');
  }
});

// Simulate authentication errors
Cypress.Commands.add('simulateAuthError', (errorType: 'network' | 'server' | 'validation') => {
  if (errorType === 'network') {
    cy.intercept('POST', '/api/v1/auth/**', { forceNetworkError: true }).as('networkError');
  } else if (errorType === 'server') {
    cy.intercept('POST', '/api/v1/auth/**', { 
      statusCode: 500, 
      body: { success: false, error: 'Internal server error' }
    }).as('serverError');
  } else if (errorType === 'validation') {
    cy.intercept('POST', '/api/v1/auth/**', { 
      statusCode: 422, 
      body: { success: false, error: 'Validation failed' }
    }).as('validationError');
  }
});

// Wait for authentication to complete
Cypress.Commands.add('waitForAuth', () => {
  // Wait for either dashboard load or error state
  cy.url().should('satisfy', (url) => {
    return url.includes('/dashboard') || url.includes('/login') || url.includes('/register');
  });

  // If on dashboard, verify authentication
  cy.url().then(url => {
    if (url.includes('/dashboard')) {
      cy.get('[data-testid="user-menu"]').should('be.visible');
    }
  });
});

// Check for error feedback
Cypress.Commands.add('checkErrorFeedback', (expectedMessages = ['error', 'failed', 'invalid']) => {
  cy.get('body').should('satisfy', ($body) => {
    const text = $body.text().toLowerCase();
    const hasErrorMessage = expectedMessages.some(msg => text.includes(msg.toLowerCase()));
    const hasErrorClass = $body.find('.error, .alert-error, .text-red, .text-danger').length > 0;
    const hasFormError = $body.find('input:invalid, .form-error, .field-error').length > 0;
    const formCleared = $body.find('input[type="password"]').val() === '';

    return hasErrorMessage || hasErrorClass || hasFormError || formCleared;
  });
});

// Authentication test utilities
export const AUTH_TEST_UTILS = {
  // Password validation patterns
  WEAK_PASSWORDS: [
    'short',
    'password',
    '12345678',
    'abcdefgh',
    'ABCDEFGH',
    'abcd1234'
  ],
  
  STRONG_PASSWORDS: [
    'Qx7#mK9@pL2$nZ6%',
    'MyStrongP@ssw0rd!',
    'C0mpl3x&S3cur3!',
    'T3st!ng@2024'
  ],

  // Common error messages to check for
  ERROR_MESSAGES: [
    'invalid',
    'incorrect',
    'error',
    'failed',
    'wrong',
    'not found',
    'unauthorized',
    'access denied'
  ],

  // Generate unique test email
  generateTestEmail: (prefix: string = 'test') => {
    return `${prefix}-${Date.now()}-${Math.random().toString(36).substr(2, 9)}@example.com`;
  },

  // Generate test user data
  generateUserData: (prefix: string = 'Test') => {
    const timestamp = Date.now();
    return {
      email: AUTH_TEST_UTILS.generateTestEmail(prefix.toLowerCase()),
      password: 'Qx7#mK9@pL2$nZ6%',
      firstName: prefix,
      lastName: 'User',
      accountName: `${prefix} Company ${timestamp}`
    };
  },

  // Validation patterns
  EMAIL_PATTERNS: {
    VALID: [
      'user@example.com',
      'test.email+tag@domain.co.uk',
      'user.name@domain.com'
    ],
    INVALID: [
      'invalid-email',
      '@domain.com',
      'user@',
      'user.domain.com'
    ]
  },

  // Common form selectors
  SELECTORS: {
    LOGIN: {
      EMAIL: 'input[type="email"]',
      PASSWORD: 'input[type="password"]',
      SUBMIT: 'button[type="submit"]',
      REMEMBER_ME: 'input[type="checkbox"]'
    },
    REGISTRATION: {
      ACCOUNT_NAME: 'input[name="accountName"]',
      FIRST_NAME: 'input[name="firstName"]',
      LAST_NAME: 'input[name="lastName"]',
      EMAIL: 'input[name="email"]',
      PASSWORD: 'input[name="password"]',
      SUBMIT: 'button[type="submit"]'
    },
    DASHBOARD: {
      USER_MENU: '[data-testid="user-menu"]',
      LOGOUT_BTN: '[data-testid="logout-btn"]'
    }
  }
};

// Export utility functions for use in tests
export const waitForFormReady = () => {
  cy.get('form').should('be.visible');
  cy.get('button[type="submit"]').should('be.visible');
};

export const fillRegistrationForm = (userData: any) => {
  cy.get(AUTH_TEST_UTILS.SELECTORS.REGISTRATION.ACCOUNT_NAME).type(userData.accountName);
  cy.get(AUTH_TEST_UTILS.SELECTORS.REGISTRATION.FIRST_NAME).type(userData.firstName);
  cy.get(AUTH_TEST_UTILS.SELECTORS.REGISTRATION.LAST_NAME).type(userData.lastName);
  cy.get(AUTH_TEST_UTILS.SELECTORS.REGISTRATION.EMAIL).type(userData.email);
  cy.get(AUTH_TEST_UTILS.SELECTORS.REGISTRATION.PASSWORD).type(userData.password);
};

export const fillLoginForm = (email: string, password: string) => {
  cy.get(AUTH_TEST_UTILS.SELECTORS.LOGIN.EMAIL).type(email);
  cy.get(AUTH_TEST_UTILS.SELECTORS.LOGIN.PASSWORD).type(password);
};

export const verifyAuthenticationSuccess = (firstName: string) => {
  cy.url().should('include', '/dashboard');
  cy.get(AUTH_TEST_UTILS.SELECTORS.DASHBOARD.USER_MENU).should('be.visible');
  cy.contains(firstName).should('be.visible');
};