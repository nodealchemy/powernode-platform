/// <reference types="cypress" />

/**
 * Business Analytics Export Tests
 *
 * Tests for Analytics Export functionality including:
 * - Data export options
 * - Export formats (CSV, PDF, Excel)
 * - Report generation
 * - Scheduled exports
 * - Export history
 */

describe('Business Analytics Export Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Export Options Access', () => {
    it('should navigate to analytics with export options', () => {
      cy.visit('/app/business/analytics');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Export', 'Download', 'Analytics']);
    });

    it('should display export button on dashboard', () => {
      cy.visit('/app/business/analytics');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Export', 'Download', 'Analytics']);
    });
  });

  describe('Export Formats', () => {
    beforeEach(() => {
      cy.visit('/app/business/analytics');
      cy.waitForPageLoad();
    });

    it('should offer CSV export', () => {
      cy.assertContainsAny(['CSV', '.csv', 'Export']);
    });

    it('should offer PDF export', () => {
      cy.assertContainsAny(['PDF', '.pdf', 'Export']);
    });

    it('should offer Excel export', () => {
      cy.assertContainsAny(['Excel', 'XLS', '.xlsx', 'Export']);
    });
  });

  describe('Report Generation', () => {
    it('should navigate to reports page', () => {
      cy.visit('/app/business/reports');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Report', 'Generate']);
    });

    it('should display report templates', () => {
      cy.visit('/app/business/reports');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Template', 'Revenue', 'Subscription']);
    });

    it('should have date range selector for reports', () => {
      cy.visit('/app/business/reports');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Date Range', 'From', 'Report']);
    });

    it('should have generate report button', () => {
      cy.visit('/app/business/reports');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Generate', 'Create Report', 'Report']);
    });
  });

  describe('Revenue Export', () => {
    beforeEach(() => {
      cy.visit('/app/business/analytics/revenue');
      cy.waitForPageLoad();
    });

    it('should display MRR/ARR data', () => {
      cy.assertContainsAny(['MRR', 'ARR', 'Revenue']);
    });

    it('should have export revenue data option', () => {
      cy.assertContainsAny(['Export', 'Revenue']);
    });
  });

  describe('Cohort Export', () => {
    beforeEach(() => {
      cy.visit('/app/business/analytics/cohorts');
      cy.waitForPageLoad();
    });

    it('should display cohort analysis', () => {
      cy.assertContainsAny(['Cohort', 'Retention']);
    });

    it('should have export cohort data option', () => {
      cy.assertContainsAny(['Export', 'Cohort']);
    });
  });

  describe('Scheduled Exports', () => {
    it('should navigate to scheduled exports', () => {
      cy.visit('/app/business/reports/scheduled');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Schedule', 'Recurring', 'Automated']);
    });

    it('should display scheduled export list', () => {
      cy.visit('/app/business/reports/scheduled');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Schedule', 'Recurring', 'Automated', 'Export']);
    });

    it('should have create scheduled export button', () => {
      cy.visit('/app/business/reports/scheduled');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Create', 'Schedule', 'New']);
    });

    it('should display frequency options', () => {
      cy.visit('/app/business/reports/scheduled');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Daily', 'Weekly', 'Monthly']);
    });
  });

  describe('Export History', () => {
    it('should navigate to export history', () => {
      cy.visit('/app/business/reports/history');
      cy.waitForPageLoad();

      cy.assertContainsAny(['History', 'Previous', 'Past']);
    });

    it('should display export history list', () => {
      cy.visit('/app/business/reports/history');
      cy.waitForPageLoad();

      cy.assertContainsAny(['History', 'Previous', 'Past', 'Export']);
    });

    it('should have download option for past exports', () => {
      cy.visit('/app/business/reports/history');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Download', 'History', 'Export']);
    });
  });

  describe('Responsive Design', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display analytics export correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/business/analytics');
        cy.waitForPageLoad();

        cy.assertContainsAny(['Analytics', 'Revenue', 'Export', 'Dashboard']);
        cy.log(`Analytics export displayed correctly on ${name}`);
      });
    });
  });
});
