/// <reference types="cypress" />

/**
 * System Alerts Tests
 *
 * Tests for System Alerts functionality including:
 * - Alert dashboard
 * - Alert configuration
 * - Alert rules
 * - Alert history
 * - Alert notifications
 * - Alert acknowledgment
 */

describe('System Alerts Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Alert Dashboard', () => {
    it('should navigate to alerts dashboard', () => {
      cy.visit('/app/system/alerts');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Alert', 'Warning', 'Critical']);
    });

    it('should display active alerts count', () => {
      cy.visit('/app/system/alerts');
      cy.waitForPageLoad();
      cy.assertContainsAny(['active', 'alert']);
    });

    it('should display alert severity levels', () => {
      cy.visit('/app/system/alerts');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Critical', 'Warning', 'Info', 'Severity']);
    });

    it('should display alert list', () => {
      cy.visit('/app/system/alerts');
      cy.waitForPageLoad();
      cy.assertContainsAny(['No alerts']);
    });
  });

  describe('Alert Details', () => {
    beforeEach(() => {
      cy.visit('/app/system/alerts');
      cy.waitForPageLoad();
    });

    it('should display alert source', () => {
      cy.assertContainsAny(['Source', 'Service', 'Component']);
    });

    it('should display alert timestamp', () => {
      cy.assertContainsAny(['ago', 'Time']);
    });

    it('should display alert description', () => {
      cy.assertContainsAny(['Description']);
    });

    it('should display affected resources', () => {
      cy.assertContainsAny(['Resource', 'Affected', 'Target']);
    });
  });

  describe('Alert Configuration', () => {
    it('should navigate to alert configuration', () => {
      cy.visit('/app/system/alerts/config');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Configuration', 'Settings', 'Rules']);
    });

    it('should have create alert rule button', () => {
      cy.visit('/app/system/alerts/config');
      cy.waitForPageLoad();
      cy.assertHasElement(['button:contains("Create")', 'button:contains("Add")', 'button:contains("New")']);
    });

    it('should display alert thresholds', () => {
      cy.visit('/app/system/alerts/config');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Threshold', '%', 'Limit']);
    });

    it('should display notification channels', () => {
      cy.visit('/app/system/alerts/config');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Email', 'Slack', 'Webhook', 'Channel']);
    });
  });

  describe('Alert Rules', () => {
    beforeEach(() => {
      cy.visit('/app/system/alerts/rules');
      cy.waitForPageLoad();
    });

    it('should display alert rules list', () => {
      cy.assertContainsAny(['Rule']);
    });

    it('should display rule status', () => {
      cy.assertContainsAny(['Active', 'Disabled', 'Status']);
    });

    it('should have enable/disable rule toggle', () => {
      cy.assertHasElement(['input[type="checkbox"]', '[role="switch"]']);
    });

    it('should have edit rule option', () => {
      cy.assertContainsAny(['Edit']);
    });

    it('should have delete rule option', () => {
      cy.assertContainsAny(['Delete']);
    });
  });

  describe('Alert History', () => {
    it('should navigate to alert history', () => {
      cy.visit('/app/system/alerts/history');
      cy.waitForPageLoad();
      cy.assertContainsAny(['History', 'Past', 'Archive']);
    });

    it('should display historical alerts', () => {
      cy.visit('/app/system/alerts/history');
      cy.waitForPageLoad();
      cy.assertHasElement(['table', '[data-testid="history-list"]']);
    });

    it('should have filter by severity', () => {
      cy.visit('/app/system/alerts/history');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Severity']);
    });

    it('should have date range filter', () => {
      cy.visit('/app/system/alerts/history');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Date']);
    });

    it('should display resolution status', () => {
      cy.visit('/app/system/alerts/history');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Resolved', 'Acknowledged', 'Closed']);
    });
  });

  describe('Alert Acknowledgment', () => {
    beforeEach(() => {
      cy.visit('/app/system/alerts');
      cy.waitForPageLoad();
    });

    it('should have acknowledge button', () => {
      cy.assertContainsAny(['Acknowledge']);
    });

    it('should have resolve button', () => {
      cy.assertContainsAny(['Resolve']);
    });

    it('should have silence option', () => {
      cy.assertContainsAny(['Silence']);
    });

    it('should display acknowledged by info', () => {
      cy.assertContainsAny(['Acknowledged by', 'User']);
    });
  });

  describe('Alert Notifications', () => {
    it('should navigate to alert notification settings', () => {
      cy.visit('/app/system/alerts/notifications');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Notification', 'Alert', 'Channel']);
    });

    it('should have email notification toggle', () => {
      cy.visit('/app/system/alerts/notifications');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Email']);
    });

    it('should have Slack integration', () => {
      cy.visit('/app/system/alerts/notifications');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Slack']);
    });

    it('should have webhook notification option', () => {
      cy.visit('/app/system/alerts/notifications');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Webhook', 'HTTP', 'URL']);
    });
  });

  describe('Alert Metrics', () => {
    it('should display alert statistics', () => {
      cy.visit('/app/system/alerts');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Total', 'Average', 'Statistics']);
    });

    it('should display mean time to resolve', () => {
      cy.visit('/app/system/alerts');
      cy.waitForPageLoad();
      cy.assertContainsAny(['MTTR', 'Mean time', 'Resolution time']);
    });

    it('should display alerts trend chart', () => {
      cy.visit('/app/system/alerts');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Trend']);
    });
  });

  describe('Responsive Design', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display alerts correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/system/alerts');
        cy.waitForPageLoad();

        cy.assertContainsAny(['Alerts', 'System', 'Warning']);
        cy.log(`Alerts displayed correctly on ${name}`);
      });
    });
  });
});
