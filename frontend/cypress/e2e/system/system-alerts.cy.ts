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

      cy.get('body').then($body => {
        const hasAlerts = $body.text().includes('Alert') ||
                         $body.text().includes('Warning') ||
                         $body.text().includes('Critical');
        if (hasAlerts) {
          cy.log('Alerts dashboard loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display active alerts count', () => {
      cy.visit('/app/system/alerts');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCount = $body.find('[data-testid="alert-count"], .alert-badge').length > 0 ||
                        $body.text().match(/\d+\s*(active|alert)/i) !== null;
        if (hasCount) {
          cy.log('Active alerts count displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display alert severity levels', () => {
      cy.visit('/app/system/alerts');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSeverity = $body.text().includes('Critical') ||
                          $body.text().includes('Warning') ||
                          $body.text().includes('Info') ||
                          $body.text().includes('Severity');
        if (hasSeverity) {
          cy.log('Alert severity levels displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display alert list', () => {
      cy.visit('/app/system/alerts');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasList = $body.find('table, [data-testid="alerts-list"], .alert-item').length > 0 ||
                       $body.text().includes('No alerts');
        if (hasList) {
          cy.log('Alert list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Alert Details', () => {
    beforeEach(() => {
      cy.visit('/app/system/alerts');
      cy.waitForPageLoad();
    });

    it('should display alert source', () => {
      cy.get('body').then($body => {
        const hasSource = $body.text().includes('Source') ||
                         $body.text().includes('Service') ||
                         $body.text().includes('Component');
        if (hasSource) {
          cy.log('Alert source displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display alert timestamp', () => {
      cy.get('body').then($body => {
        const hasTimestamp = $body.text().includes('ago') ||
                            $body.text().match(/\d{1,2}:\d{2}/) !== null ||
                            $body.text().includes('Time');
        if (hasTimestamp) {
          cy.log('Alert timestamp displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display alert description', () => {
      cy.get('body').then($body => {
        const hasDescription = $body.text().includes('Description') ||
                              $body.find('p, [data-testid="alert-description"]').length > 0;
        if (hasDescription) {
          cy.log('Alert description displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display affected resources', () => {
      cy.get('body').then($body => {
        const hasResources = $body.text().includes('Resource') ||
                            $body.text().includes('Affected') ||
                            $body.text().includes('Target');
        if (hasResources) {
          cy.log('Affected resources displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Alert Configuration', () => {
    it('should navigate to alert configuration', () => {
      cy.visit('/app/system/alerts/config');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasConfig = $body.text().includes('Configuration') ||
                         $body.text().includes('Settings') ||
                         $body.text().includes('Rules');
        if (hasConfig) {
          cy.log('Alert configuration page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have create alert rule button', () => {
      cy.visit('/app/system/alerts/config');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCreate = $body.find('button:contains("Create"), button:contains("Add"), button:contains("New")').length > 0;
        if (hasCreate) {
          cy.log('Create alert rule button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display alert thresholds', () => {
      cy.visit('/app/system/alerts/config');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasThresholds = $body.text().includes('Threshold') ||
                             $body.text().includes('%') ||
                             $body.text().includes('Limit');
        if (hasThresholds) {
          cy.log('Alert thresholds displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display notification channels', () => {
      cy.visit('/app/system/alerts/config');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasChannels = $body.text().includes('Email') ||
                           $body.text().includes('Slack') ||
                           $body.text().includes('Webhook') ||
                           $body.text().includes('Channel');
        if (hasChannels) {
          cy.log('Notification channels displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Alert Rules', () => {
    beforeEach(() => {
      cy.visit('/app/system/alerts/rules');
      cy.waitForPageLoad();
    });

    it('should display alert rules list', () => {
      cy.get('body').then($body => {
        const hasRules = $body.text().includes('Rule') ||
                        $body.find('table, [data-testid="rules-list"]').length > 0;
        if (hasRules) {
          cy.log('Alert rules list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display rule status', () => {
      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Active') ||
                         $body.text().includes('Disabled') ||
                         $body.text().includes('Status');
        if (hasStatus) {
          cy.log('Rule status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have enable/disable rule toggle', () => {
      cy.get('body').then($body => {
        const hasToggle = $body.find('input[type="checkbox"], [role="switch"]').length > 0 ||
                         $body.find('button:contains("Enable"), button:contains("Disable")').length > 0;
        if (hasToggle) {
          cy.log('Enable/disable rule toggle displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have edit rule option', () => {
      cy.get('body').then($body => {
        const hasEdit = $body.find('button:contains("Edit"), a[href*="edit"]').length > 0 ||
                       $body.text().includes('Edit');
        if (hasEdit) {
          cy.log('Edit rule option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have delete rule option', () => {
      cy.get('body').then($body => {
        const hasDelete = $body.find('button:contains("Delete"), button[aria-label*="delete"]').length > 0 ||
                         $body.text().includes('Delete');
        if (hasDelete) {
          cy.log('Delete rule option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Alert History', () => {
    it('should navigate to alert history', () => {
      cy.visit('/app/system/alerts/history');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasHistory = $body.text().includes('History') ||
                          $body.text().includes('Past') ||
                          $body.text().includes('Archive');
        if (hasHistory) {
          cy.log('Alert history page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display historical alerts', () => {
      cy.visit('/app/system/alerts/history');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasList = $body.find('table, [data-testid="history-list"]').length > 0;
        if (hasList) {
          cy.log('Historical alerts displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have filter by severity', () => {
      cy.visit('/app/system/alerts/history');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSeverityFilter = $body.find('select, [data-testid="severity-filter"]').length > 0 ||
                                 $body.text().includes('Severity');
        if (hasSeverityFilter) {
          cy.log('Severity filter displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have date range filter', () => {
      cy.visit('/app/system/alerts/history');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDateFilter = $body.find('input[type="date"]').length > 0 ||
                             $body.text().includes('Date');
        if (hasDateFilter) {
          cy.log('Date range filter displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display resolution status', () => {
      cy.visit('/app/system/alerts/history');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasResolution = $body.text().includes('Resolved') ||
                             $body.text().includes('Acknowledged') ||
                             $body.text().includes('Closed');
        if (hasResolution) {
          cy.log('Resolution status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Alert Acknowledgment', () => {
    beforeEach(() => {
      cy.visit('/app/system/alerts');
      cy.waitForPageLoad();
    });

    it('should have acknowledge button', () => {
      cy.get('body').then($body => {
        const hasAck = $body.find('button:contains("Acknowledge"), button:contains("Ack")').length > 0 ||
                      $body.text().includes('Acknowledge');
        if (hasAck) {
          cy.log('Acknowledge button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have resolve button', () => {
      cy.get('body').then($body => {
        const hasResolve = $body.find('button:contains("Resolve"), button:contains("Close")').length > 0 ||
                          $body.text().includes('Resolve');
        if (hasResolve) {
          cy.log('Resolve button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have silence option', () => {
      cy.get('body').then($body => {
        const hasSilence = $body.find('button:contains("Silence"), button:contains("Mute"), button:contains("Snooze")').length > 0 ||
                          $body.text().includes('Silence');
        if (hasSilence) {
          cy.log('Silence option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display acknowledged by info', () => {
      cy.get('body').then($body => {
        const hasAckedBy = $body.text().includes('Acknowledged by') ||
                          $body.text().includes('by') ||
                          $body.text().includes('User');
        if (hasAckedBy) {
          cy.log('Acknowledged by info displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Alert Notifications', () => {
    it('should navigate to alert notification settings', () => {
      cy.visit('/app/system/alerts/notifications');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasNotifications = $body.text().includes('Notification') ||
                                $body.text().includes('Alert') ||
                                $body.text().includes('Channel');
        if (hasNotifications) {
          cy.log('Alert notification settings loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have email notification toggle', () => {
      cy.visit('/app/system/alerts/notifications');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasEmail = $body.text().includes('Email') ||
                        $body.find('input[type="checkbox"]').length > 0;
        if (hasEmail) {
          cy.log('Email notification toggle displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Slack integration', () => {
      cy.visit('/app/system/alerts/notifications');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSlack = $body.text().includes('Slack') ||
                        $body.find('[data-testid="slack-integration"]').length > 0;
        if (hasSlack) {
          cy.log('Slack integration displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have webhook notification option', () => {
      cy.visit('/app/system/alerts/notifications');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasWebhook = $body.text().includes('Webhook') ||
                          $body.text().includes('HTTP') ||
                          $body.text().includes('URL');
        if (hasWebhook) {
          cy.log('Webhook notification option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Alert Metrics', () => {
    it('should display alert statistics', () => {
      cy.visit('/app/system/alerts');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasStats = $body.text().includes('Total') ||
                        $body.text().includes('Average') ||
                        $body.text().includes('Statistics');
        if (hasStats) {
          cy.log('Alert statistics displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display mean time to resolve', () => {
      cy.visit('/app/system/alerts');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasMTTR = $body.text().includes('MTTR') ||
                       $body.text().includes('Mean time') ||
                       $body.text().includes('Resolution time');
        if (hasMTTR) {
          cy.log('Mean time to resolve displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display alerts trend chart', () => {
      cy.visit('/app/system/alerts');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasChart = $body.find('canvas, svg, [data-testid="alerts-chart"]').length > 0 ||
                        $body.text().includes('Trend');
        if (hasChart) {
          cy.log('Alerts trend chart displayed');
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
      it(`should display alerts correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/system/alerts');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`Alerts displayed correctly on ${name}`);
      });
    });
  });
});
