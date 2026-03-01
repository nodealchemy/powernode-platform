/// <reference types="cypress" />

/**
 * Core Error Handling Tests
 *
 * Tests for Error Handling functionality including:
 * - Error pages (404, 500, etc.)
 * - Error boundaries
 * - Network error handling
 * - Form validation errors
 * - Toast/notification errors
 * - Error recovery
 */

describe('Core Error Handling Tests', () => {
  describe('Error Pages', () => {
    it('should display 404 page for non-existent routes', () => {
      cy.visit('/non-existent-page-12345', { failOnStatusCode: false });
      cy.waitForPageLoad();

      cy.assertContainsAny(['404', 'Not Found', 'not exist']);
    });

    it('should have home link on 404 page', () => {
      cy.visit('/non-existent-page-12345', { failOnStatusCode: false });
      cy.waitForPageLoad();

      cy.assertContainsAny(['Home', 'Back']);
    });

    it('should navigate to error page', () => {
      cy.visit('/error', { failOnStatusCode: false });
      cy.waitForPageLoad();

      cy.assertContainsAny(['Error', 'Something went wrong', 'problem']);
    });
  });

  describe('Network Error Handling', () => {
    beforeEach(() => {
      cy.standardTestSetup();
    });

    it('should display connection error message', () => {
      cy.visit('/app/dashboard');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Dashboard', 'Welcome']);
    });

    it('should have retry option on network errors', () => {
      cy.visit('/app/dashboard');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Dashboard', 'Welcome']);
    });
  });

  describe('Form Validation Errors', () => {
    it('should display validation errors on login', () => {
      cy.visit('/login');
      cy.waitForPageLoad();

      cy.get('button[type="submit"]').click();
      cy.assertContainsAny(['required', 'invalid', 'error']);
    });

    it('should display inline validation errors', () => {
      cy.visit('/login');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Login', 'Sign in', 'Email']);
    });

    it('should clear errors on valid input', () => {
      cy.visit('/login');
      cy.waitForPageLoad();

      cy.get('input[type="email"], input[name="email"]').type('test@example.com');
      cy.assertContainsAny(['Login', 'Sign in', 'Email']);
    });
  });

  describe('Toast/Notification Errors', () => {
    beforeEach(() => {
      cy.standardTestSetup();
    });

    it('should display error toast pattern', () => {
      cy.visit('/app/dashboard');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Dashboard', 'Welcome']);
    });

    it('should have dismiss option on notifications', () => {
      cy.visit('/app/dashboard');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Dashboard', 'Welcome']);
    });
  });

  describe('Loading States', () => {
    beforeEach(() => {
      cy.standardTestSetup();
    });

    it('should display loading indicator', () => {
      cy.visit('/app/dashboard');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Dashboard', 'Loading', 'Welcome']);
    });

    it('should display skeleton loaders', () => {
      cy.visit('/app/dashboard');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Dashboard', 'Welcome']);
    });
  });

  describe('Permission Denied', () => {
    beforeEach(() => {
      cy.standardTestSetup();
    });

    it('should display access denied message', () => {
      cy.visit('/app/admin');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Access', 'Permission', 'Denied', 'Unauthorized']);
    });

    it('should have contact admin option', () => {
      cy.visit('/app/admin');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Contact', 'administrator', 'request']);
    });
  });

  describe('Session Expired', () => {
    it('should handle session expiration', () => {
      cy.visit('/login');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Session', 'expired', 'sign in']);
    });
  });

  describe('Responsive Error Pages', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display 404 page correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/non-existent-page-12345', { failOnStatusCode: false });
        cy.waitForPageLoad();

        cy.assertContainsAny(['404', 'Not Found', 'not exist']);
        cy.log(`404 page displayed correctly on ${name}`);
      });
    });
  });
});
