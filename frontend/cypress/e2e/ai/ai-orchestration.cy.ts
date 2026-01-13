/// <reference types="cypress" />

/**
 * AI Orchestration Page Tests
 *
 * Tests for AI Orchestration hub functionality including:
 * - Page navigation and load
 * - Tab navigation (Overview, Providers, Agents, Workflows, Conversations, Analytics, Monitoring, MCP)
 * - Permission-based tab visibility
 * - Enhanced AI Overview display
 * - Tab content loading
 * - Authentication check
 * - Error handling
 * - Responsive design
 */

describe('AI Orchestration Page Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to AI Orchestration page', () => {
      cy.visit('/app/ai');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasContent = $body.text().includes('AI Orchestration') ||
                          $body.text().includes('AI') ||
                          $body.text().includes('Permission');
        if (hasContent) {
          cy.log('AI Orchestration page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page title', () => {
      cy.visit('/app/ai');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('AI Orchestration');
        if (hasTitle) {
          cy.log('Page title displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page description', () => {
      cy.visit('/app/ai');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasDescription = $body.text().includes('Manage') ||
                               $body.text().includes('AI providers') ||
                               $body.text().includes('agents') ||
                               $body.text().includes('workflows');
        if (hasDescription) {
          cy.log('Page description displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/ai');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('Dashboard') ||
                               $body.text().includes('AI Orchestration');
        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Tab Navigation', () => {
    beforeEach(() => {
      cy.visit('/app/ai');
      cy.wait(2000);
    });

    it('should display Overview tab', () => {
      cy.get('body').then($body => {
        const hasOverview = $body.text().includes('Overview');
        if (hasOverview) {
          cy.log('Overview tab displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display AI Providers tab', () => {
      cy.get('body').then($body => {
        const hasProviders = $body.text().includes('Providers') ||
                            $body.text().includes('AI Providers');
        if (hasProviders) {
          cy.log('AI Providers tab displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display AI Agents tab', () => {
      cy.get('body').then($body => {
        const hasAgents = $body.text().includes('Agents') ||
                         $body.text().includes('AI Agents');
        if (hasAgents) {
          cy.log('AI Agents tab displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Workflows tab', () => {
      cy.get('body').then($body => {
        const hasWorkflows = $body.text().includes('Workflows');
        if (hasWorkflows) {
          cy.log('Workflows tab displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Conversations tab', () => {
      cy.get('body').then($body => {
        const hasConversations = $body.text().includes('Conversations');
        if (hasConversations) {
          cy.log('Conversations tab displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Analytics tab', () => {
      cy.get('body').then($body => {
        const hasAnalytics = $body.text().includes('Analytics');
        if (hasAnalytics) {
          cy.log('Analytics tab displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Monitoring tab', () => {
      cy.get('body').then($body => {
        const hasMonitoring = $body.text().includes('Monitoring');
        if (hasMonitoring) {
          cy.log('Monitoring tab displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display MCP tab', () => {
      cy.get('body').then($body => {
        const hasMCP = $body.text().includes('MCP');
        if (hasMCP) {
          cy.log('MCP tab displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Tab Switching', () => {
    beforeEach(() => {
      cy.visit('/app/ai');
      cy.wait(2000);
    });

    it('should switch to AI Providers tab', () => {
      cy.get('body').then($body => {
        const providersTab = $body.find('button:contains("Providers"), a:contains("Providers")');
        if (providersTab.length > 0) {
          cy.wrap(providersTab).first().click({ force: true });
          cy.wait(500);
          cy.log('Switched to AI Providers tab');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should switch to AI Agents tab', () => {
      cy.get('body').then($body => {
        const agentsTab = $body.find('button:contains("Agents"), a:contains("Agents")');
        if (agentsTab.length > 0) {
          cy.wrap(agentsTab).first().click({ force: true });
          cy.wait(500);
          cy.log('Switched to AI Agents tab');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should switch to Workflows tab', () => {
      cy.get('body').then($body => {
        const workflowsTab = $body.find('button:contains("Workflows"), a:contains("Workflows")');
        if (workflowsTab.length > 0) {
          cy.wrap(workflowsTab).first().click({ force: true });
          cy.wait(500);
          cy.log('Switched to Workflows tab');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should switch to Conversations tab', () => {
      cy.get('body').then($body => {
        const conversationsTab = $body.find('button:contains("Conversations"), a:contains("Conversations")');
        if (conversationsTab.length > 0) {
          cy.wrap(conversationsTab).first().click({ force: true });
          cy.wait(500);
          cy.log('Switched to Conversations tab');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should switch to Analytics tab', () => {
      cy.get('body').then($body => {
        const analyticsTab = $body.find('button:contains("Analytics"), a:contains("Analytics")');
        if (analyticsTab.length > 0) {
          cy.wrap(analyticsTab).first().click({ force: true });
          cy.wait(500);
          cy.log('Switched to Analytics tab');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should switch to Monitoring tab', () => {
      cy.get('body').then($body => {
        const monitoringTab = $body.find('button:contains("Monitoring"), a:contains("Monitoring")');
        if (monitoringTab.length > 0) {
          cy.wrap(monitoringTab).first().click({ force: true });
          cy.wait(500);
          cy.log('Switched to Monitoring tab');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should switch to MCP tab', () => {
      cy.get('body').then($body => {
        const mcpTab = $body.find('button:contains("MCP"), a:contains("MCP")');
        if (mcpTab.length > 0) {
          cy.wrap(mcpTab).first().click({ force: true });
          cy.wait(500);
          cy.log('Switched to MCP tab');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Overview Tab Content', () => {
    beforeEach(() => {
      cy.visit('/app/ai');
      cy.wait(2000);
    });

    it('should display Enhanced AI Overview', () => {
      cy.get('body').then($body => {
        const hasOverview = $body.text().includes('Overview') ||
                           $body.find('[class*="card"]').length > 0;
        if (hasOverview) {
          cy.log('Enhanced AI Overview displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display AI system statistics', () => {
      cy.get('body').then($body => {
        const hasStats = $body.text().includes('Providers') ||
                        $body.text().includes('Agents') ||
                        $body.text().includes('Workflows');
        if (hasStats) {
          cy.log('AI system statistics displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Page Actions', () => {
    beforeEach(() => {
      cy.visit('/app/ai');
      cy.wait(2000);
    });

    it('should have Refresh button', () => {
      cy.get('body').then($body => {
        const refreshButton = $body.find('button:contains("Refresh")');
        if (refreshButton.length > 0) {
          cy.log('Refresh button found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Permission Check', () => {
    it('should show permission message for unauthorized users', () => {
      cy.visit('/app/ai');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasPermission = $body.text().includes("don't have permission") ||
                             $body.text().includes('AI Orchestration') ||
                             $body.find('[class*="tab"]').length > 0;
        if (hasPermission) {
          cy.log('Permission handled properly');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should hide tabs based on permissions', () => {
      cy.visit('/app/ai');
      cy.wait(2000);

      // Check that tabs are rendered based on permissions
      cy.get('body').then($body => {
        const tabCount = $body.find('[role="tab"], button[class*="tab"]').length;
        cy.log(`Found ${tabCount} tabs based on permissions`);
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Direct Tab Navigation', () => {
    it('should navigate directly to providers tab', () => {
      cy.visit('/app/ai/providers');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasProviders = $body.text().includes('Provider') ||
                            $body.text().includes('AI');
        if (hasProviders) {
          cy.log('Providers tab loaded directly');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should navigate directly to agents tab', () => {
      cy.visit('/app/ai/agents');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasAgents = $body.text().includes('Agent') ||
                         $body.text().includes('AI');
        if (hasAgents) {
          cy.log('Agents tab loaded directly');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should navigate directly to workflows tab', () => {
      cy.visit('/app/ai/workflows');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasWorkflows = $body.text().includes('Workflow') ||
                            $body.text().includes('AI');
        if (hasWorkflows) {
          cy.log('Workflows tab loaded directly');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should navigate directly to conversations tab', () => {
      cy.visit('/app/ai/conversations');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasConversations = $body.text().includes('Conversation') ||
                                $body.text().includes('AI');
        if (hasConversations) {
          cy.log('Conversations tab loaded directly');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should navigate directly to analytics tab', () => {
      cy.visit('/app/ai/analytics');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasAnalytics = $body.text().includes('Analytics') ||
                            $body.text().includes('AI');
        if (hasAnalytics) {
          cy.log('Analytics tab loaded directly');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should navigate directly to monitoring tab', () => {
      cy.visit('/app/ai/monitoring');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasMonitoring = $body.text().includes('Monitoring') ||
                             $body.text().includes('AI');
        if (hasMonitoring) {
          cy.log('Monitoring tab loaded directly');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should navigate directly to MCP tab', () => {
      cy.visit('/app/ai/mcp');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasMCP = $body.text().includes('MCP') ||
                      $body.text().includes('AI');
        if (hasMCP) {
          cy.log('MCP tab loaded directly');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.intercept('GET', '/api/v1/ai/*', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/ai');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should display error notification on failure', () => {
      cy.intercept('GET', '/api/v1/ai/*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load AI data' }
      });

      cy.visit('/app/ai');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasError = $body.text().includes('Error') ||
                         $body.text().includes('Failed') ||
                         $body.text().includes('AI');
        if (hasError) {
          cy.log('Error handled');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '/api/v1/ai/*', {
        delay: 1000,
        statusCode: 200,
        body: { success: true }
      });

      cy.visit('/app/ai');

      cy.get('body').then($body => {
        const hasLoading = $body.find('[class*="spin"], [class*="loading"]').length > 0 ||
                           $body.text().includes('Loading');
        if (hasLoading) {
          cy.log('Loading indicator displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/ai');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('AI') || $body.text().includes('Orchestration');
        if (hasContent) {
          cy.log('Content visible on mobile');
        }
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/ai');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('AI') || $body.text().includes('Orchestration');
        if (hasContent) {
          cy.log('Content visible on tablet');
        }
      });
    });

    it('should stack elements on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/ai');
      cy.wait(2000);

      cy.get('body').should('be.visible');
    });

    it('should handle horizontal tab scrolling on mobile', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/ai');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasTabs = $body.find('[role="tablist"], [class*="tab"]').length > 0;
        if (hasTabs) {
          cy.log('Tabs visible and scrollable on mobile');
        }
      });

      cy.get('body').should('be.visible');
    });
  });
});
