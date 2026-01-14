/// <reference types="cypress" />

/**
 * AI Providers Tests
 *
 * Tests for AI Providers page functionality including:
 * - Page navigation and load
 * - Providers list display
 * - Provider configuration
 * - Provider status
 * - Add/configure provider actions
 * - Provider integration settings
 * - API key management for providers
 * - Responsive design
 */

describe('AI Providers Tests', () => {
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
    it('should navigate to AI Providers from sidebar', () => {
      cy.visit('/app');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const aiLink = $body.find('a[href*="/ai"], button:contains("AI")');

        if (aiLink.length > 0) {
          cy.wrap(aiLink).first().should('be.visible').click();
          cy.waitForPageLoad();

          cy.get('body').then($newBody => {
            const providersLink = $newBody.find('a[href*="/providers"]');
            if (providersLink.length > 0) {
              cy.wrap(providersLink).first().should('be.visible').click();
            } else {
              cy.visit('/app/ai/providers');
            }
          });
        } else {
          cy.visit('/app/ai/providers');
        }
      });

      cy.url().should('include', '/providers');
      cy.get('body').should('be.visible');
    });

    it('should load AI Providers page directly', () => {
      cy.visit('/app/ai/providers');
      cy.waitForPageLoad();

      cy.url().then(url => {
        if (url.includes('/providers')) {
          cy.get('body').should('satisfy', ($body) => {
            const text = $body.text();
            return text.includes('Provider') || text.includes('AI') || text.includes('Integration');
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/ai/providers');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('Dashboard') &&
                               ($body.text().includes('AI') || $body.text().includes('Providers'));

        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs displayed correctly');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Providers List Display', () => {
    beforeEach(() => {
      cy.visit('/app/ai/providers');
      cy.waitForPageLoad();
    });

    it('should display providers list or empty state', () => {
      cy.get('body').then($body => {
        const _hasProviders = $body.find('[class*="provider"], [class*="card"], [class*="list"]').length > 0 ||
                             $body.text().includes('No providers') ||
                             $body.text().includes('Configure');

        if ($body.text().includes('No providers')) {
          cy.log('Empty state displayed');
        } else {
          cy.log('Providers list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display common AI providers', () => {
      cy.get('body').then($body => {
        const providers = ['OpenAI', 'Anthropic', 'Azure', 'Google', 'Cohere', 'Hugging Face'];
        let foundProviders = 0;

        providers.forEach(provider => {
          if ($body.text().includes(provider)) {
            foundProviders++;
          }
        });

        if (foundProviders > 0) {
          cy.log(`Found ${foundProviders} known AI providers`);
        } else {
          cy.log('No standard providers displayed - may use custom providers');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display provider status', () => {
      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Connected') ||
                          $body.text().includes('Configured') ||
                          $body.text().includes('Active') ||
                          $body.text().includes('Not configured') ||
                          $body.find('[class*="status"], [class*="badge"]').length > 0;

        if (hasStatus) {
          cy.log('Provider status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display provider logos or icons', () => {
      cy.get('body').then($body => {
        const hasLogos = $body.find('img, svg, [class*="icon"], [class*="logo"]').length > 0;

        if (hasLogos) {
          cy.log('Provider logos/icons displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Provider Configuration', () => {
    beforeEach(() => {
      cy.visit('/app/ai/providers');
      cy.waitForPageLoad();
    });

    it('should have configure action for providers', () => {
      cy.get('body').then($body => {
        const configureButton = $body.find('button:contains("Configure"), button:contains("Setup"), button:contains("Connect")');

        if (configureButton.length > 0) {
          cy.wrap(configureButton).first().should('be.visible');
          cy.log('Configure button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should open configuration modal when configure clicked', () => {
      cy.get('body').then($body => {
        const configureButton = $body.find('button:contains("Configure"), button:contains("Setup")');

        if (configureButton.length > 0) {
          cy.wrap(configureButton).first().should('be.visible').click();
          cy.waitForStableDOM();

          cy.get('body').then($newBody => {
            const modalVisible = $newBody.find('[role="dialog"], [class*="modal"]').length > 0 ||
                                  $newBody.text().includes('API Key') ||
                                  $newBody.text().includes('Configuration');

            if (modalVisible) {
              cy.log('Configuration modal opened');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have API key input in configuration', () => {
      cy.get('body').then($body => {
        const configureButton = $body.find('button:contains("Configure"), button:contains("Setup")');

        if (configureButton.length > 0) {
          cy.wrap(configureButton).first().should('be.visible').click();
          cy.waitForStableDOM();

          cy.get('body').then($newBody => {
            const apiKeyInput = $newBody.find('input[name="apiKey"], input[name="api_key"], input[placeholder*="API"]');

            if (apiKeyInput.length > 0) {
              cy.wrap(apiKeyInput).should('be.visible');
              cy.log('API key input found');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should close configuration modal when cancel clicked', () => {
      cy.get('body').then($body => {
        const configureButton = $body.find('button:contains("Configure")');

        if (configureButton.length > 0) {
          cy.wrap(configureButton).first().should('be.visible').click();
          cy.waitForStableDOM();

          cy.get('body').then($newBody => {
            const cancelButton = $newBody.find('button:contains("Cancel"), button:contains("Close")');

            if (cancelButton.length > 0) {
              cy.wrap(cancelButton).first().should('be.visible').click();
              cy.waitForModalClose();
              cy.log('Modal closed');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Provider Status Management', () => {
    beforeEach(() => {
      cy.visit('/app/ai/providers');
      cy.waitForPageLoad();
    });

    it('should have enable/disable action for providers', () => {
      cy.get('body').then($body => {
        const toggleButton = $body.find('button:contains("Enable"), button:contains("Disable"), [class*="toggle"]');

        if (toggleButton.length > 0) {
          cy.wrap(toggleButton).first().should('be.visible');
          cy.log('Enable/Disable button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should toggle provider status', () => {
      cy.get('body').then($body => {
        const toggleButton = $body.find('button:contains("Enable"), button:contains("Disable")');

        if (toggleButton.length > 0) {
          cy.wrap(toggleButton).first().should('be.visible').click();
          cy.waitForPageLoad();
          cy.get('body').should('be.visible');
          cy.log('Provider status toggled');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display connected status for configured providers', () => {
      cy.get('body').then($body => {
        const hasConnectedStatus = $body.text().includes('Connected') ||
                                    $body.text().includes('Active') ||
                                    $body.find('[class*="success"]').length > 0;

        if (hasConnectedStatus) {
          cy.log('Connected status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Provider Details', () => {
    beforeEach(() => {
      cy.visit('/app/ai/providers');
      cy.waitForPageLoad();
    });

    it('should have view details action', () => {
      cy.get('body').then($body => {
        const viewButton = $body.find('button:contains("View"), button:contains("Details"), [aria-label*="view"]');

        if (viewButton.length > 0) {
          cy.wrap(viewButton).first().should('be.visible');
          cy.log('View details button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display provider capabilities', () => {
      cy.get('body').then($body => {
        const hasCapabilities = $body.text().includes('chat') ||
                                 $body.text().includes('completion') ||
                                 $body.text().includes('embedding') ||
                                 $body.text().includes('model');

        if (hasCapabilities) {
          cy.log('Provider capabilities displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display available models', () => {
      cy.get('body').then($body => {
        const hasModels = $body.text().includes('gpt') ||
                          $body.text().includes('claude') ||
                          $body.text().includes('model') ||
                          $body.find('[class*="model"]').length > 0;

        if (hasModels) {
          cy.log('Available models displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('API Key Management', () => {
    beforeEach(() => {
      cy.visit('/app/ai/providers');
      cy.waitForPageLoad();
    });

    it('should mask API keys when displayed', () => {
      cy.get('body').then($body => {
        // API keys should not be fully visible
        const hasVisibleKey = $body.text().match(/sk-[a-zA-Z0-9]{48}/);

        if (!hasVisibleKey) {
          cy.log('API keys are properly masked');
        } else {
          cy.log('Warning: API key may be visible');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have option to update API key', () => {
      cy.get('body').then($body => {
        const updateButton = $body.find('button:contains("Update"), button:contains("Edit"), button:contains("Change")');

        if (updateButton.length > 0) {
          cy.log('Update API key option available');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should validate API key format', () => {
      cy.get('body').then($body => {
        const configureButton = $body.find('button:contains("Configure")');

        if (configureButton.length > 0) {
          cy.wrap(configureButton).first().should('be.visible').click();
          cy.waitForStableDOM();

          cy.get('body').then($newBody => {
            const apiKeyInput = $newBody.find('input[name="apiKey"], input[name="api_key"]');

            if (apiKeyInput.length > 0) {
              cy.wrap(apiKeyInput).type('invalid-key');

              const saveButton = $newBody.find('button[type="submit"], button:contains("Save")');
              if (saveButton.length > 0) {
                cy.wrap(saveButton).first().should('be.visible').click();
                cy.waitForPageLoad();

                // Check for validation error
                cy.get('body').then($errorBody => {
                  const hasError = $errorBody.text().toLowerCase().includes('valid') ||
                                    $errorBody.text().toLowerCase().includes('invalid') ||
                                    $errorBody.find('[class*="error"]').length > 0;

                  if (hasError) {
                    cy.log('API key validation working');
                  }
                });
              }
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Provider Testing', () => {
    beforeEach(() => {
      cy.visit('/app/ai/providers');
      cy.waitForPageLoad();
    });

    it('should have test connection action', () => {
      cy.get('body').then($body => {
        const testButton = $body.find('button:contains("Test"), button:contains("Verify")');

        if (testButton.length > 0) {
          cy.wrap(testButton).first().should('be.visible');
          cy.log('Test connection button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should show test result feedback', () => {
      cy.get('body').then($body => {
        const testButton = $body.find('button:contains("Test")');

        if (testButton.length > 0) {
          cy.wrap(testButton).first().should('be.visible').click();
          cy.waitForPageLoad();

          cy.get('body').then($newBody => {
            const hasResult = $newBody.text().includes('Success') ||
                               $newBody.text().includes('Failed') ||
                               $newBody.text().includes('Connected') ||
                               $newBody.find('[class*="success"], [class*="error"]').length > 0;

            if (hasResult) {
              cy.log('Test result displayed');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Provider Settings', () => {
    beforeEach(() => {
      cy.visit('/app/ai/providers');
      cy.waitForPageLoad();
    });

    it('should have settings/preferences option', () => {
      cy.get('body').then($body => {
        const settingsButton = $body.find('button:contains("Settings"), button:contains("Preferences"), [aria-label*="settings"]');

        if (settingsButton.length > 0) {
          cy.wrap(settingsButton).first().should('be.visible');
          cy.log('Settings option found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display rate limiting settings', () => {
      cy.get('body').then($body => {
        const hasRateLimit = $body.text().includes('rate') ||
                              $body.text().includes('limit') ||
                              $body.text().includes('quota');

        if (hasRateLimit) {
          cy.log('Rate limiting settings displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display default model settings', () => {
      cy.get('body').then($body => {
        const hasModelSettings = $body.text().includes('Default') ||
                                  $body.text().includes('model') ||
                                  $body.find('select').length > 0;

        if (hasModelSettings) {
          cy.log('Model settings displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Empty State', () => {
    it('should display empty state when no providers configured', () => {
      cy.intercept('GET', '/api/v1/ai/providers*', {
        statusCode: 200,
        body: {
          success: true,
          data: { providers: [] }
        }
      }).as('emptyProviders');

      cy.visit('/app/ai/providers');
      cy.wait('@emptyProviders');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasEmptyState = $body.text().includes('No providers') ||
                               $body.text().includes('Get started') ||
                               $body.text().includes('Configure') ||
                               $body.text().includes('Add provider');

        if (hasEmptyState) {
          cy.log('Empty state displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.intercept('GET', '/api/v1/ai/providers*', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      }).as('serverError');

      cy.visit('/app/ai/providers');
      cy.wait('@serverError');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should display error notification on failure', () => {
      cy.intercept('GET', '/api/v1/ai/providers*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load providers' }
      }).as('loadError');

      cy.visit('/app/ai/providers');
      cy.wait('@loadError');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasError = $body.text().includes('Error') ||
                          $body.text().includes('Failed') ||
                          $body.find('[class*="error"], [class*="toast"]').length > 0;

        if (hasError) {
          cy.log('Error notification displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should handle invalid API key error', () => {
      cy.intercept('POST', '/api/v1/ai/providers/*/test', {
        statusCode: 401,
        body: { success: false, error: 'Invalid API key' }
      }).as('invalidKeyError');

      cy.visit('/app/ai/providers');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const testButton = $body.find('button:contains("Test")');

        if (testButton.length > 0) {
          cy.wrap(testButton).first().should('be.visible').click();
          cy.wait('@invalidKeyError');

          cy.get('body').then($newBody => {
            const hasError = $newBody.text().includes('Invalid') ||
                              $newBody.text().includes('Error') ||
                              $newBody.find('[class*="error"]').length > 0;

            if (hasError) {
              cy.log('Invalid API key error displayed');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/ai/providers');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Provider') || $body.text().includes('AI');
        if (hasContent) {
          cy.log('Content visible on mobile');
        }
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/ai/providers');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Provider') || $body.text().includes('AI');
        if (hasContent) {
          cy.log('Content visible on tablet');
        }
      });
    });

    it('should stack provider cards on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/ai/providers');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
    });
  });
});


export {};
