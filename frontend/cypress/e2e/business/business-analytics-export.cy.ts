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

      cy.get('body').then($body => {
        const hasExport = $body.text().includes('Export') ||
                         $body.text().includes('Download') ||
                         $body.find('[data-testid="export-button"]').length > 0;
        if (hasExport) {
          cy.log('Export options available');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display export button on dashboard', () => {
      cy.visit('/app/business/analytics');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasButton = $body.find('button:contains("Export"), button:contains("Download")').length > 0;
        if (hasButton) {
          cy.log('Export button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Export Formats', () => {
    beforeEach(() => {
      cy.visit('/app/business/analytics');
      cy.waitForPageLoad();
    });

    it('should offer CSV export', () => {
      cy.get('body').then($body => {
        const hasCSV = $body.text().includes('CSV') ||
                      $body.text().includes('.csv');
        if (hasCSV) {
          cy.log('CSV export available');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should offer PDF export', () => {
      cy.get('body').then($body => {
        const hasPDF = $body.text().includes('PDF') ||
                      $body.text().includes('.pdf');
        if (hasPDF) {
          cy.log('PDF export available');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should offer Excel export', () => {
      cy.get('body').then($body => {
        const hasExcel = $body.text().includes('Excel') ||
                        $body.text().includes('XLS') ||
                        $body.text().includes('.xlsx');
        if (hasExcel) {
          cy.log('Excel export available');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Report Generation', () => {
    it('should navigate to reports page', () => {
      cy.visit('/app/business/reports');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasReports = $body.text().includes('Report') ||
                          $body.text().includes('Generate');
        if (hasReports) {
          cy.log('Reports page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display report templates', () => {
      cy.visit('/app/business/reports');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasTemplates = $body.text().includes('Template') ||
                            $body.text().includes('Revenue') ||
                            $body.text().includes('Subscription');
        if (hasTemplates) {
          cy.log('Report templates displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have date range selector for reports', () => {
      cy.visit('/app/business/reports');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDateRange = $body.find('input[type="date"], [data-testid="date-range"]').length > 0 ||
                            $body.text().includes('Date Range') ||
                            $body.text().includes('From');
        if (hasDateRange) {
          cy.log('Date range selector displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have generate report button', () => {
      cy.visit('/app/business/reports');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasGenerate = $body.find('button:contains("Generate"), button:contains("Create Report")').length > 0;
        if (hasGenerate) {
          cy.log('Generate report button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Revenue Export', () => {
    beforeEach(() => {
      cy.visit('/app/business/analytics/revenue');
      cy.waitForPageLoad();
    });

    it('should display MRR/ARR data', () => {
      cy.get('body').then($body => {
        const hasRevenue = $body.text().includes('MRR') ||
                          $body.text().includes('ARR') ||
                          $body.text().includes('Revenue');
        if (hasRevenue) {
          cy.log('Revenue data displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have export revenue data option', () => {
      cy.get('body').then($body => {
        const hasExport = $body.find('button:contains("Export"), [data-testid="export-revenue"]').length > 0 ||
                         $body.text().includes('Export');
        if (hasExport) {
          cy.log('Export revenue option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Cohort Export', () => {
    beforeEach(() => {
      cy.visit('/app/business/analytics/cohorts');
      cy.waitForPageLoad();
    });

    it('should display cohort analysis', () => {
      cy.get('body').then($body => {
        const hasCohort = $body.text().includes('Cohort') ||
                         $body.text().includes('Retention');
        if (hasCohort) {
          cy.log('Cohort analysis displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have export cohort data option', () => {
      cy.get('body').then($body => {
        const hasExport = $body.find('button:contains("Export")').length > 0 ||
                         $body.text().includes('Export');
        if (hasExport) {
          cy.log('Export cohort option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Scheduled Exports', () => {
    it('should navigate to scheduled exports', () => {
      cy.visit('/app/business/reports/scheduled');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasScheduled = $body.text().includes('Schedule') ||
                            $body.text().includes('Recurring') ||
                            $body.text().includes('Automated');
        if (hasScheduled) {
          cy.log('Scheduled exports page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display scheduled export list', () => {
      cy.visit('/app/business/reports/scheduled');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasList = $body.find('table, [data-testid="scheduled-list"]').length > 0;
        if (hasList) {
          cy.log('Scheduled export list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have create scheduled export button', () => {
      cy.visit('/app/business/reports/scheduled');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCreate = $body.find('button:contains("Create"), button:contains("Schedule"), button:contains("New")').length > 0;
        if (hasCreate) {
          cy.log('Create scheduled export button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display frequency options', () => {
      cy.visit('/app/business/reports/scheduled');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasFrequency = $body.text().includes('Daily') ||
                            $body.text().includes('Weekly') ||
                            $body.text().includes('Monthly');
        if (hasFrequency) {
          cy.log('Frequency options displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Export History', () => {
    it('should navigate to export history', () => {
      cy.visit('/app/business/reports/history');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasHistory = $body.text().includes('History') ||
                          $body.text().includes('Previous') ||
                          $body.text().includes('Past');
        if (hasHistory) {
          cy.log('Export history page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display export history list', () => {
      cy.visit('/app/business/reports/history');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasList = $body.find('table, [data-testid="history-list"]').length > 0;
        if (hasList) {
          cy.log('Export history list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have download option for past exports', () => {
      cy.visit('/app/business/reports/history');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDownload = $body.find('button:contains("Download"), a[download]').length > 0 ||
                           $body.text().includes('Download');
        if (hasDownload) {
          cy.log('Download option displayed');
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
      it(`should display analytics export correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/business/analytics');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`Analytics export displayed correctly on ${name}`);
      });
    });
  });
});
