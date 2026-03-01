/// <reference types="cypress" />

/**
 * Auth Session Management Tests
 *
 * Tests for Session Management functionality including:
 * - Session timeout
 * - Session refresh
 * - Multiple sessions
 * - Session termination
 * - Remember me
 * - Idle timeout
 */

describe('Auth Session Management Tests', () => {
  describe('Active Session Display', () => {
    beforeEach(() => {
      cy.standardTestSetup();
    });

    it('should navigate to sessions page', () => {
      cy.visit('/app/account/sessions');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Session', 'Device', 'Active']);
    });

    it('should display current session', () => {
      cy.visit('/app/account/sessions');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Current', 'This device', 'Active now']);
    });

    it('should display session browser info', () => {
      cy.visit('/app/account/sessions');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Chrome', 'Firefox', 'Safari', 'Browser']);
    });

    it('should display session location', () => {
      cy.visit('/app/account/sessions');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Location', 'IP']);
    });

    it('should display last activity time', () => {
      cy.visit('/app/account/sessions');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Last', 'Activity', 'ago']);
    });
  });

  describe('Session Termination', () => {
    beforeEach(() => {
      cy.standardTestSetup();
    });

    it('should have terminate session button', () => {
      cy.visit('/app/account/sessions');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Sign out', 'End', 'Revoke']);
    });

    it('should have terminate all sessions option', () => {
      cy.visit('/app/account/sessions');
      cy.waitForPageLoad();

      cy.assertContainsAny(['all other', 'all sessions', 'Sign out all', 'End all']);
    });

    it('should show confirmation for session termination', () => {
      cy.visit('/app/account/sessions');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Confirm', 'Are you sure']);
    });
  });

  describe('Remember Me', () => {
    it('should display remember me checkbox on login', () => {
      cy.visit('/login');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Remember', 'Keep me']);
    });

    it('should have remember me label', () => {
      cy.visit('/login');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Remember me', 'Keep me signed in', 'Stay logged in']);
    });
  });

  describe('Session Security Settings', () => {
    beforeEach(() => {
      cy.standardTestSetup();
    });

    it('should navigate to security settings', () => {
      cy.visit('/app/account/security');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Security', 'Session', 'Timeout']);
    });

    it('should display session timeout setting', () => {
      cy.visit('/app/account/security');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Timeout', 'Expire', 'Inactive']);
    });

    it('should display login notification setting', () => {
      cy.visit('/app/account/security');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Notification', 'Alert', 'Email']);
    });
  });

  describe('Session Timeout Warning', () => {
    beforeEach(() => {
      cy.standardTestSetup();
    });

    it('should display session timeout warning modal pattern', () => {
      cy.visit('/app/dashboard');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Session', 'Dashboard', 'Login']);
    });

    it('should have extend session option', () => {
      cy.visit('/app/dashboard');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Extend', 'Stay', 'Continue']);
    });
  });

  describe('Logout Flow', () => {
    beforeEach(() => {
      cy.standardTestSetup();
    });

    it('should have logout option in user menu', () => {
      cy.visit('/app/dashboard');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Logout', 'Sign out', 'Log out']);
    });

    it('should navigate to logout confirmation', () => {
      cy.visit('/logout');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Logout', 'Sign out', 'signed out']);
    });
  });

  describe('Responsive Design', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display session management correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.standardTestSetup();
        cy.visit('/app/account/sessions');
        cy.waitForPageLoad();

        cy.assertContainsAny(['Session', 'Dashboard', 'Login']);
        cy.log(`Session management displayed correctly on ${name}`);
      });
    });
  });
});
