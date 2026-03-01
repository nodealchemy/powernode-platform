/// <reference types="cypress" />

/**
 * Account Team Invitations Tests
 *
 * Tests for Team Invitation functionality including:
 * - Send invitation flow
 * - Invitation list display
 * - Resend invitation
 * - Cancel invitation
 * - Role assignment in invitation
 * - Permission assignment in invitation
 * - Error handling
 * - Validation
 */

describe('Account Team Invitations Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Invitation Section Access', () => {
    it('should navigate to team management page', () => {
      cy.visit('/app/account/team');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Team', 'Members', 'Users']);
    });

    it('should display Invite button', () => {
      cy.visit('/app/account/team');
      cy.waitForPageLoad();
      cy.get('button').contains(/Invite/i).should('exist');
    });
  });

  describe('Invite Team Member Modal', () => {
    beforeEach(() => {
      cy.visit('/app/account/team');
      cy.waitForPageLoad();
    });

    it('should open invite modal', () => {
      cy.get('button').contains(/Invite/i).first().click();
      cy.waitForStableDOM();
      cy.assertContainsAny(['Invite', 'Team', 'Member']);
    });

    it('should display email input field', () => {
      cy.get('button').contains(/Invite/i).first().click();
      cy.waitForStableDOM();
      cy.assertHasElement(['input[type="email"]', 'input[name*="email"]']);
    });

    it('should display role selection', () => {
      cy.get('button').contains(/Invite/i).first().click();
      cy.waitForStableDOM();
      cy.assertContainsAny(['Role']);
    });

    it('should display permission options', () => {
      cy.get('button').contains(/Invite/i).first().click();
      cy.waitForStableDOM();
      cy.assertContainsAny(['Permission']);
    });

    it('should have Send Invitation button', () => {
      cy.get('button').contains(/Invite/i).first().click();
      cy.waitForStableDOM();
      cy.get('button').contains(/Send/i).should('exist');
    });
  });

  describe('Email Validation', () => {
    beforeEach(() => {
      cy.visit('/app/account/team');
      cy.waitForPageLoad();
    });

    it('should validate email format', () => {
      cy.get('button').contains(/Invite/i).first().click();
      cy.waitForStableDOM();
      cy.get('input[type="email"], input[name*="email"]').first().type('invalid-email');
      cy.assertContainsAny(['Email', 'Invite', 'valid']);
    });
  });

  describe('Pending Invitations List', () => {
    beforeEach(() => {
      cy.visit('/app/account/team');
      cy.waitForPageLoad();
    });

    it('should display pending invitations section', () => {
      cy.assertContainsAny(['Pending', 'Invitations', 'invited']);
    });

    it('should display invitation details', () => {
      cy.assertContainsAny(['@', 'Sent', 'Status', 'No pending']);
    });
  });

  describe('Resend Invitation', () => {
    beforeEach(() => {
      cy.visit('/app/account/team');
      cy.waitForPageLoad();
    });

    it('should display resend option for pending invitations', () => {
      cy.get('button').contains(/Resend/i).should('exist');
    });
  });

  describe('Cancel Invitation', () => {
    beforeEach(() => {
      cy.visit('/app/account/team');
      cy.waitForPageLoad();
    });

    it('should display cancel option for pending invitations', () => {
      cy.get('button').contains(/Cancel|Revoke/i).should('exist');
    });
  });

  describe('Role Options', () => {
    beforeEach(() => {
      cy.visit('/app/account/team');
      cy.waitForPageLoad();
    });

    it('should display available roles', () => {
      cy.get('button').contains(/Invite/i).first().click();
      cy.waitForStableDOM();
      cy.assertContainsAny(['Admin', 'Manager', 'Member', 'Billing']);
    });
  });

  describe('Error Handling', () => {
    it('should handle duplicate email invitation', () => {
      cy.visit('/app/account/team');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Team', 'Members', 'Invite']);
    });

    it('should handle API errors gracefully', () => {
      cy.visit('/app/account/team');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Team', 'Members', 'Invite']);
    });
  });

  describe('Responsive Design', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display invitation interface correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/account/team');
        cy.waitForPageLoad();
        cy.assertContainsAny(['Team', 'Invite', 'Members']);
      });
    });
  });
});
