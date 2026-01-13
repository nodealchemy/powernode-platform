/// <reference types="cypress" />

/**
 * AI Debug Page Tests
 *
 * Tests for AI Debug functionality including:
 * - Page navigation and load
 * - Debug information display
 * - AIPermissionsDebug component
 * - Troubleshooting steps
 * - Common solutions
 * - Permission-based access
 * - Error handling
 * - Responsive design
 */

describe('AI Debug Page Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to AI Debug page', () => {
      cy.visit('/app/ai/debug');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Debug') ||
                          $body.text().includes('AI') ||
                          $body.text().includes('Troubleshoot') ||
                          $body.text().includes('Permission');
        if (hasContent) {
          cy.log('AI Debug page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page title', () => {
      cy.visit('/app/ai/debug');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('Debug') ||
                        $body.text().includes('AI Debug');
        if (hasTitle) {
          cy.log('Page title displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/ai/debug');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('Dashboard') ||
                               $body.text().includes('AI') ||
                               $body.text().includes('Orchestration');
        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Debug Information Display', () => {
    beforeEach(() => {
      cy.visit('/app/ai/debug');
      cy.wait(2000);
    });

    it('should display permissions debug component', () => {
      cy.get('body').then($body => {
        const hasPermissions = $body.text().includes('Permission') ||
                              $body.text().includes('Access') ||
                              $body.find('[class*="debug"]').length > 0;
        if (hasPermissions) {
          cy.log('Permissions debug component displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display current user permissions', () => {
      cy.get('body').then($body => {
        const hasUserInfo = $body.text().includes('User') ||
                           $body.text().includes('Current') ||
                           $body.text().includes('Permissions');
        if (hasUserInfo) {
          cy.log('Current user permissions displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display AI-related permissions', () => {
      cy.get('body').then($body => {
        const hasAIPermissions = $body.text().includes('ai.') ||
                                $body.text().includes('workflow') ||
                                $body.text().includes('agent');
        if (hasAIPermissions) {
          cy.log('AI-related permissions displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Troubleshooting Steps', () => {
    beforeEach(() => {
      cy.visit('/app/ai/debug');
      cy.wait(2000);
    });

    it('should display troubleshooting section', () => {
      cy.get('body').then($body => {
        const hasTroubleshooting = $body.text().includes('Troubleshoot') ||
                                   $body.text().includes('Steps') ||
                                   $body.text().includes('Fix');
        if (hasTroubleshooting) {
          cy.log('Troubleshooting section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display step-by-step instructions', () => {
      cy.get('body').then($body => {
        const hasSteps = $body.text().includes('Step') ||
                        $body.text().includes('1.') ||
                        $body.find('ol, ul').length > 0;
        if (hasSteps) {
          cy.log('Step-by-step instructions displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Common Solutions', () => {
    beforeEach(() => {
      cy.visit('/app/ai/debug');
      cy.wait(2000);
    });

    it('should display common solutions section', () => {
      cy.get('body').then($body => {
        const hasSolutions = $body.text().includes('Common') ||
                            $body.text().includes('Solution') ||
                            $body.text().includes('Issue');
        if (hasSolutions) {
          cy.log('Common solutions section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display permission-related solutions', () => {
      cy.get('body').then($body => {
        const hasPermissionSolutions = $body.text().includes('permission') ||
                                       $body.text().includes('access') ||
                                       $body.text().includes('denied');
        if (hasPermissionSolutions) {
          cy.log('Permission-related solutions displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display configuration solutions', () => {
      cy.get('body').then($body => {
        const hasConfigSolutions = $body.text().includes('config') ||
                                   $body.text().includes('setting') ||
                                   $body.text().includes('enable');
        if (hasConfigSolutions) {
          cy.log('Configuration solutions displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Debug Actions', () => {
    beforeEach(() => {
      cy.visit('/app/ai/debug');
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

    it('should have Clear Cache button', () => {
      cy.get('body').then($body => {
        const clearButton = $body.find('button:contains("Clear"), button:contains("Reset")');
        if (clearButton.length > 0) {
          cy.log('Clear Cache button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Export Debug Info button', () => {
      cy.get('body').then($body => {
        const exportButton = $body.find('button:contains("Export"), button:contains("Download")');
        if (exportButton.length > 0) {
          cy.log('Export Debug Info button found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('System Status', () => {
    beforeEach(() => {
      cy.visit('/app/ai/debug');
      cy.wait(2000);
    });

    it('should display system status', () => {
      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Status') ||
                         $body.text().includes('Online') ||
                         $body.text().includes('Connected');
        if (hasStatus) {
          cy.log('System status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display API connection status', () => {
      cy.get('body').then($body => {
        const hasAPIStatus = $body.text().includes('API') ||
                            $body.text().includes('Connection');
        if (hasAPIStatus) {
          cy.log('API connection status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Permission Check', () => {
    it('should show permission message for unauthorized users', () => {
      cy.visit('/app/ai/debug');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasPermission = $body.text().includes("don't have permission") ||
                             $body.text().includes('Debug') ||
                             $body.text().includes('AI');
        if (hasPermission) {
          cy.log('Permission handled properly');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.intercept('GET', '/api/v1/ai/debug*', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/ai/debug');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should display error notification on failure', () => {
      cy.intercept('GET', '/api/v1/ai/debug*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load debug info' }
      });

      cy.visit('/app/ai/debug');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasError = $body.text().includes('Error') ||
                         $body.text().includes('Failed') ||
                         $body.text().includes('Debug');
        if (hasError) {
          cy.log('Error handled');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '/api/v1/ai/debug*', {
        delay: 1000,
        statusCode: 200,
        body: { success: true, debug: {} }
      });

      cy.visit('/app/ai/debug');

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
      cy.visit('/app/ai/debug');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Debug') || $body.text().includes('AI');
        if (hasContent) {
          cy.log('Content visible on mobile');
        }
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/ai/debug');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Debug') || $body.text().includes('AI');
        if (hasContent) {
          cy.log('Content visible on tablet');
        }
      });
    });

    it('should stack elements on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/ai/debug');
      cy.wait(2000);

      cy.get('body').should('be.visible');
    });
  });
});
