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
      cy.assertContainsAny(['Usage', 'Consumption', 'Metering']);
    });

    it('should display current usage summary', () => {
      cy.visit('/app/business/usage');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Current', 'Total']);
      cy.assertHasElement(['[data-testid="usage-summary"]', 'body']);
    });

    it('should display usage by resource type', () => {
      cy.visit('/app/business/usage');
      cy.waitForPageLoad();
      cy.assertContainsAny(['API', 'Storage', 'Compute', 'Bandwidth']);
    });

    it('should display usage trends chart', () => {
      cy.visit('/app/business/usage');
      cy.waitForPageLoad();
      cy.assertHasElement(['canvas', 'svg', '[data-testid="usage-chart"]']);
      cy.assertContainsAny(['Trend']);
    });
  });

  describe('Usage Meters', () => {
    beforeEach(() => {
      cy.visit('/app/business/usage/meters');
      cy.waitForPageLoad();
    });

    it('should display meter list', () => {
      cy.assertContainsAny(['Meter']);
      cy.assertHasElement(['table', '[data-testid="meters-list"]']).should('exist');
    });

    it('should have create meter button', () => {
      cy.get('button:contains("Create"), button:contains("Add"), button:contains("New")').should('exist');
    });

    it('should display meter status', () => {
      cy.assertContainsAny(['Active', 'Paused', 'Status']);
    });

    it('should display meter type', () => {
      cy.assertContainsAny(['Counter', 'Gauge', 'Sum', 'Type']);
    });
  });

  describe('Meter Configuration', () => {
    it('should navigate to meter configuration', () => {
      cy.visit('/app/business/usage/meters/new');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Configure', 'Create', 'Meter']);
    });

    it('should have meter name field', () => {
      cy.visit('/app/business/usage/meters/new');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Name']);
      cy.assertHasElement(['input[name*="name"]', 'input[placeholder*="name"]']).should('exist');
    });

    it('should have aggregation type selector', () => {
      cy.visit('/app/business/usage/meters/new');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Aggregation', 'Sum', 'Count', 'Max']);
    });

    it('should have billing dimension options', () => {
      cy.visit('/app/business/usage/meters/new');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Dimension', 'Group by', 'Filter']);
    });
  });

  describe('Usage Tracking', () => {
    beforeEach(() => {
      cy.visit('/app/business/usage/tracking');
      cy.waitForPageLoad();
    });

    it('should display real-time usage', () => {
      cy.assertContainsAny(['Real-time', 'Live', 'Current']);
    });

    it('should display usage events', () => {
      cy.assertContainsAny(['Event']);
      cy.assertHasElement(['table', '[data-testid="usage-events"]']).should('exist');
    });

    it('should have time range selector', () => {
      cy.assertContainsAny(['Hour', 'Day', 'Week', 'Month']);
    });

    it('should display usage by customer', () => {
      cy.assertContainsAny(['Customer', 'Account', 'User']);
    });
  });

  describe('Quota Management', () => {
    beforeEach(() => {
      cy.visit('/app/business/usage/quotas');
      cy.waitForPageLoad();
    });

    it('should display quota list', () => {
      cy.assertContainsAny(['Quota', 'Limit']);
      cy.assertHasElement(['[data-testid="quota-list"]', 'body']);
    });

    it('should display quota progress', () => {
      cy.assertContainsAny(['%']);
      cy.assertHasElement(['progress', '[role="progressbar"]', '.progress']).should('exist');
    });

    it('should have set quota button', () => {
      cy.get('button:contains("Set"), button:contains("Edit"), button:contains("Quota")').should('exist');
    });

    it('should display overage policy', () => {
      cy.assertContainsAny(['Overage', 'Exceed', 'Policy']);
    });
  });

  describe('Usage Alerts', () => {
    beforeEach(() => {
      cy.visit('/app/business/usage/alerts');
      cy.waitForPageLoad();
    });

    it('should display alert list', () => {
      cy.assertContainsAny(['Alert']);
      cy.assertHasElement(['[data-testid="alerts-list"]', 'body']);
    });

    it('should have create alert button', () => {
      cy.get('button:contains("Create"), button:contains("Add"), button:contains("New")').should('exist');
    });

    it('should display threshold options', () => {
      cy.assertContainsAny(['Threshold', '80%', '90%', '100%']);
    });

    it('should display notification channels', () => {
      cy.assertContainsAny(['Email', 'Slack', 'Webhook']);
    });
  });

  describe('Usage Reports', () => {
    beforeEach(() => {
      cy.visit('/app/business/usage/reports');
      cy.waitForPageLoad();
    });

    it('should display report types', () => {
      cy.assertContainsAny(['Report', 'Summary', 'Detail']);
    });

    it('should have generate report button', () => {
      cy.get('button:contains("Generate"), button:contains("Create"), button:contains("Run")').should('exist');
    });

    it('should have export options', () => {
      cy.assertContainsAny(['Export', 'CSV', 'PDF']);
    });

    it('should have schedule report option', () => {
      cy.assertContainsAny(['Schedule', 'Recurring', 'Automatic']);
    });
  });

  describe('Billing Integration', () => {
    it('should display usage-based billing info', () => {
      cy.visit('/app/business/usage');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Billing', 'Cost', 'Price']);
    });

    it('should display estimated charges', () => {
      cy.visit('/app/business/usage');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Estimated', 'Projected', '$']);
    });

    it('should link to invoice', () => {
      cy.visit('/app/business/usage');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Invoice']);
      cy.assertHasElement(['a[href*="invoice"]', 'button:contains("Invoice")']);
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

        cy.assertContainsAny(['Usage', 'Metering', 'Dashboard']);
      });
    });
  });
});
