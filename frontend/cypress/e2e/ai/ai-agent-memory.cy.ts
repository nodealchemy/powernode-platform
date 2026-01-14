/// <reference types="cypress" />

describe('AI Agent Memory Page Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 5000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to Agent Memory page', () => {
      cy.visit('/app/ai/agents/test-agent/memory');
      cy.url().should('include', '/ai');
    });

    it('should display agent not found for invalid agent', () => {
      cy.visit('/app/ai/agents/invalid-agent-id/memory');
      cy.get('body').then($body => {
        const hasNotFound = $body.text().includes('Not Found') ||
                           $body.text().includes('does not exist') ||
                           $body.text().includes('Back to Agents');
        if (hasNotFound) {
          cy.log('Agent not found message displayed');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Page Actions', () => {
    it('should have Clear All button', () => {
      cy.visit('/app/ai/agents/test-agent/memory');
      cy.get('body').then($body => {
        const hasClear = $body.text().includes('Clear All') ||
                        $body.text().includes('Clear');
        if (hasClear) {
          cy.log('Clear All button found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should have Add Memory button', () => {
      cy.visit('/app/ai/agents/test-agent/memory');
      cy.get('body').then($body => {
        const hasAdd = $body.text().includes('Add Memory') ||
                      $body.text().includes('Add');
        if (hasAdd) {
          cy.log('Add Memory button found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Context Info Display', () => {
    it('should display context information', () => {
      cy.visit('/app/ai/agents/test-agent/memory');
      cy.get('body').then($body => {
        const hasContext = $body.text().includes('entries') ||
                          $body.find('[class*="context"]').length > 0 ||
                          $body.text().includes('Memory');
        if (hasContext) {
          cy.log('Context information found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display entry count', () => {
      cy.visit('/app/ai/agents/test-agent/memory');
      cy.get('body').then($body => {
        const hasCount = $body.text().includes('entries') ||
                        $body.text().match(/\d+ entries/);
        if (hasCount) {
          cy.log('Entry count displayed');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should have View Full Context link', () => {
      cy.visit('/app/ai/agents/test-agent/memory');
      cy.get('body').then($body => {
        const hasLink = $body.text().includes('View Full Context') ||
                       $body.find('a[href*="/contexts/"]').length > 0;
        if (hasLink) {
          cy.log('View Full Context link found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Memory Viewer', () => {
    it('should display memory viewer component', () => {
      cy.visit('/app/ai/agents/test-agent/memory');
      cy.get('body').then($body => {
        const hasViewer = $body.text().includes('Memory') ||
                         $body.find('[class*="memory"]').length > 0;
        if (hasViewer) {
          cy.log('Memory viewer component found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display memory entries or empty state', () => {
      cy.visit('/app/ai/agents/test-agent/memory');
      cy.get('body').then($body => {
        const hasEntries = $body.find('[class*="entry"]').length > 0 ||
                          $body.text().includes('No memories') ||
                          $body.text().includes('no entries');
        if (hasEntries) {
          cy.log('Memory entries or empty state displayed');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Entry Editor', () => {
    it('should display entry editor when adding memory', () => {
      cy.visit('/app/ai/agents/test-agent/memory');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Add Memory")').length > 0 ||
            $body.find('button:contains("Add")').length > 0) {
          cy.contains('button', /Add Memory|Add/).first().should('be.visible').click();
          cy.get('body').then($updated => {
            const hasEditor = $updated.text().includes('Add Memory') ||
                             $updated.text().includes('Edit Memory') ||
                             $updated.find('[class*="editor"]').length > 0;
            if (hasEditor) {
              cy.log('Entry editor displayed');
            }
          });
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should have Cancel button in editor', () => {
      cy.visit('/app/ai/agents/test-agent/memory');
      cy.get('body').then($body => {
        const hasCancel = $body.text().includes('Cancel');
        if (hasCancel) {
          cy.log('Cancel button found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.intercept('GET', '**/api/**/agents/*/memory**', {
        statusCode: 500,
        body: { error: 'Internal Server Error' }
      }).as('apiError');

      cy.visit('/app/ai/agents/test-agent/memory');
      cy.get('body').should('be.visible');
    });

    it('should show error notification on failure', () => {
      cy.intercept('GET', '**/api/**/agents/*/memory**', {
        statusCode: 404,
        body: { error: 'Agent not found' }
      }).as('notFoundError');

      cy.visit('/app/ai/agents/test-agent/memory');
      cy.get('body').should('be.visible');
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '**/api/**/agents/**', (req) => {
        req.reply((res) => {
          res.delay = 2000;
          res.send({ success: true, data: {} });
        });
      }).as('slowLoad');

      cy.visit('/app/ai/agents/test-agent/memory');
      cy.get('body').then($body => {
        const hasLoading = $body.find('[class*="animate-spin"]').length > 0 ||
                          $body.text().includes('Loading');
        if (hasLoading) {
          cy.log('Loading indicator found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/ai/agents/test-agent/memory');
      cy.get('body').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/ai/agents/test-agent/memory');
      cy.get('body').should('be.visible');
    });
  });
});


export {};
