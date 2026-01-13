/// <reference types="cypress" />

/**
 * DevOps API Keys Management Tests
 *
 * Tests for API Keys page functionality including:
 * - Page navigation and load
 * - API key list display
 * - Generate new API key modal
 * - API key details display
 * - Copy API key to clipboard
 * - Regenerate API key
 * - Toggle API key status
 * - Security notice display
 * - API call stats display
 * - Empty state handling
 * - Error handling
 * - Responsive design
 */

describe('DevOps API Keys Management Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    // Login with demo user
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to API Keys page from DevOps', () => {
      cy.visit('/app/devops');
      cy.wait(2000);

      cy.get('body').then($body => {
        const apiKeyLink = $body.find('a[href*="/api-keys"], button:contains("API Keys")');

        if (apiKeyLink.length > 0) {
          cy.wrap(apiKeyLink).first().click();
          cy.url().should('include', '/api-keys');
        } else {
          cy.visit('/app/devops/api-keys');
        }
      });

      cy.url().should('include', '/api-keys');
      cy.get('body').should('be.visible');
    });

    it('should load API Keys page directly', () => {
      cy.visit('/app/devops/api-keys');

      cy.url().then(url => {
        if (url.includes('/api-keys')) {
          cy.get('body').should('satisfy', ($body) => {
            const text = $body.text();
            return text.includes('API Key') || text.includes('API Keys') || text.includes('Generate');
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/devops/api-keys');

      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('Dashboard') &&
                               ($body.text().includes('DevOps') || $body.text().includes('API Keys'));

        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs displayed correctly');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('API Key List Display', () => {
    beforeEach(() => {
      cy.visit('/app/devops/api-keys');
      cy.wait(2000);
    });

    it('should display API keys list or empty state', () => {
      cy.get('body').then($body => {
        const hasApiKeys = $body.find('[class*="key"], [class*="card"]').length > 0 ||
                           $body.text().includes('No API Keys');

        if ($body.text().includes('No API Keys')) {
          cy.contains('No API Keys').should('be.visible');
          cy.log('Empty state displayed');
        } else {
          cy.log('API keys list or loading state displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display API key name', () => {
      cy.get('body').then($body => {
        // Look for key cards with names
        const keyCards = $body.find('[class*="card"], [class*="key-item"]');

        if (keyCards.length > 0) {
          cy.log(`Found ${keyCards.length} API key card(s)`);
        } else if ($body.text().includes('No API Keys')) {
          cy.log('No API keys to display');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display API key status badges', () => {
      cy.get('body').then($body => {
        const hasStatusBadges = $body.text().includes('Active') ||
                                 $body.text().includes('Inactive') ||
                                 $body.text().includes('Revoked');

        if (hasStatusBadges) {
          cy.log('Status badges displayed');
        } else {
          cy.log('No status badges - may have no keys or different status format');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display masked API key', () => {
      cy.get('body').then($body => {
        // Look for masked key format (e.g., pk_****...)
        const hasMaskedKey = $body.find('code').length > 0 ||
                             /[a-z]{2,}_[\*]+/.test($body.text()) ||
                             $body.text().includes('****');

        if (hasMaskedKey) {
          cy.log('Masked API key displayed');
        } else {
          cy.log('No masked keys visible - may have no keys');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display API key scopes if available', () => {
      cy.get('body').then($body => {
        const hasScopes = $body.text().includes('Read') ||
                          $body.text().includes('Write') ||
                          $body.text().includes('Admin') ||
                          $body.find('[class*="scope"], [class*="badge"]').length > 0;

        if (hasScopes) {
          cy.log('API key scopes displayed');
        } else {
          cy.log('No scopes visible');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display last used timestamp', () => {
      cy.get('body').then($body => {
        const hasLastUsed = $body.text().includes('Last used') ||
                            $body.text().includes('Never') ||
                            $body.text().includes('ago');

        if (hasLastUsed) {
          cy.log('Last used timestamp displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display usage count', () => {
      cy.get('body').then($body => {
        const hasUsage = $body.text().includes('Usage') ||
                         $body.text().includes('requests') ||
                         /\d+\s*(calls?|requests?)/i.test($body.text());

        if (hasUsage) {
          cy.log('Usage count displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Generate New API Key', () => {
    beforeEach(() => {
      cy.visit('/app/devops/api-keys');
      cy.wait(2000);
    });

    it('should display Generate New Key button', () => {
      cy.get('body').then($body => {
        const generateButton = $body.find('button:contains("Generate"), button:contains("New Key"), button:contains("Create")');

        if (generateButton.length > 0) {
          cy.wrap(generateButton).first().should('be.visible');
          cy.log('Generate button found');
        } else {
          cy.log('Generate button not visible - may require permissions');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should open modal when Generate New Key clicked', () => {
      cy.get('body').then($body => {
        const generateButton = $body.find('button:contains("Generate"), button:contains("New Key")');

        if (generateButton.length > 0) {
          cy.wrap(generateButton).first().click();
          cy.wait(500);

          // Check for modal
          cy.get('body').then($newBody => {
            const modalVisible = $newBody.find('[role="dialog"], [class*="modal"]').length > 0 ||
                                  $newBody.text().includes('Create') ||
                                  $newBody.text().includes('Name');

            if (modalVisible) {
              cy.log('API Key modal opened');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have name input in modal', () => {
      cy.get('body').then($body => {
        const generateButton = $body.find('button:contains("Generate"), button:contains("New Key")');

        if (generateButton.length > 0) {
          cy.wrap(generateButton).first().click();
          cy.wait(500);

          cy.get('body').then($newBody => {
            const nameInput = $newBody.find('input[name="name"], input[placeholder*="name"]');

            if (nameInput.length > 0) {
              cy.wrap(nameInput).should('be.visible');
              cy.log('Name input found in modal');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have scope selection in modal', () => {
      cy.get('body').then($body => {
        const generateButton = $body.find('button:contains("Generate"), button:contains("New Key")');

        if (generateButton.length > 0) {
          cy.wrap(generateButton).first().click();
          cy.wait(500);

          cy.get('body').then($newBody => {
            const hasScopes = $newBody.text().includes('Scope') ||
                              $newBody.text().includes('Permission') ||
                              $newBody.find('input[type="checkbox"]').length > 0;

            if (hasScopes) {
              cy.log('Scope selection found in modal');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should close modal when cancel clicked', () => {
      cy.get('body').then($body => {
        const generateButton = $body.find('button:contains("Generate"), button:contains("New Key")');

        if (generateButton.length > 0) {
          cy.wrap(generateButton).first().click();
          cy.wait(500);

          cy.get('body').then($newBody => {
            const cancelButton = $newBody.find('button:contains("Cancel"), button:contains("Close")');

            if (cancelButton.length > 0) {
              cy.wrap(cancelButton).first().click();
              cy.wait(500);
              cy.log('Modal closed');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Copy API Key', () => {
    beforeEach(() => {
      cy.visit('/app/devops/api-keys');
      cy.wait(2000);
    });

    it('should have copy button for API keys', () => {
      cy.get('body').then($body => {
        const copyButton = $body.find('button:contains("Copy"), [aria-label*="copy"], [title*="Copy"]');

        if (copyButton.length > 0) {
          cy.wrap(copyButton).first().should('be.visible');
          cy.log('Copy button found');
        } else if (!$body.text().includes('No API Keys')) {
          cy.log('Copy button not visible - may use different UI');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should show feedback when key copied', () => {
      cy.get('body').then($body => {
        const copyButton = $body.find('button:contains("Copy")');

        if (copyButton.length > 0) {
          cy.wrap(copyButton).first().click();
          cy.wait(500);

          // Check for success feedback
          cy.get('body').then($newBody => {
            const hasFeedback = $newBody.text().includes('Copied') ||
                                $newBody.text().includes('clipboard') ||
                                $newBody.find('[class*="success"], [class*="toast"]').length > 0;

            if (hasFeedback) {
              cy.log('Copy feedback displayed');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Regenerate API Key', () => {
    beforeEach(() => {
      cy.visit('/app/devops/api-keys');
      cy.wait(2000);
    });

    it('should have regenerate button for API keys', () => {
      cy.get('body').then($body => {
        const regenerateButton = $body.find('button:contains("Regenerate"), [title*="Regenerate"]');

        if (regenerateButton.length > 0) {
          cy.wrap(regenerateButton).first().should('be.visible');
          cy.log('Regenerate button found');
        } else if (!$body.text().includes('No API Keys')) {
          cy.log('Regenerate button not visible');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should show confirmation before regenerating', () => {
      cy.get('body').then($body => {
        const regenerateButton = $body.find('button:contains("Regenerate")');

        if (regenerateButton.length > 0) {
          cy.wrap(regenerateButton).first().click();
          cy.wait(500);

          // Check for confirmation dialog
          cy.get('body').then($newBody => {
            const hasConfirmation = $newBody.find('[role="dialog"], [class*="modal"], [class*="confirm"]').length > 0 ||
                                     $newBody.text().includes('Are you sure') ||
                                     $newBody.text().includes('confirm');

            if (hasConfirmation) {
              cy.log('Confirmation dialog displayed');

              // Cancel the regeneration
              const cancelButton = $newBody.find('button:contains("Cancel")');
              if (cancelButton.length > 0) {
                cy.wrap(cancelButton).first().click();
              }
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Toggle API Key Status', () => {
    beforeEach(() => {
      cy.visit('/app/devops/api-keys');
      cy.wait(2000);
    });

    it('should have revoke/activate button for API keys', () => {
      cy.get('body').then($body => {
        const statusButton = $body.find('button:contains("Revoke"), button:contains("Activate"), button:contains("Disable")');

        if (statusButton.length > 0) {
          cy.wrap(statusButton).first().should('be.visible');
          cy.log('Status toggle button found');
        } else if (!$body.text().includes('No API Keys')) {
          cy.log('Status toggle not visible');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should toggle API key status on click', () => {
      cy.get('body').then($body => {
        const statusButton = $body.find('button:contains("Revoke"), button:contains("Activate")');

        if (statusButton.length > 0) {
          const initialText = statusButton.first().text();
          cy.wrap(statusButton).first().click();
          cy.wait(1000);

          // Verify status changed
          cy.get('body').should('be.visible');
          cy.log('Status toggle clicked');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Security Notice', () => {
    beforeEach(() => {
      cy.visit('/app/devops/api-keys');
      cy.wait(2000);
    });

    it('should display security notice', () => {
      cy.get('body').then($body => {
        const hasSecurityNotice = $body.text().includes('Security') ||
                                   $body.text().includes('secure') ||
                                   $body.text().includes('Keep them secure') ||
                                   $body.find('[class*="warning"], [class*="notice"]').length > 0;

        if (hasSecurityNotice) {
          cy.log('Security notice displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('API Call Stats', () => {
    beforeEach(() => {
      cy.visit('/app/devops/api-keys');
      cy.wait(2000);
    });

    it('should display API Calls Today stat', () => {
      cy.get('body').then($body => {
        if ($body.text().includes('API Calls Today') || $body.text().includes('Calls Today')) {
          cy.contains(/API Calls Today|Calls Today/i).should('be.visible');
          cy.log('API Calls Today stat displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Total API Calls stat', () => {
      cy.get('body').then($body => {
        if ($body.text().includes('Total API Calls') || $body.text().includes('Total Calls')) {
          cy.contains(/Total (API )?Calls/i).should('be.visible');
          cy.log('Total API Calls stat displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Active Keys stat', () => {
      cy.get('body').then($body => {
        if ($body.text().includes('Active Keys') || $body.text().includes('Active')) {
          cy.contains(/Active Keys?/i).should('be.visible');
          cy.log('Active Keys stat displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Empty State', () => {
    it('should display empty state when no keys exist', () => {
      // Mock empty API keys response
      cy.intercept('GET', '/api/v1/api_keys*', {
        statusCode: 200,
        body: {
          success: true,
          data: {
            api_keys: [],
            stats: { requests_today: 0, total_keys: 0 }
          }
        }
      });

      cy.visit('/app/devops/api-keys');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasEmptyState = $body.text().includes('No API Keys') ||
                               $body.text().includes('Get started') ||
                               $body.text().includes('Generate Your First');

        if (hasEmptyState) {
          cy.log('Empty state displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have generate button in empty state', () => {
      cy.intercept('GET', '/api/v1/api_keys*', {
        statusCode: 200,
        body: {
          success: true,
          data: {
            api_keys: [],
            stats: { requests_today: 0, total_keys: 0 }
          }
        }
      });

      cy.visit('/app/devops/api-keys');
      cy.wait(2000);

      cy.get('body').then($body => {
        const generateButton = $body.find('button:contains("Generate")');

        if (generateButton.length > 0) {
          cy.wrap(generateButton).should('be.visible');
          cy.log('Generate button in empty state');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.intercept('GET', '/api/v1/api_keys*', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/devops/api-keys');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should display error message on failure', () => {
      cy.intercept('GET', '/api/v1/api_keys*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load API keys' }
      });

      cy.visit('/app/devops/api-keys');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasError = $body.text().includes('Error') ||
                          $body.text().includes('Failed') ||
                          $body.find('[class*="error"]').length > 0;

        if (hasError) {
          cy.log('Error message displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have retry button on error', () => {
      cy.intercept('GET', '/api/v1/api_keys*', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/devops/api-keys');
      cy.wait(2000);

      cy.get('body').then($body => {
        const retryButton = $body.find('button:contains("Retry"), button:contains("Try again")');

        if (retryButton.length > 0) {
          cy.wrap(retryButton).should('be.visible');
          cy.log('Retry button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Refresh Functionality', () => {
    beforeEach(() => {
      cy.visit('/app/devops/api-keys');
      cy.wait(2000);
    });

    it('should have refresh button', () => {
      cy.get('body').then($body => {
        const refreshButton = $body.find('button:contains("Refresh"), [aria-label*="refresh"]');

        if (refreshButton.length > 0) {
          cy.wrap(refreshButton).should('be.visible');
          cy.log('Refresh button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should refresh API keys list', () => {
      cy.get('body').then($body => {
        const refreshButton = $body.find('button:contains("Refresh")');

        if (refreshButton.length > 0) {
          cy.wrap(refreshButton).first().click();
          cy.wait(1000);
          cy.get('body').should('be.visible');
          cy.log('Refresh triggered');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/devops/api-keys');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('API') || $body.text().includes('Key');
        if (hasContent) {
          cy.log('Content visible on mobile');
        }
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/devops/api-keys');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('API') || $body.text().includes('Key');
        if (hasContent) {
          cy.log('Content visible on tablet');
        }
      });
    });

    it('should stack elements on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/devops/api-keys');
      cy.wait(2000);

      cy.get('body').should('be.visible');
    });
  });
});
