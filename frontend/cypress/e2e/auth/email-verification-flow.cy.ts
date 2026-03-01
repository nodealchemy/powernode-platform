/// <reference types="cypress" />

/**
 * Email Verification Flow Tests
 *
 * Comprehensive E2E tests for the email verification process:
 * - Token validation
 * - Success/error states
 * - Resend verification functionality
 * - Navigation flows
 * - Loading states
 */

describe('Email Verification Flow Tests', () => {
  beforeEach(() => {
    setupEmailVerificationIntercepts();
  });

  describe('Valid Token Verification', () => {
    it('should display loading state while verifying', () => {
      cy.intercept('POST', '**/api/**/auth/verify-email*', {
        statusCode: 200,
        body: { success: true, message: 'Email verified successfully!' },
        delay: 1000,
      }).as('verifyEmailSlow');

      cy.visit('/verify-email?token=valid-token-123');

      // Should show loading state
      cy.assertContainsAny(['Verifying Email', 'Verifying', 'Please wait']);
      cy.get('[class*="animate-spin"], [class*="spinner"], [class*="loading"]').should('be.visible');
    });

    it('should display success state after valid verification', () => {
      cy.intercept('POST', '**/api/**/auth/verify-email*', {
        statusCode: 200,
        body: {
          success: true,
          message: 'Your email has been successfully verified',
          user: {
            id: 'user-123',
            email: 'test@example.com',
            email_verified: true,
          },
        },
      }).as('verifyEmailSuccess');

      cy.visit('/verify-email?token=valid-token-123');
      cy.wait('@verifyEmailSuccess');

      // Should show success state
      cy.assertContainsAny(['Email Verified', 'Verified', 'Success']);
      cy.assertContainsAny(['successfully verified', 'verified', 'success']);
      cy.get('body').should('contain', 'test@example.com');
    });

    it('should have continue button after successful verification', () => {
      cy.intercept('POST', '**/api/**/auth/verify-email*', {
        statusCode: 200,
        body: { success: true, message: 'Email verified!' },
      }).as('verifyEmail');

      cy.visit('/verify-email?token=valid-token-123');
      cy.wait('@verifyEmail');

      cy.get('button').contains(/continue|dashboard|proceed/i).should('be.visible');
    });

    it('should navigate to dashboard when continue clicked (authenticated user)', () => {
      localStorage.setItem('access_token', 'mock-access-token');

      cy.intercept('POST', '**/api/**/auth/verify-email*', {
        statusCode: 200,
        body: { success: true, message: 'Email verified!' },
      }).as('verifyEmail');

      cy.visit('/verify-email?token=valid-token-123');
      cy.wait('@verifyEmail');

      cy.get('button').contains(/continue|dashboard/i).click();
      cy.url().should('include', '/app');
    });

    it('should navigate to login when continue clicked (unauthenticated user)', () => {
      localStorage.removeItem('access_token');

      cy.intercept('POST', '**/api/**/auth/verify-email*', {
        statusCode: 200,
        body: { success: true, message: 'Email verified!' },
      }).as('verifyEmail');

      cy.visit('/verify-email?token=valid-token-123');
      cy.wait('@verifyEmail');

      cy.get('button').contains(/continue|login/i).click();
      cy.url().should('include', '/login');
    });
  });

  describe('Invalid/Expired Token', () => {
    it('should display error state for invalid token', () => {
      cy.intercept('POST', '**/api/**/auth/verify-email*', {
        statusCode: 400,
        body: {
          success: false,
          error: 'Invalid or expired verification token',
        },
      }).as('verifyEmailFailed');

      cy.visit('/verify-email?token=invalid-token');
      cy.wait('@verifyEmailFailed');

      cy.assertContainsAny(['Verification Failed', 'Failed', 'Error', 'Invalid']);
      cy.assertContainsAny(['invalid', 'expired', 'failed']);
    });

    it('should show resend verification button on error', () => {
      cy.intercept('POST', '**/api/**/auth/verify-email*', {
        statusCode: 400,
        body: { success: false, error: 'Token expired' },
      }).as('verifyEmailFailed');

      cy.visit('/verify-email?token=expired-token');
      cy.wait('@verifyEmailFailed');

      cy.get('button').contains(/resend|request new|new verification/i).should('be.visible');
    });

    it('should have back to login link on error', () => {
      cy.intercept('POST', '**/api/**/auth/verify-email*', {
        statusCode: 400,
        body: { success: false, error: 'Token invalid' },
      }).as('verifyEmailFailed');

      cy.visit('/verify-email?token=bad-token');
      cy.wait('@verifyEmailFailed');

      cy.get('button, a').contains(/back to login|login/i).should('be.visible');
    });

    it('should navigate to login with resend flag when resend clicked', () => {
      cy.intercept('POST', '**/api/**/auth/verify-email*', {
        statusCode: 400,
        body: { success: false, error: 'Token expired' },
      }).as('verifyEmailFailed');

      cy.visit('/verify-email?token=expired-token');
      cy.wait('@verifyEmailFailed');

      cy.get('button').contains(/resend|request new/i).click();
      cy.url().should('include', '/login');
    });
  });

  describe('Missing Token', () => {
    it('should display invalid link message when no token provided', () => {
      cy.visit('/verify-email');

      cy.assertContainsAny(['Invalid Verification Link', 'Invalid', 'incomplete']);
      cy.assertContainsAny(['invalid', 'incomplete', 'missing']);
    });

    it('should have request new email button when no token', () => {
      cy.visit('/verify-email');

      cy.get('button').contains(/request|resend|new verification/i).should('be.visible');
    });

    it('should have back to login link when no token', () => {
      cy.visit('/verify-email');

      cy.get('button, a').contains(/back to login|login/i).should('be.visible');
    });
  });

  describe('Server Error Handling', () => {
    it('should handle 500 server error gracefully', () => {
      cy.intercept('POST', '**/api/**/auth/verify-email*', {
        statusCode: 500,
        body: { error: 'Internal server error' },
      }).as('verifyEmailError');

      cy.visit('/verify-email?token=valid-token');
      cy.wait('@verifyEmailError');

      cy.assertContainsAny(['Failed', 'Error', 'error', 'try again']);
    });

    it('should handle network timeout gracefully', () => {
      cy.intercept('POST', '**/api/**/auth/verify-email*', {
        forceNetworkError: true,
      }).as('verifyEmailTimeout');

      cy.visit('/verify-email?token=valid-token');

      // Should show error state after timeout
      cy.assertContainsAny(['Failed', 'Error', 'error', 'network']);
    });
  });

  describe('Visual States', () => {
    it('should display success icon on successful verification', () => {
      cy.intercept('POST', '**/api/**/auth/verify-email*', {
        statusCode: 200,
        body: { success: true, message: 'Email verified!' },
      }).as('verifyEmail');

      cy.visit('/verify-email?token=valid-token');
      cy.wait('@verifyEmail');

      // Should have success visual indicator (check icon or success color)
      cy.get('svg, [class*="success"], [class*="check"]').should('exist');
    });

    it('should display warning icon for invalid token', () => {
      cy.visit('/verify-email');

      // Should have warning visual indicator
      cy.get('svg, [class*="warning"], [class*="alert"]').should('exist');
    });

    it('should display error icon on verification failure', () => {
      cy.intercept('POST', '**/api/**/auth/verify-email*', {
        statusCode: 400,
        body: { success: false, error: 'Invalid token' },
      }).as('verifyEmailFailed');

      cy.visit('/verify-email?token=bad-token');
      cy.wait('@verifyEmailFailed');

      // Should have error visual indicator
      cy.get('svg, [class*="error"], [class*="alert"], [class*="warning"]').should('exist');
    });
  });

  describe('Responsive Design', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display correctly on ${name}`, () => {
        cy.viewport(width, height);

        cy.intercept('POST', '**/api/**/auth/verify-email*', {
          statusCode: 200,
          body: { success: true, message: 'Email verified!' },
        }).as('verifyEmail');

        cy.visit('/verify-email?token=valid-token');
        cy.wait('@verifyEmail');

        cy.assertContainsAny(['Verified', 'Email', 'success']);
      });
    });
  });

  describe('Accessibility', () => {
    it('should have proper heading structure', () => {
      cy.visit('/verify-email');

      cy.get('h1, h2').should('exist');
    });

    it('should have accessible button labels', () => {
      cy.visit('/verify-email');

      cy.get('button').each($btn => {
        cy.wrap($btn).should('not.be.empty');
      });
    });
  });
});

/**
 * Setup email verification API intercepts
 */
function setupEmailVerificationIntercepts() {
  // Default success response
  cy.intercept('POST', '**/api/**/auth/verify-email*', {
    statusCode: 200,
    body: {
      success: true,
      message: 'Email verified successfully!',
      user: {
        id: 'user-123',
        email: 'test@example.com',
        email_verified: true,
      },
    },
  }).as('verifyEmail');

  // Resend verification endpoint
  cy.intercept('POST', '**/api/**/auth/resend-verification*', {
    statusCode: 200,
    body: { success: true, message: 'Verification email sent' },
  }).as('resendVerification');
}

export {};
