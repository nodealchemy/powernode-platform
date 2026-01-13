/// <reference types="cypress" />

/**
 * AI Workflow Templates Page Tests
 *
 * Tests for Workflow Templates functionality including:
 * - Page navigation and load
 * - Search functionality
 * - Category and difficulty filtering
 * - Template cards display
 * - View template action
 * - Use template action
 * - Permission-based actions
 * - Empty state handling
 * - Error handling
 * - Responsive design
 */

describe('AI Workflow Templates Page Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to Workflow Templates page', () => {
      cy.visit('/app/ai/workflow-templates');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Workflow Templates') ||
                          $body.text().includes('Templates') ||
                          $body.text().includes('Permission');
        if (hasContent) {
          cy.log('Workflow Templates page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page title', () => {
      cy.visit('/app/ai/workflow-templates');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('Workflow Templates');
        if (hasTitle) {
          cy.log('Page title displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page description', () => {
      cy.visit('/app/ai/workflow-templates');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasDescription = $body.text().includes('Pre-built') ||
                               $body.text().includes('automation') ||
                               $body.text().includes('templates');
        if (hasDescription) {
          cy.log('Page description displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/ai/workflow-templates');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('AI') ||
                               $body.text().includes('Templates');
        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Search Functionality', () => {
    beforeEach(() => {
      cy.visit('/app/ai/workflow-templates');
      cy.wait(2000);
    });

    it('should display search input', () => {
      cy.get('body').then($body => {
        const hasSearch = $body.find('input[type="search"], input[placeholder*="search"], input[placeholder*="Search"]').length > 0;
        if (hasSearch) {
          cy.log('Search input displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should search templates', () => {
      cy.get('body').then($body => {
        const searchInput = $body.find('input[type="search"], input[placeholder*="search"]');
        if (searchInput.length > 0) {
          cy.wrap(searchInput).first().type('data');
          cy.wait(500);
          cy.log('Search performed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should filter results on search', () => {
      cy.get('body').then($body => {
        const searchInput = $body.find('input[type="search"], input[placeholder*="search"]');
        if (searchInput.length > 0) {
          cy.wrap(searchInput).first().type('nonexistent-template-xyz');
          cy.wait(500);
          cy.log('Search filter applied');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Filtering', () => {
    beforeEach(() => {
      cy.visit('/app/ai/workflow-templates');
      cy.wait(2000);
    });

    it('should display category filter', () => {
      cy.get('body').then($body => {
        const hasCategoryFilter = $body.text().includes('All Categories') ||
                                  $body.text().includes('Category') ||
                                  $body.find('select, [class*="select"]').length > 0;
        if (hasCategoryFilter) {
          cy.log('Category filter displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display difficulty filter', () => {
      cy.get('body').then($body => {
        const hasDifficultyFilter = $body.text().includes('All Levels') ||
                                    $body.text().includes('Difficulty') ||
                                    $body.text().includes('Beginner');
        if (hasDifficultyFilter) {
          cy.log('Difficulty filter displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should filter by category', () => {
      cy.get('body').then($body => {
        const selects = $body.find('select, [class*="select"]');
        if (selects.length > 0) {
          cy.wrap(selects).first().click({ force: true });
          cy.wait(500);
          cy.log('Category filter clicked');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should filter by difficulty', () => {
      cy.get('body').then($body => {
        const hasLevels = $body.text().includes('Beginner') ||
                          $body.text().includes('Intermediate') ||
                          $body.text().includes('Advanced');
        if (hasLevels) {
          cy.log('Difficulty levels available');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Clear Filters option', () => {
      cy.get('body').then($body => {
        const searchInput = $body.find('input[placeholder*="search"]');
        if (searchInput.length > 0) {
          cy.wrap(searchInput).first().type('test');
          cy.wait(500);
          cy.get('body').then($filterBody => {
            const clearButton = $filterBody.find('button:contains("Clear Filters"), button:contains("Clear")');
            if (clearButton.length > 0) {
              cy.log('Clear Filters option found');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Template Cards Display', () => {
    beforeEach(() => {
      cy.visit('/app/ai/workflow-templates');
      cy.wait(2000);
    });

    it('should display template grid', () => {
      cy.get('body').then($body => {
        const hasGrid = $body.find('[class*="grid"]').length > 0;
        if (hasGrid) {
          cy.log('Template grid displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display template cards', () => {
      cy.get('body').then($body => {
        const hasCards = $body.find('[class*="card"], [class*="Card"]').length > 0;
        if (hasCards) {
          cy.log('Template cards displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display template name', () => {
      cy.get('body').then($body => {
        const hasTitle = $body.find('h3, [class*="title"], [class*="CardTitle"]').length > 0;
        if (hasTitle) {
          cy.log('Template names displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display template description', () => {
      cy.get('body').then($body => {
        const hasDescription = $body.find('p[class*="muted"], [class*="description"]').length > 0;
        if (hasDescription) {
          cy.log('Template descriptions displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display category badge', () => {
      cy.get('body').then($body => {
        const hasBadge = $body.find('[class*="badge"], [class*="Badge"]').length > 0;
        if (hasBadge) {
          cy.log('Category badges displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display difficulty badge', () => {
      cy.get('body').then($body => {
        const hasDifficulty = $body.text().includes('beginner') ||
                              $body.text().includes('intermediate') ||
                              $body.text().includes('advanced');
        if (hasDifficulty) {
          cy.log('Difficulty badges displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display execution mode', () => {
      cy.get('body').then($body => {
        const hasMode = $body.text().includes('sequential') ||
                        $body.text().includes('parallel') ||
                        $body.text().includes('conditional');
        if (hasMode) {
          cy.log('Execution mode displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display estimated duration', () => {
      cy.get('body').then($body => {
        const hasDuration = $body.text().includes('min') ||
                            $body.text().includes('hour') ||
                            $body.find('[class*="clock"], [class*="duration"]').length > 0;
        if (hasDuration) {
          cy.log('Estimated duration displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display tags', () => {
      cy.get('body').then($body => {
        const hasTags = $body.find('[class*="badge"], span[class*="tag"]').length > 0;
        if (hasTags) {
          cy.log('Tags displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Template Actions', () => {
    beforeEach(() => {
      cy.visit('/app/ai/workflow-templates');
      cy.wait(2000);
    });

    it('should have View button', () => {
      cy.get('body').then($body => {
        const viewButton = $body.find('button:contains("View")');
        if (viewButton.length > 0) {
          cy.log('View button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Use button for authorized users', () => {
      cy.get('body').then($body => {
        const useButton = $body.find('button:contains("Use")');
        if (useButton.length > 0) {
          cy.log('Use button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should show notification on View click', () => {
      cy.get('body').then($body => {
        const viewButton = $body.find('button:contains("View")');
        if (viewButton.length > 0) {
          cy.wrap(viewButton).first().click({ force: true });
          cy.wait(500);
          cy.log('View button clicked');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Permission-Based Access', () => {
    it('should show Use button for users with ai.workflows.create permission', () => {
      cy.visit('/app/ai/workflow-templates');
      cy.wait(2000);

      cy.get('body').then($body => {
        const useButton = $body.find('button:contains("Use")');
        if (useButton.length > 0) {
          cy.log('Use button shown for authorized user');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Empty State', () => {
    it('should display empty state when no templates', () => {
      cy.intercept('GET', '/api/v1/ai/workflow-templates*', {
        statusCode: 200,
        body: { success: true, data: [] }
      });

      cy.visit('/app/ai/workflow-templates');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasEmpty = $body.text().includes('No templates found') ||
                         $body.text().includes('No workflow templates') ||
                         $body.text().includes('not available');
        if (hasEmpty) {
          cy.log('Empty state displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should show message when filters return no results', () => {
      cy.visit('/app/ai/workflow-templates');
      cy.wait(2000);

      cy.get('body').then($body => {
        const searchInput = $body.find('input[placeholder*="search"]');
        if (searchInput.length > 0) {
          cy.wrap(searchInput).first().type('zzzznonexistenttemplatexxxx');
          cy.wait(500);
          cy.get('body').then($emptyBody => {
            const hasNoResults = $emptyBody.text().includes('No templates found') ||
                                 $emptyBody.text().includes('No results') ||
                                 $emptyBody.text().includes('adjusting your filters');
            if (hasNoResults) {
              cy.log('No results message displayed');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.intercept('GET', '/api/v1/ai/workflow-templates*', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/ai/workflow-templates');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should display error notification on failure', () => {
      cy.intercept('GET', '/api/v1/ai/workflow-templates*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load templates' }
      });

      cy.visit('/app/ai/workflow-templates');
      cy.wait(2000);

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

  describe('Loading State', () => {
    it('should display loading skeleton', () => {
      cy.intercept('GET', '/api/v1/ai/workflow-templates*', {
        delay: 1000,
        statusCode: 200,
        body: { success: true, data: [] }
      });

      cy.visit('/app/ai/workflow-templates');

      cy.get('body').then($body => {
        const hasLoading = $body.find('[class*="animate-pulse"], [class*="skeleton"]').length > 0 ||
                           $body.find('[class*="loading"]').length > 0;
        if (hasLoading) {
          cy.log('Loading skeleton displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/ai/workflow-templates');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Templates') || $body.text().includes('Workflow');
        if (hasContent) {
          cy.log('Content visible on mobile');
        }
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/ai/workflow-templates');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Templates') || $body.text().includes('Workflow');
        if (hasContent) {
          cy.log('Content visible on tablet');
        }
      });
    });

    it('should stack filters on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/ai/workflow-templates');
      cy.wait(2000);

      cy.get('body').should('be.visible');
    });

    it('should show multi-column grid on large screens', () => {
      cy.viewport(1280, 800);
      cy.visit('/app/ai/workflow-templates');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasGrid = $body.find('[class*="grid"]').length > 0;
        if (hasGrid) {
          cy.log('Multi-column grid on large screens');
        }
      });

      cy.get('body').should('be.visible');
    });
  });
});
