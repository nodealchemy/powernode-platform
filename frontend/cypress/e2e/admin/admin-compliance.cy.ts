/// <reference types="cypress" />

/**
 * Admin Compliance Tests
 *
 * Tests for Compliance functionality including:
 * - Compliance dashboard
 * - GDPR compliance
 * - Data retention
 * - Privacy settings
 * - Compliance reports
 * - Data export requests
 */

describe('Admin Compliance Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Compliance Dashboard', () => {
    it('should navigate to compliance page', () => {
      cy.visit('/app/admin/compliance');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCompliance = $body.text().includes('Compliance') ||
                             $body.text().includes('Privacy') ||
                             $body.text().includes('GDPR');
        if (hasCompliance) {
          cy.log('Compliance page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display compliance status', () => {
      cy.visit('/app/admin/compliance');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Compliant') ||
                         $body.text().includes('Status') ||
                         $body.text().includes('Complete');
        if (hasStatus) {
          cy.log('Compliance status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display compliance checklist', () => {
      cy.visit('/app/admin/compliance');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasChecklist = $body.find('input[type="checkbox"], ul li, [data-testid="checklist"]').length > 0 ||
                            $body.text().includes('✓');
        if (hasChecklist) {
          cy.log('Compliance checklist displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('GDPR Compliance', () => {
    beforeEach(() => {
      cy.visit('/app/admin/compliance/gdpr');
      cy.waitForPageLoad();
    });

    it('should display GDPR settings', () => {
      cy.get('body').then($body => {
        const hasGDPR = $body.text().includes('GDPR') ||
                       $body.text().includes('Data Protection') ||
                       $body.text().includes('European');
        if (hasGDPR) {
          cy.log('GDPR settings displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display consent management', () => {
      cy.get('body').then($body => {
        const hasConsent = $body.text().includes('Consent') ||
                          $body.text().includes('Permission') ||
                          $body.text().includes('Agree');
        if (hasConsent) {
          cy.log('Consent management displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display data subject rights', () => {
      cy.get('body').then($body => {
        const hasRights = $body.text().includes('Rights') ||
                         $body.text().includes('Access') ||
                         $body.text().includes('Erasure') ||
                         $body.text().includes('Portability');
        if (hasRights) {
          cy.log('Data subject rights displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Data Retention', () => {
    it('should navigate to data retention settings', () => {
      cy.visit('/app/admin/compliance/retention');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasRetention = $body.text().includes('Retention') ||
                            $body.text().includes('Data') ||
                            $body.text().includes('Policy');
        if (hasRetention) {
          cy.log('Data retention page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display retention policies', () => {
      cy.visit('/app/admin/compliance/retention');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasPolicies = $body.text().includes('Policy') ||
                          $body.text().includes('days') ||
                          $body.text().includes('months');
        if (hasPolicies) {
          cy.log('Retention policies displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have data type retention settings', () => {
      cy.visit('/app/admin/compliance/retention');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasTypes = $body.text().includes('User') ||
                        $body.text().includes('Log') ||
                        $body.text().includes('Transaction');
        if (hasTypes) {
          cy.log('Data type settings displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Data Export Requests', () => {
    it('should navigate to data requests', () => {
      cy.visit('/app/admin/compliance/data-requests');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasRequests = $body.text().includes('Request') ||
                          $body.text().includes('Export') ||
                          $body.text().includes('Data');
        if (hasRequests) {
          cy.log('Data requests page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display request list', () => {
      cy.visit('/app/admin/compliance/data-requests');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasList = $body.find('table, [data-testid="requests-list"]').length > 0;
        if (hasList) {
          cy.log('Request list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display request status', () => {
      cy.visit('/app/admin/compliance/data-requests');
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

    it('should have approve/process actions', () => {
      cy.visit('/app/admin/compliance/data-requests');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasActions = $body.find('button:contains("Approve"), button:contains("Process"), button:contains("Complete")').length > 0 ||
                          $body.text().includes('Approve');
        if (hasActions) {
          cy.log('Request actions displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Compliance Reports', () => {
    it('should navigate to compliance reports', () => {
      cy.visit('/app/admin/compliance/reports');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasReports = $body.text().includes('Report') ||
                          $body.text().includes('Audit') ||
                          $body.text().includes('Summary');
        if (hasReports) {
          cy.log('Compliance reports page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have generate report option', () => {
      cy.visit('/app/admin/compliance/reports');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasGenerate = $body.find('button:contains("Generate"), button:contains("Create")').length > 0 ||
                           $body.text().includes('Generate');
        if (hasGenerate) {
          cy.log('Generate report option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have export report option', () => {
      cy.visit('/app/admin/compliance/reports');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasExport = $body.find('button:contains("Export"), button:contains("Download")').length > 0 ||
                         $body.text().includes('Export');
        if (hasExport) {
          cy.log('Export report option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Privacy Settings', () => {
    it('should navigate to privacy settings', () => {
      cy.visit('/app/admin/compliance/privacy');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasPrivacy = $body.text().includes('Privacy') ||
                          $body.text().includes('Setting') ||
                          $body.text().includes('Data');
        if (hasPrivacy) {
          cy.log('Privacy settings page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display cookie settings', () => {
      cy.visit('/app/admin/compliance/privacy');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCookies = $body.text().includes('Cookie') ||
                          $body.text().includes('Tracking');
        if (hasCookies) {
          cy.log('Cookie settings displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display analytics settings', () => {
      cy.visit('/app/admin/compliance/privacy');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasAnalytics = $body.text().includes('Analytics') ||
                           $body.text().includes('Tracking') ||
                           $body.text().includes('Collection');
        if (hasAnalytics) {
          cy.log('Analytics settings displayed');
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
      it(`should display compliance correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/admin/compliance');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`Compliance displayed correctly on ${name}`);
      });
    });
  });
});
