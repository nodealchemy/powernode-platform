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
      cy.assertContainsAny(['Compliance', 'Privacy', 'GDPR']);
    });

    it('should display compliance status', () => {
      cy.visit('/app/admin/compliance');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Compliant', 'Status', 'Complete']);
    });

    it('should display compliance checklist', () => {
      cy.visit('/app/admin/compliance');
      cy.waitForPageLoad();
      cy.assertHasElement(['input[type="checkbox"]', 'ul li', '[data-testid="checklist"]']);
    });
  });

  describe('GDPR Compliance', () => {
    beforeEach(() => {
      cy.visit('/app/admin/compliance/gdpr');
      cy.waitForPageLoad();
    });

    it('should display GDPR settings', () => {
      cy.assertContainsAny(['GDPR', 'Data Protection', 'European']);
    });

    it('should display consent management', () => {
      cy.assertContainsAny(['Consent', 'Permission', 'Agree']);
    });

    it('should display data subject rights', () => {
      cy.assertContainsAny(['Rights', 'Access', 'Erasure', 'Portability']);
    });
  });

  describe('Data Retention', () => {
    it('should navigate to data retention settings', () => {
      cy.visit('/app/admin/compliance/retention');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Retention', 'Data', 'Policy']);
    });

    it('should display retention policies', () => {
      cy.visit('/app/admin/compliance/retention');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Policy', 'days', 'months']);
    });

    it('should have data type retention settings', () => {
      cy.visit('/app/admin/compliance/retention');
      cy.waitForPageLoad();
      cy.assertContainsAny(['User', 'Log', 'Transaction']);
    });
  });

  describe('Data Export Requests', () => {
    it('should navigate to data requests', () => {
      cy.visit('/app/admin/compliance/data-requests');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Request', 'Export', 'Data']);
    });

    it('should display request list', () => {
      cy.visit('/app/admin/compliance/data-requests');
      cy.waitForPageLoad();
      cy.assertHasElement(['table', '[data-testid="requests-list"]']);
    });

    it('should display request status', () => {
      cy.visit('/app/admin/compliance/data-requests');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Pending', 'Completed', 'Processing']);
    });

    it('should have approve/process actions', () => {
      cy.visit('/app/admin/compliance/data-requests');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Approve', 'Process', 'Complete']);
    });
  });

  describe('Compliance Reports', () => {
    it('should navigate to compliance reports', () => {
      cy.visit('/app/admin/compliance/reports');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Report', 'Audit', 'Summary']);
    });

    it('should have generate report option', () => {
      cy.visit('/app/admin/compliance/reports');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Generate', 'Create']);
    });

    it('should have export report option', () => {
      cy.visit('/app/admin/compliance/reports');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Export', 'Download']);
    });
  });

  describe('Privacy Settings', () => {
    it('should navigate to privacy settings', () => {
      cy.visit('/app/admin/compliance/privacy');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Privacy', 'Setting', 'Data']);
    });

    it('should display cookie settings', () => {
      cy.visit('/app/admin/compliance/privacy');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Cookie', 'Tracking']);
    });

    it('should display analytics settings', () => {
      cy.visit('/app/admin/compliance/privacy');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Analytics', 'Tracking', 'Collection']);
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

        cy.assertContainsAny(['Compliance', 'Privacy', 'GDPR']);
      });
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('**/api/**/admin/compliance*', {
        statusCode: 500,
        visitUrl: '/app/admin/compliance',
      });
    });
  });

  describe('Permission Check', () => {
    it('should require admin permissions', () => {
      cy.testPermissionDenied('/app/admin/compliance');
    });
  });
});
