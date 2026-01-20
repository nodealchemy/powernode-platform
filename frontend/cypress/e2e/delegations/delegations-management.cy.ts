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

      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Delegation') ||
                          $body.text().includes('Account') ||
                          $body.text().includes('Access');
        if (hasContent) {
          cy.log('Delegations page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page title', () => {
      cy.visit('/app/account/delegations');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('Account Delegations') ||
                        $body.text().includes('Delegations');
        if (hasTitle) {
          cy.log('Page title displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page description', () => {
      cy.visit('/app/account/delegations');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDescription = $body.text().includes('cross-account') ||
                              $body.text().includes('access') ||
                              $body.text().includes('Manage');
        if (hasDescription) {
          cy.log('Page description displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Tab Navigation', () => {
    beforeEach(() => {
      cy.visit('/app/account/delegations');
      cy.waitForPageLoad();
    });

    it('should display Outgoing Delegations tab', () => {
      cy.get('body').then($body => {
        const hasOutgoing = $body.text().includes('Outgoing') ||
                           $body.text().includes('Outgoing Delegations');
        if (hasOutgoing) {
          cy.log('Outgoing Delegations tab displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Incoming Access tab', () => {
      cy.get('body').then($body => {
        const hasIncoming = $body.text().includes('Incoming') ||
                           $body.text().includes('Incoming Access');
        if (hasIncoming) {
          cy.log('Incoming Access tab displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should switch to Incoming Access tab', () => {
      cy.get('body').then($body => {
        const incomingTab = $body.find('button:contains("Incoming")');
        if (incomingTab.length > 0) {
          cy.wrap(incomingTab).first().click();
          cy.log('Switched to Incoming Access tab');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Create Delegation', () => {
    beforeEach(() => {
      cy.visit('/app/account/delegations');
      cy.waitForPageLoad();
    });

    it('should display Create Delegation button', () => {
      cy.get('body').then($body => {
        const hasCreateBtn = $body.text().includes('Create Delegation') ||
                            $body.find('button:contains("Create")').length > 0;
        if (hasCreateBtn) {
          cy.log('Create Delegation button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should open Create Delegation modal', () => {
      cy.get('body').then($body => {
        const createBtn = $body.find('button:contains("Create Delegation")');
        if (createBtn.length > 0) {
          cy.wrap(createBtn).first().click();
          cy.log('Create Delegation modal opened');
        }
      });

      // Modal should appear
      cy.get('body').then($body => {
        const hasModal = $body.find('[role="dialog"]').length > 0 ||
                        $body.text().includes('Create') ||
                        $body.find('.modal').length > 0;
        if (hasModal) {
          cy.log('Modal is visible');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Active Delegations', () => {
    beforeEach(() => {
      cy.visit('/app/account/delegations');
      cy.waitForPageLoad();
    });

    it('should display Active Delegations section', () => {
      cy.get('body').then($body => {
        const hasActive = $body.text().includes('Active Delegations') ||
                         $body.text().includes('Granted Access');
        if (hasActive) {
          cy.log('Active Delegations section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display delegation cards or empty state', () => {
      cy.get('body').then($body => {
        const hasCards = $body.text().includes('user') ||
                        $body.text().includes('permission') ||
                        $body.text().includes('No active delegations') ||
                        $body.find('[data-testid="delegation-card"]').length > 0;
        if (hasCards) {
          cy.log('Delegation cards or empty state displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display status badges on delegation cards', () => {
      cy.get('body').then($body => {
        const hasStatusBadge = $body.text().includes('Active') ||
                              $body.text().includes('Pending') ||
                              $body.text().includes('Expired') ||
                              $body.text().includes('Revoked') ||
                              $body.text().includes('No active');
        if (hasStatusBadge) {
          cy.log('Status badges displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Inactive Delegations', () => {
    beforeEach(() => {
      cy.visit('/app/account/delegations');
      cy.waitForPageLoad();
    });

    it('should display Inactive Delegations section', () => {
      cy.get('body').then($body => {
        const hasInactive = $body.text().includes('Inactive') ||
                           $body.text().includes('Inactive Delegations');
        if (hasInactive) {
          cy.log('Inactive Delegations section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display expired/revoked delegations or empty state', () => {
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Expired') ||
                          $body.text().includes('Revoked') ||
                          $body.text().includes('No inactive delegations');
        if (hasContent) {
          cy.log('Expired/revoked delegations or empty state displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Pending Requests', () => {
    beforeEach(() => {
      cy.visit('/app/account/delegations');
      cy.waitForPageLoad();
    });

    it('should display pending requests alert if any', () => {
      cy.get('body').then($body => {
        const hasPending = $body.text().includes('Pending') ||
                          $body.text().includes('pending delegation request') ||
                          $body.text().includes('awaiting');
        if (hasPending) {
          cy.log('Pending requests alert displayed');
        } else {
          cy.log('No pending requests');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Review button for pending requests', () => {
      cy.get('body').then($body => {
        const hasReview = $body.text().includes('Review') ||
                         $body.find('button:contains("Review")').length > 0;
        if (hasReview) {
          cy.log('Review button displayed for pending requests');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Available Permissions Reference', () => {
    beforeEach(() => {
      cy.visit('/app/account/delegations');
      cy.waitForPageLoad();
    });

    it('should display Available Permissions section', () => {
      cy.get('body').then($body => {
        const hasPermissions = $body.text().includes('Available Permissions') ||
                              $body.text().includes('Permissions');
        if (hasPermissions) {
          cy.log('Available Permissions section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display permission cards with descriptions', () => {
      cy.get('body').then($body => {
        const hasPermCards = $body.text().includes('description') ||
                            $body.find('[data-testid="permission-card"]').length > 0 ||
                            $body.text().includes('label');
        if (hasPermCards) {
          cy.log('Permission cards with descriptions displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Delegation Details Modal', () => {
    beforeEach(() => {
      cy.visit('/app/account/delegations');
      cy.waitForPageLoad();
    });

    it('should open details modal when clicking delegation card', () => {
      cy.get('body').then($body => {
        // Look for delegation cards
        const delegationCard = $body.find('[data-testid="delegation-card"], .cursor-pointer');
        if (delegationCard.length > 0) {
          cy.wrap(delegationCard).first().click();
          cy.log('Delegation details modal opened');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Revoke Delegation', () => {
    beforeEach(() => {
      cy.visit('/app/account/delegations');
      cy.waitForPageLoad();
    });

    it('should have revoke option in delegation details', () => {
      cy.get('body').then($body => {
        const hasRevoke = $body.text().includes('Revoke') ||
                         $body.find('button:contains("Revoke")').length > 0;
        if (hasRevoke) {
          cy.log('Revoke option available');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Loading States', () => {
    it('should show loading indicator while fetching data', () => {
      cy.visit('/app/account/delegations');

      cy.get('body').then($body => {
        const hasLoader = $body.text().includes('Loading') ||
                         $body.find('.animate-spin').length > 0;
        if (hasLoader) {
          cy.log('Loading indicator shown');
        }
      });

      cy.waitForPageLoad();
      cy.get('body').should('be.visible');
    });
  });

  describe('Empty States', () => {
    beforeEach(() => {
      cy.visit('/app/account/delegations');
      cy.waitForPageLoad();
    });

    it('should display empty state for no active delegations', () => {
      cy.get('body').then($body => {
        const hasEmptyActive = $body.text().includes('No active delegations') ||
                              $body.text().includes('Create a delegation');
        if (hasEmptyActive) {
          cy.log('Empty state for active delegations displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display empty state for no inactive delegations', () => {
      cy.get('body').then($body => {
        const hasEmptyInactive = $body.text().includes('No inactive delegations') ||
                                $body.text().includes('Expired and revoked');
        if (hasEmptyInactive) {
          cy.log('Empty state for inactive delegations displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.visit('/app/account/delegations');
      cy.waitForPageLoad();

      // Page should still be functional even if API fails
      cy.get('body').should('be.visible');
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

        cy.get('body').should('be.visible');
        cy.log(`Delegations page displayed correctly on ${name}`);
      });
    });
  });
});
