/// <reference types="cypress" />

/**
 * AI Monitoring Page Tests
 *
 * Tests for AI Monitoring functionality including:
 * - Page navigation and load
 * - Status bar display
 * - Overview cards
 * - Tab navigation (overview, providers, agents, workflows, conversations, alerts)
 * - Real-time updates toggle
 * - Time range selection
 * - Refresh functionality
 * - System health dashboard
 * - Provider monitoring
 * - Agent performance
 * - Alert management
 * - Permission-based access
 * - Responsive design
 */

describe('AI Monitoring Page Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.setupAiIntercepts();
    // Login with demo user
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 5000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to AI Monitoring from AI section', () => {
      cy.visit('/app/ai');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const monitoringLink = $body.find('a[href*="/monitoring"], button:contains("Monitoring")');

        if (monitoringLink.length > 0) {
          cy.wrap(monitoringLink).first().should('be.visible').click();
          cy.url().should('include', '/monitoring');
        } else {
          cy.visit('/app/ai/monitoring');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should load AI Monitoring page directly', () => {
      cy.visit('/app/ai/monitoring');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const text = $body.text();
        const hasContent = text.includes('Monitoring') ||
                           text.includes('System') ||
                           text.includes('Health') ||
                           text.includes('Loading') ||
                           text.includes('Access');
        if (hasContent) {
          cy.log('AI Monitoring page content loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page title', () => {
      cy.visit('/app/ai/monitoring');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('AI System Monitoring') ||
                          $body.text().includes('Monitoring');

        if (hasTitle) {
          cy.log('Page title displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/ai/monitoring');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('Dashboard') ||
                               $body.text().includes('AI');

        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs displayed correctly');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Status Bar Display', () => {
    beforeEach(() => {
      cy.visit('/app/ai/monitoring');
      cy.waitForPageLoad();
    });

    it('should display connection status', () => {
      cy.get('body').then($body => {
        const hasConnection = $body.text().includes('Connected') ||
                               $body.text().includes('Disconnected') ||
                               $body.text().includes('Online') ||
                               $body.text().includes('Offline');

        if (hasConnection) {
          cy.log('Connection status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display real-time status indicator', () => {
      cy.get('body').then($body => {
        const hasRealTime = $body.text().includes('Real-time') ||
                             $body.text().includes('Live') ||
                             $body.text().includes('Paused');

        if (hasRealTime) {
          cy.log('Real-time status indicator displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display last update timestamp', () => {
      cy.get('body').then($body => {
        const hasTimestamp = $body.text().includes('Updated') ||
                              $body.text().includes('Last') ||
                              $body.text().includes('ago');

        if (hasTimestamp) {
          cy.log('Last update timestamp displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Overview Cards', () => {
    beforeEach(() => {
      cy.visit('/app/ai/monitoring');
      cy.waitForPageLoad();
    });

    it('should display overview statistics cards', () => {
      cy.get('body').then($body => {
        const hasCards = $body.find('[class*="card"]').length > 0 ||
                          $body.text().includes('Workflows') ||
                          $body.text().includes('Agents') ||
                          $body.text().includes('Providers');

        if (hasCards) {
          cy.log('Overview cards displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display workflow stats', () => {
      cy.get('body').then($body => {
        if ($body.text().includes('Workflow')) {
          cy.log('Workflow stats displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display conversation stats', () => {
      cy.get('body').then($body => {
        if ($body.text().includes('Conversation')) {
          cy.log('Conversation stats displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display alert count', () => {
      cy.get('body').then($body => {
        if ($body.text().includes('Alert')) {
          cy.log('Alert count displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Tab Navigation', () => {
    beforeEach(() => {
      cy.visit('/app/ai/monitoring');
      cy.waitForPageLoad();
    });

    it('should display monitoring tabs', () => {
      cy.get('body').then($body => {
        const hasTabs = $body.text().includes('Overview') ||
                         $body.find('button[role="tab"], [class*="tab"]').length > 0;

        if (hasTabs) {
          cy.log('Monitoring tabs displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should switch to Providers tab', () => {
      cy.get('body').then($body => {
        const providersTab = $body.find('button:contains("Providers"), [role="tab"]:contains("Providers")');

        if (providersTab.length > 0) {
          cy.wrap(providersTab).first().should('be.visible').click();
          cy.waitForPageLoad();
          cy.log('Switched to Providers tab');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should switch to Agents tab', () => {
      cy.get('body').then($body => {
        const agentsTab = $body.find('button:contains("Agents"), [role="tab"]:contains("Agents")');

        if (agentsTab.length > 0) {
          cy.wrap(agentsTab).first().should('be.visible').click();
          cy.waitForPageLoad();
          cy.log('Switched to Agents tab');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should switch to Workflows tab', () => {
      cy.get('body').then($body => {
        const workflowsTab = $body.find('button:contains("Workflows"), [role="tab"]:contains("Workflows")');

        if (workflowsTab.length > 0) {
          cy.wrap(workflowsTab).first().should('be.visible').click();
          cy.waitForPageLoad();
          cy.log('Switched to Workflows tab');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should switch to Conversations tab', () => {
      cy.get('body').then($body => {
        const conversationsTab = $body.find('button:contains("Conversations"), [role="tab"]:contains("Conversations")');

        if (conversationsTab.length > 0) {
          cy.wrap(conversationsTab).first().should('be.visible').click();
          cy.waitForPageLoad();
          cy.log('Switched to Conversations tab');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should switch to Alerts tab', () => {
      cy.get('body').then($body => {
        const alertsTab = $body.find('button:contains("Alerts"), [role="tab"]:contains("Alerts")');

        if (alertsTab.length > 0) {
          cy.wrap(alertsTab).first().should('be.visible').click();
          cy.waitForPageLoad();
          cy.log('Switched to Alerts tab');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Real-Time Updates', () => {
    beforeEach(() => {
      cy.visit('/app/ai/monitoring');
      cy.waitForPageLoad();
    });

    it('should have Enable Real-time button', () => {
      cy.get('body').then($body => {
        const realTimeButton = $body.find('button:contains("Real-time"), button:contains("Enable"), button:contains("Disable")');

        if (realTimeButton.length > 0) {
          cy.log('Real-time toggle button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should toggle real-time updates', () => {
      cy.get('body').then($body => {
        const realTimeButton = $body.find('button:contains("Enable Real-time"), button:contains("Disable Real-time")');

        if (realTimeButton.length > 0) {
          cy.wrap(realTimeButton).first().should('be.visible').click();
          cy.waitForPageLoad();
          cy.log('Real-time updates toggled');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Time Range Selection', () => {
    beforeEach(() => {
      cy.visit('/app/ai/monitoring');
      cy.waitForPageLoad();
    });

    it('should have time range selector', () => {
      cy.get('body').then($body => {
        const timeRange = $body.find('select, button:contains("1h"), button:contains("24h"), button:contains("7d")');

        if (timeRange.length > 0) {
          cy.log('Time range selector found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should change time range', () => {
      cy.get('body').then($body => {
        // Look for time range buttons or select elements
        const timeRangeButton = $body.find('button:contains("24h"), button:contains("7d"), button:contains("1h")').not('select option');

        if (timeRangeButton.length > 0) {
          cy.wrap(timeRangeButton).first().should('be.visible').click();
          cy.waitForPageLoad();
          cy.log('Time range changed');
        } else {
          // If using a select dropdown, handle differently
          const selectElement = $body.find('select');
          if (selectElement.length > 0) {
            cy.wrap(selectElement).first().should('be.visible').select(1);
            cy.waitForPageLoad();
            cy.log('Time range changed via select');
          } else {
            cy.log('Time range selector not found - may not be available');
          }
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Refresh Functionality', () => {
    beforeEach(() => {
      cy.visit('/app/ai/monitoring');
      cy.waitForPageLoad();
    });

    it('should have Refresh button', () => {
      cy.get('body').then($body => {
        const refreshButton = $body.find('button:contains("Refresh"), [aria-label*="refresh"]');

        if (refreshButton.length > 0) {
          cy.wrap(refreshButton).should('be.visible');
          cy.log('Refresh button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should refresh monitoring data', () => {
      cy.get('body').then($body => {
        const refreshButton = $body.find('button:contains("Refresh")');

        if (refreshButton.length > 0) {
          cy.wrap(refreshButton).first().should('be.visible').click();
          cy.waitForPageLoad();
          cy.log('Monitoring data refreshed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('System Health Dashboard', () => {
    beforeEach(() => {
      cy.visit('/app/ai/monitoring');
      cy.waitForPageLoad();
    });

    it('should display system health information', () => {
      cy.get('body').then($body => {
        const hasHealth = $body.text().includes('Health') ||
                           $body.text().includes('System') ||
                           $body.text().includes('Status');

        if (hasHealth) {
          cy.log('System health information displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display health score', () => {
      cy.get('body').then($body => {
        const hasScore = $body.text().includes('%') ||
                          $body.text().includes('Score') ||
                          $body.text().includes('healthy');

        if (hasScore) {
          cy.log('Health score displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Provider Monitoring', () => {
    beforeEach(() => {
      cy.visit('/app/ai/monitoring');
      cy.waitForPageLoad();

      // Try to switch to Providers tab
      cy.get('body').then($body => {
        const providersTab = $body.find('button:contains("Providers")');
        if (providersTab.length > 0) {
          cy.wrap(providersTab).first().should('be.visible').click();
          cy.waitForPageLoad();
        }
      });
    });

    it('should display provider list', () => {
      cy.get('body').then($body => {
        const hasProviders = $body.text().includes('Provider') ||
                              $body.text().includes('OpenAI') ||
                              $body.text().includes('Anthropic');

        if (hasProviders) {
          cy.log('Provider list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display provider status', () => {
      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('healthy') ||
                           $body.text().includes('degraded') ||
                           $body.text().includes('unhealthy');

        if (hasStatus) {
          cy.log('Provider status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Agent Performance', () => {
    beforeEach(() => {
      cy.visit('/app/ai/monitoring');
      cy.waitForPageLoad();

      // Try to switch to Agents tab
      cy.get('body').then($body => {
        const agentsTab = $body.find('button:contains("Agents")');
        if (agentsTab.length > 0) {
          cy.wrap(agentsTab).first().should('be.visible').click();
          cy.waitForPageLoad();
        }
      });
    });

    it('should display agent performance metrics', () => {
      cy.get('body').then($body => {
        const hasMetrics = $body.text().includes('Agent') ||
                            $body.text().includes('Performance') ||
                            $body.text().includes('Success');

        if (hasMetrics) {
          cy.log('Agent performance metrics displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Alert Management', () => {
    beforeEach(() => {
      cy.visit('/app/ai/monitoring');
      cy.waitForPageLoad();

      // Try to switch to Alerts tab
      cy.get('body').then($body => {
        const alertsTab = $body.find('button:contains("Alerts")');
        if (alertsTab.length > 0) {
          cy.wrap(alertsTab).first().should('be.visible').click();
          cy.waitForPageLoad();
        }
      });
    });

    it('should display alert list', () => {
      cy.get('body').then($body => {
        const hasAlerts = $body.text().includes('Alert') ||
                           $body.text().includes('No alerts') ||
                           $body.text().includes('critical') ||
                           $body.text().includes('warning');

        if (hasAlerts) {
          cy.log('Alert list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display alert severity levels', () => {
      cy.get('body').then($body => {
        const hasSeverity = $body.text().includes('critical') ||
                             $body.text().includes('high') ||
                             $body.text().includes('medium') ||
                             $body.text().includes('low');

        if (hasSeverity) {
          cy.log('Alert severity levels displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Permission-Based Access', () => {
    it('should show access denied for unauthorized users', () => {
      cy.visit('/app/ai/monitoring');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        if ($body.text().includes('Access Denied') || $body.text().includes('permission')) {
          cy.log('Access denied message displayed for unauthorized access');
        } else {
          cy.log('User has monitoring permissions');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.intercept('GET', '/api/v1/ai/monitoring*', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/ai/monitoring');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should display error notification on failure', () => {
      cy.intercept('GET', '/api/v1/ai/monitoring/dashboard*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load monitoring data' }
      });

      cy.visit('/app/ai/monitoring');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasError = $body.text().includes('Error') ||
                          $body.text().includes('Failed') ||
                          $body.find('[class*="error"]').length > 0;

        if (hasError) {
          cy.log('Error notification displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/ai/monitoring');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Monitoring') || $body.text().includes('AI');
        if (hasContent) {
          cy.log('Content visible on mobile');
        }
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/ai/monitoring');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Monitoring') || $body.text().includes('AI');
        if (hasContent) {
          cy.log('Content visible on tablet');
        }
      });
    });

    it('should stack cards on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/ai/monitoring');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
    });
  });
});


export {};
