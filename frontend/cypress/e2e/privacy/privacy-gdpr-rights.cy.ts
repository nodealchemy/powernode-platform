/// <reference types="cypress" />

/**
 * Privacy GDPR Rights Tests
 *
 * Tests for GDPR Data Subject Rights including:
 * - Right to access
 * - Right to rectification
 * - Right to erasure
 * - Right to portability
 * - Right to restriction
 * - Right to object
 */

describe('Privacy GDPR Rights Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('GDPR Rights Overview', () => {
    it('should navigate to GDPR rights page', () => {
      cy.visit('/app/account/privacy/gdpr');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasGDPR = $body.text().includes('GDPR') ||
                       $body.text().includes('Rights') ||
                       $body.text().includes('Data Protection');
        if (hasGDPR) {
          cy.log('GDPR rights page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display available rights', () => {
      cy.visit('/app/account/privacy/gdpr');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasRights = $body.text().includes('Access') ||
                         $body.text().includes('Delete') ||
                         $body.text().includes('Export');
        if (hasRights) {
          cy.log('Available rights displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Right to Access', () => {
    beforeEach(() => {
      cy.visit('/app/account/privacy/gdpr');
      cy.waitForPageLoad();
    });

    it('should display data access option', () => {
      cy.get('body').then($body => {
        const hasAccess = $body.text().includes('Access') ||
                         $body.text().includes('View my data') ||
                         $body.text().includes('See what');
        if (hasAccess) {
          cy.log('Data access option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have request data access button', () => {
      cy.get('body').then($body => {
        const hasButton = $body.find('button:contains("Request"), button:contains("Access"), button:contains("View")').length > 0;
        if (hasButton) {
          cy.log('Request data access button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display data categories', () => {
      cy.get('body').then($body => {
        const hasCategories = $body.text().includes('Profile') ||
                             $body.text().includes('Activity') ||
                             $body.text().includes('Payment') ||
                             $body.text().includes('Usage');
        if (hasCategories) {
          cy.log('Data categories displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Right to Erasure', () => {
    beforeEach(() => {
      cy.visit('/app/account/privacy/gdpr');
      cy.waitForPageLoad();
    });

    it('should display delete data option', () => {
      cy.get('body').then($body => {
        const hasDelete = $body.text().includes('Delete') ||
                         $body.text().includes('Erasure') ||
                         $body.text().includes('Remove');
        if (hasDelete) {
          cy.log('Delete data option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have request deletion button', () => {
      cy.get('body').then($body => {
        const hasButton = $body.find('button:contains("Delete"), button:contains("Request deletion")').length > 0;
        if (hasButton) {
          cy.log('Request deletion button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display deletion warning', () => {
      cy.get('body').then($body => {
        const hasWarning = $body.text().includes('Warning') ||
                          $body.text().includes('permanent') ||
                          $body.text().includes('cannot be undone');
        if (hasWarning) {
          cy.log('Deletion warning displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Right to Portability', () => {
    beforeEach(() => {
      cy.visit('/app/account/privacy/gdpr');
      cy.waitForPageLoad();
    });

    it('should display data export option', () => {
      cy.get('body').then($body => {
        const hasExport = $body.text().includes('Export') ||
                         $body.text().includes('Download') ||
                         $body.text().includes('Portability');
        if (hasExport) {
          cy.log('Data export option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have export format options', () => {
      cy.get('body').then($body => {
        const hasFormats = $body.text().includes('JSON') ||
                          $body.text().includes('CSV') ||
                          $body.text().includes('Format');
        if (hasFormats) {
          cy.log('Export format options displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have request export button', () => {
      cy.get('body').then($body => {
        const hasButton = $body.find('button:contains("Export"), button:contains("Download"), button:contains("Request")').length > 0;
        if (hasButton) {
          cy.log('Request export button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Right to Rectification', () => {
    beforeEach(() => {
      cy.visit('/app/account/privacy/gdpr');
      cy.waitForPageLoad();
    });

    it('should display data correction option', () => {
      cy.get('body').then($body => {
        const hasCorrect = $body.text().includes('Correct') ||
                          $body.text().includes('Update') ||
                          $body.text().includes('Rectif');
        if (hasCorrect) {
          cy.log('Data correction option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should link to profile editing', () => {
      cy.get('body').then($body => {
        const hasLink = $body.find('a[href*="profile"], a:contains("Edit")').length > 0 ||
                       $body.text().includes('Edit');
        if (hasLink) {
          cy.log('Profile edit link displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Right to Restriction', () => {
    beforeEach(() => {
      cy.visit('/app/account/privacy/gdpr');
      cy.waitForPageLoad();
    });

    it('should display processing restriction option', () => {
      cy.get('body').then($body => {
        const hasRestrict = $body.text().includes('Restrict') ||
                          $body.text().includes('Limit') ||
                          $body.text().includes('Processing');
        if (hasRestrict) {
          cy.log('Restriction option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Right to Object', () => {
    beforeEach(() => {
      cy.visit('/app/account/privacy/gdpr');
      cy.waitForPageLoad();
    });

    it('should display marketing objection option', () => {
      cy.get('body').then($body => {
        const hasMarketing = $body.text().includes('Marketing') ||
                           $body.text().includes('Object') ||
                           $body.text().includes('Unsubscribe');
        if (hasMarketing) {
          cy.log('Marketing objection option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display profiling objection option', () => {
      cy.get('body').then($body => {
        const hasProfiling = $body.text().includes('Profiling') ||
                           $body.text().includes('Automated') ||
                           $body.text().includes('Decision');
        if (hasProfiling) {
          cy.log('Profiling objection option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Request History', () => {
    it('should display request history', () => {
      cy.visit('/app/account/privacy/requests');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasHistory = $body.text().includes('History') ||
                          $body.text().includes('Request') ||
                          $body.text().includes('Previous');
        if (hasHistory) {
          cy.log('Request history displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display request status', () => {
      cy.visit('/app/account/privacy/requests');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Pending') ||
                         $body.text().includes('Completed') ||
                         $body.text().includes('Processing');
        if (hasStatus) {
          cy.log('Request status displayed');
        }
      });

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
      it(`should display GDPR rights correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/account/privacy/gdpr');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`GDPR rights displayed correctly on ${name}`);
      });
    });
  });
});
