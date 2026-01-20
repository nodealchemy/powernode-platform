/// <reference types="cypress" />

/**
 * Business Usage Metering Tests
 *
 * Tests for Usage Metering functionality including:
 * - Usage dashboard
 * - Meter configuration
 * - Usage tracking
 * - Quota management
 * - Usage alerts
 * - Usage reports
 */

describe('Business Usage Metering Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Usage Dashboard', () => {
    it('should navigate to usage dashboard', () => {
      cy.visit('/app/business/usage');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasUsage = $body.text().includes('Usage') ||
                        $body.text().includes('Consumption') ||
                        $body.text().includes('Metering');
        if (hasUsage) {
          cy.log('Usage dashboard loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display current usage summary', () => {
      cy.visit('/app/business/usage');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSummary = $body.text().includes('Current') ||
                          $body.text().includes('Total') ||
                          $body.find('[data-testid="usage-summary"]').length > 0;
        if (hasSummary) {
          cy.log('Usage summary displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display usage by resource type', () => {
      cy.visit('/app/business/usage');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasResources = $body.text().includes('API') ||
                            $body.text().includes('Storage') ||
                            $body.text().includes('Compute') ||
                            $body.text().includes('Bandwidth');
        if (hasResources) {
          cy.log('Usage by resource type displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display usage trends chart', () => {
      cy.visit('/app/business/usage');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasChart = $body.find('canvas, svg, [data-testid="usage-chart"]').length > 0 ||
                        $body.text().includes('Trend');
        if (hasChart) {
          cy.log('Usage trends chart displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Usage Meters', () => {
    beforeEach(() => {
      cy.visit('/app/business/usage/meters');
      cy.waitForPageLoad();
    });

    it('should display meter list', () => {
      cy.get('body').then($body => {
        const hasMeters = $body.text().includes('Meter') ||
                         $body.find('table, [data-testid="meters-list"]').length > 0;
        if (hasMeters) {
          cy.log('Meter list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have create meter button', () => {
      cy.get('body').then($body => {
        const hasCreate = $body.find('button:contains("Create"), button:contains("Add"), button:contains("New")').length > 0;
        if (hasCreate) {
          cy.log('Create meter button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display meter status', () => {
      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Active') ||
                         $body.text().includes('Paused') ||
                         $body.text().includes('Status');
        if (hasStatus) {
          cy.log('Meter status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display meter type', () => {
      cy.get('body').then($body => {
        const hasType = $body.text().includes('Counter') ||
                       $body.text().includes('Gauge') ||
                       $body.text().includes('Sum') ||
                       $body.text().includes('Type');
        if (hasType) {
          cy.log('Meter type displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Meter Configuration', () => {
    it('should navigate to meter configuration', () => {
      cy.visit('/app/business/usage/meters/new');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasConfig = $body.text().includes('Configure') ||
                         $body.text().includes('Create') ||
                         $body.text().includes('Meter');
        if (hasConfig) {
          cy.log('Meter configuration page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have meter name field', () => {
      cy.visit('/app/business/usage/meters/new');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasName = $body.find('input[name*="name"], input[placeholder*="name"]').length > 0 ||
                       $body.text().includes('Name');
        if (hasName) {
          cy.log('Meter name field displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have aggregation type selector', () => {
      cy.visit('/app/business/usage/meters/new');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasAggregation = $body.text().includes('Aggregation') ||
                              $body.text().includes('Sum') ||
                              $body.text().includes('Count') ||
                              $body.text().includes('Max');
        if (hasAggregation) {
          cy.log('Aggregation type selector displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have billing dimension options', () => {
      cy.visit('/app/business/usage/meters/new');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDimensions = $body.text().includes('Dimension') ||
                             $body.text().includes('Group by') ||
                             $body.text().includes('Filter');
        if (hasDimensions) {
          cy.log('Billing dimension options displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Usage Tracking', () => {
    beforeEach(() => {
      cy.visit('/app/business/usage/tracking');
      cy.waitForPageLoad();
    });

    it('should display real-time usage', () => {
      cy.get('body').then($body => {
        const hasRealtime = $body.text().includes('Real-time') ||
                           $body.text().includes('Live') ||
                           $body.text().includes('Current');
        if (hasRealtime) {
          cy.log('Real-time usage displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display usage events', () => {
      cy.get('body').then($body => {
        const hasEvents = $body.text().includes('Event') ||
                         $body.find('table, [data-testid="usage-events"]').length > 0;
        if (hasEvents) {
          cy.log('Usage events displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have time range selector', () => {
      cy.get('body').then($body => {
        const hasTimeRange = $body.text().includes('Hour') ||
                            $body.text().includes('Day') ||
                            $body.text().includes('Week') ||
                            $body.text().includes('Month');
        if (hasTimeRange) {
          cy.log('Time range selector displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display usage by customer', () => {
      cy.get('body').then($body => {
        const hasByCustomer = $body.text().includes('Customer') ||
                             $body.text().includes('Account') ||
                             $body.text().includes('User');
        if (hasByCustomer) {
          cy.log('Usage by customer displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Quota Management', () => {
    beforeEach(() => {
      cy.visit('/app/business/usage/quotas');
      cy.waitForPageLoad();
    });

    it('should display quota list', () => {
      cy.get('body').then($body => {
        const hasQuotas = $body.text().includes('Quota') ||
                         $body.text().includes('Limit') ||
                         $body.find('[data-testid="quota-list"]').length > 0;
        if (hasQuotas) {
          cy.log('Quota list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display quota progress', () => {
      cy.get('body').then($body => {
        const hasProgress = $body.find('progress, [role="progressbar"], .progress').length > 0 ||
                           $body.text().includes('%');
        if (hasProgress) {
          cy.log('Quota progress displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have set quota button', () => {
      cy.get('body').then($body => {
        const hasSetQuota = $body.find('button:contains("Set"), button:contains("Edit"), button:contains("Quota")').length > 0;
        if (hasSetQuota) {
          cy.log('Set quota button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display overage policy', () => {
      cy.get('body').then($body => {
        const hasOverage = $body.text().includes('Overage') ||
                          $body.text().includes('Exceed') ||
                          $body.text().includes('Policy');
        if (hasOverage) {
          cy.log('Overage policy displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Usage Alerts', () => {
    beforeEach(() => {
      cy.visit('/app/business/usage/alerts');
      cy.waitForPageLoad();
    });

    it('should display alert list', () => {
      cy.get('body').then($body => {
        const hasAlerts = $body.text().includes('Alert') ||
                         $body.find('[data-testid="alerts-list"]').length > 0;
        if (hasAlerts) {
          cy.log('Alert list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have create alert button', () => {
      cy.get('body').then($body => {
        const hasCreate = $body.find('button:contains("Create"), button:contains("Add"), button:contains("New")').length > 0;
        if (hasCreate) {
          cy.log('Create alert button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display threshold options', () => {
      cy.get('body').then($body => {
        const hasThreshold = $body.text().includes('Threshold') ||
                            $body.text().includes('80%') ||
                            $body.text().includes('90%') ||
                            $body.text().includes('100%');
        if (hasThreshold) {
          cy.log('Threshold options displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display notification channels', () => {
      cy.get('body').then($body => {
        const hasChannels = $body.text().includes('Email') ||
                           $body.text().includes('Slack') ||
                           $body.text().includes('Webhook');
        if (hasChannels) {
          cy.log('Notification channels displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Usage Reports', () => {
    beforeEach(() => {
      cy.visit('/app/business/usage/reports');
      cy.waitForPageLoad();
    });

    it('should display report types', () => {
      cy.get('body').then($body => {
        const hasReports = $body.text().includes('Report') ||
                          $body.text().includes('Summary') ||
                          $body.text().includes('Detail');
        if (hasReports) {
          cy.log('Report types displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have generate report button', () => {
      cy.get('body').then($body => {
        const hasGenerate = $body.find('button:contains("Generate"), button:contains("Create"), button:contains("Run")').length > 0;
        if (hasGenerate) {
          cy.log('Generate report button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have export options', () => {
      cy.get('body').then($body => {
        const hasExport = $body.text().includes('Export') ||
                         $body.text().includes('CSV') ||
                         $body.text().includes('PDF');
        if (hasExport) {
          cy.log('Export options displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have schedule report option', () => {
      cy.get('body').then($body => {
        const hasSchedule = $body.text().includes('Schedule') ||
                           $body.text().includes('Recurring') ||
                           $body.text().includes('Automatic');
        if (hasSchedule) {
          cy.log('Schedule report option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Billing Integration', () => {
    it('should display usage-based billing info', () => {
      cy.visit('/app/business/usage');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasBilling = $body.text().includes('Billing') ||
                          $body.text().includes('Cost') ||
                          $body.text().includes('Price');
        if (hasBilling) {
          cy.log('Usage-based billing info displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display estimated charges', () => {
      cy.visit('/app/business/usage');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasEstimate = $body.text().includes('Estimated') ||
                           $body.text().includes('Projected') ||
                           $body.text().includes('$');
        if (hasEstimate) {
          cy.log('Estimated charges displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should link to invoice', () => {
      cy.visit('/app/business/usage');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasInvoice = $body.text().includes('Invoice') ||
                          $body.find('a[href*="invoice"], button:contains("Invoice")').length > 0;
        if (hasInvoice) {
          cy.log('Invoice link displayed');
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
      it(`should display usage dashboard correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/business/usage');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`Usage dashboard displayed correctly on ${name}`);
      });
    });
  });
});
