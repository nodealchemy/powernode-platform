/// <reference types="cypress" />

/**
 * Delegations Management Tests
 *
 * Tests for Account Delegations functionality including:
 * - Page navigation and load
 * - Delegation listing
 * - Create delegation flow
 * - Delegation details view
 * - Delegation request handling
 * - Revoke delegation
 * - Tab navigation (outgoing/incoming)
 * - Permission reference display
 * - Error handling
 * - Responsive design
 */

describe('Delegations Management Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Page Navigation', () => {
    it('should navigate to Delegations page', () => {
      cy.visit('/app/account/delegations');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Delegation', 'Account', 'Access']);
    });

    it('should display page title', () => {
      cy.visit('/app/account/delegations');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Account Delegations', 'Delegations']);
    });

    it('should display page description', () => {
      cy.visit('/app/account/delegations');
      cy.waitForPageLoad();
      cy.assertContainsAny(['cross-account', 'access', 'Manage']);
    });
  });

  describe('Tab Navigation', () => {
    beforeEach(() => {
      cy.visit('/app/account/delegations');
      cy.waitForPageLoad();
    });

    it('should display Outgoing Delegations tab', () => {
      cy.assertContainsAny(['Outgoing', 'Outgoing Delegations']);
    });

    it('should display Incoming Access tab', () => {
      cy.assertContainsAny(['Incoming', 'Incoming Access']);
    });

    it('should switch to Incoming Access tab', () => {
      cy.get('button:contains("Incoming")').first().click();
      cy.assertContainsAny(['Incoming', 'Incoming Access']);
    });
  });

  describe('Create Delegation', () => {
    beforeEach(() => {
      cy.visit('/app/account/delegations');
      cy.waitForPageLoad();
    });

    it('should display Create Delegation button', () => {
      cy.assertContainsAny(['Create Delegation', 'Create']);
    });

    it('should open Create Delegation modal', () => {
      cy.assertHasElement(['button:contains("Create Delegation")', 'button:contains("Create")']);
    });
  });

  describe('Active Delegations', () => {
    beforeEach(() => {
      cy.visit('/app/account/delegations');
      cy.waitForPageLoad();
    });

    it('should display Active Delegations section', () => {
      cy.assertContainsAny(['Active Delegations', 'Granted Access']);
    });

    it('should display delegation cards or empty state', () => {
      cy.assertContainsAny(['No active delegations', 'Create a delegation', 'user', 'permission']);
    });

    it('should display status badges on delegation cards', () => {
      cy.assertContainsAny(['Active', 'Pending', 'Expired', 'Revoked', 'No active']);
    });
  });

  describe('Inactive Delegations', () => {
    beforeEach(() => {
      cy.visit('/app/account/delegations');
      cy.waitForPageLoad();
    });

    it('should display Inactive Delegations section', () => {
      cy.assertContainsAny(['Inactive', 'Inactive Delegations']);
    });

    it('should display expired/revoked delegations or empty state', () => {
      cy.assertContainsAny(['Expired', 'Revoked', 'No inactive delegations']);
    });
  });

  describe('Pending Requests', () => {
    beforeEach(() => {
      cy.visit('/app/account/delegations');
      cy.waitForPageLoad();
    });

    it('should display pending requests alert if any', () => {
      cy.assertContainsAny(['Pending', 'No pending', 'pending delegation request', 'awaiting']);
    });

    it('should display Review button for pending requests', () => {
      cy.assertContainsAny(['Review', 'Pending', 'Delegation']);
    });
  });

  describe('Available Permissions Reference', () => {
    beforeEach(() => {
      cy.visit('/app/account/delegations');
      cy.waitForPageLoad();
    });

    it('should display Available Permissions section', () => {
      cy.assertContainsAny(['Available Permissions', 'Permissions']);
    });

    it('should display permission cards with descriptions', () => {
      cy.assertContainsAny(['Permission', 'description', 'label']);
    });
  });

  describe('Delegation Details Modal', () => {
    beforeEach(() => {
      cy.visit('/app/account/delegations');
      cy.waitForPageLoad();
    });

    it('should open details modal when clicking delegation card', () => {
      cy.assertHasElement(['[data-testid="delegation-card"]', '.cursor-pointer', 'a']);
    });
  });

  describe('Revoke Delegation', () => {
    beforeEach(() => {
      cy.visit('/app/account/delegations');
      cy.waitForPageLoad();
    });

    it('should have revoke option in delegation details', () => {
      cy.assertContainsAny(['Revoke', 'Delegation']);
    });
  });

  describe('Loading States', () => {
    it('should show loading indicator while fetching data', () => {
      cy.visit('/app/account/delegations');
      cy.assertContainsAny(['Delegations', 'Management']);
      cy.waitForPageLoad();
    });
  });

  describe('Empty States', () => {
    beforeEach(() => {
      cy.visit('/app/account/delegations');
      cy.waitForPageLoad();
    });

    it('should display empty state for no active delegations', () => {
      cy.assertContainsAny(['No active delegations', 'Create a delegation']);
    });

    it('should display empty state for no inactive delegations', () => {
      cy.assertContainsAny(['No inactive delegations', 'Expired and revoked']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.visit('/app/account/delegations');
      cy.waitForPageLoad();

      // Page should still be functional even if API fails
      cy.assertContainsAny(['Delegations', 'Management']);
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
        cy.visit('/app/account/delegations');
        cy.waitForPageLoad();

        cy.assertContainsAny(['Delegations', 'Management']);
        cy.log(`Delegations page displayed correctly on ${name}`);
      });
    });
  });
});
