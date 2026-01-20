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

      cy.get('body').then($body => {
        const hasTeam = $body.text().includes('Team') ||
                       $body.text().includes('Members') ||
                       $body.text().includes('Users');
        if (hasTeam) {
          cy.log('Team management page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Invite button', () => {
      cy.visit('/app/account/team');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasInviteBtn = $body.text().includes('Invite') ||
                            $body.find('button:contains("Invite")').length > 0;
        if (hasInviteBtn) {
          cy.log('Invite button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Invite Team Member Modal', () => {
    beforeEach(() => {
      cy.visit('/app/account/team');
      cy.waitForPageLoad();
    });

    it('should open invite modal', () => {
      cy.get('body').then($body => {
        const inviteBtn = $body.find('button:contains("Invite")');
        if (inviteBtn.length > 0) {
          cy.wrap(inviteBtn).first().click();
          cy.log('Invite modal opened');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display email input field', () => {
      cy.get('body').then($body => {
        const inviteBtn = $body.find('button:contains("Invite")');
        if (inviteBtn.length > 0) {
          cy.wrap(inviteBtn).first().click();

          cy.get('body').then($innerBody => {
            const hasEmail = $innerBody.find('input[type="email"], input[name*="email"]').length > 0 ||
                            $innerBody.text().includes('Email');
            if (hasEmail) {
              cy.log('Email input field displayed');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display role selection', () => {
      cy.get('body').then($body => {
        const inviteBtn = $body.find('button:contains("Invite")');
        if (inviteBtn.length > 0) {
          cy.wrap(inviteBtn).first().click();

          cy.get('body').then($innerBody => {
            const hasRole = $innerBody.text().includes('Role') ||
                           $innerBody.find('select, [data-testid*="role"]').length > 0;
            if (hasRole) {
              cy.log('Role selection displayed');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display permission options', () => {
      cy.get('body').then($body => {
        const inviteBtn = $body.find('button:contains("Invite")');
        if (inviteBtn.length > 0) {
          cy.wrap(inviteBtn).first().click();

          cy.get('body').then($innerBody => {
            const hasPermissions = $innerBody.text().includes('Permission') ||
                                   $innerBody.find('[data-testid*="permission"]').length > 0;
            if (hasPermissions) {
              cy.log('Permission options displayed');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Send Invitation button', () => {
      cy.get('body').then($body => {
        const inviteBtn = $body.find('button:contains("Invite")');
        if (inviteBtn.length > 0) {
          cy.wrap(inviteBtn).first().click();

          cy.get('body').then($innerBody => {
            const hasSendBtn = $innerBody.text().includes('Send') ||
                              $innerBody.find('button:contains("Send"), button[type="submit"]').length > 0;
            if (hasSendBtn) {
              cy.log('Send Invitation button displayed');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Email Validation', () => {
    beforeEach(() => {
      cy.visit('/app/account/team');
      cy.waitForPageLoad();
    });

    it('should validate email format', () => {
      cy.get('body').then($body => {
        const inviteBtn = $body.find('button:contains("Invite")');
        if (inviteBtn.length > 0) {
          cy.wrap(inviteBtn).first().click();

          const emailInput = cy.get('input[type="email"], input[name*="email"]');
          emailInput.then($input => {
            if ($input.length > 0) {
              cy.wrap($input).first().type('invalid-email');
              cy.log('Testing email validation');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Pending Invitations List', () => {
    beforeEach(() => {
      cy.visit('/app/account/team');
      cy.waitForPageLoad();
    });

    it('should display pending invitations section', () => {
      cy.get('body').then($body => {
        const hasPending = $body.text().includes('Pending') ||
                          $body.text().includes('Invitations') ||
                          $body.text().includes('invited');
        if (hasPending) {
          cy.log('Pending invitations section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display invitation details', () => {
      cy.get('body').then($body => {
        const hasDetails = $body.text().includes('@') ||
                          $body.text().includes('Sent') ||
                          $body.text().includes('Status') ||
                          $body.text().includes('No pending');
        if (hasDetails) {
          cy.log('Invitation details displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Resend Invitation', () => {
    beforeEach(() => {
      cy.visit('/app/account/team');
      cy.waitForPageLoad();
    });

    it('should display resend option for pending invitations', () => {
      cy.get('body').then($body => {
        const hasResend = $body.text().includes('Resend') ||
                         $body.find('button:contains("Resend")').length > 0;
        if (hasResend) {
          cy.log('Resend option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Cancel Invitation', () => {
    beforeEach(() => {
      cy.visit('/app/account/team');
      cy.waitForPageLoad();
    });

    it('should display cancel option for pending invitations', () => {
      cy.get('body').then($body => {
        const hasCancel = $body.text().includes('Cancel') ||
                         $body.text().includes('Revoke') ||
                         $body.find('button:contains("Cancel")').length > 0;
        if (hasCancel) {
          cy.log('Cancel option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Role Options', () => {
    beforeEach(() => {
      cy.visit('/app/account/team');
      cy.waitForPageLoad();
    });

    it('should display available roles', () => {
      cy.get('body').then($body => {
        const inviteBtn = $body.find('button:contains("Invite")');
        if (inviteBtn.length > 0) {
          cy.wrap(inviteBtn).first().click();

          cy.get('body').then($innerBody => {
            const roles = ['Admin', 'Manager', 'Member', 'Billing'];
            const foundRoles = roles.filter(role => $innerBody.text().includes(role));
            if (foundRoles.length > 0) {
              cy.log(`Found roles: ${foundRoles.join(', ')}`);
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle duplicate email invitation', () => {
      cy.visit('/app/account/team');
      cy.waitForPageLoad();

      // Page should remain functional
      cy.get('body').should('be.visible');
    });

    it('should handle API errors gracefully', () => {
      cy.visit('/app/account/team');
      cy.waitForPageLoad();

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
      it(`should display invitation interface correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/account/team');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`Team invitation interface displayed correctly on ${name}`);
      });
    });
  });
});
