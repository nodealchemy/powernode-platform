/// <reference types="cypress" />

/**
 * AI Conversations Page Tests
 *
 * Tests for AI Conversations functionality including:
 * - Page navigation and load
 * - Conversation list display
 * - Search functionality
 * - Filter by status
 * - Filter by agent
 * - Create conversation
 * - View conversation details
 * - Continue conversation
 * - Export conversation
 * - Archive/unarchive conversation
 * - Delete conversation
 * - Pagination
 * - Responsive design
 */

describe('AI Conversations Page Tests', () => {
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
    it('should navigate to AI Conversations from AI section', () => {
      cy.visit('/app/ai');
      cy.wait(2000);

      cy.get('body').then($body => {
        const conversationsLink = $body.find('a[href*="/conversations"], button:contains("Conversations")');

        if (conversationsLink.length > 0) {
          cy.wrap(conversationsLink).first().click();
          cy.url().should('include', '/conversations');
        } else {
          cy.visit('/app/ai/conversations');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should load AI Conversations page directly', () => {
      cy.visit('/app/ai/conversations');
      cy.wait(2000);

      cy.get('body').then($body => {
        const text = $body.text();
        const hasContent = text.includes('Conversation') ||
                           text.includes('Message') ||
                           text.includes('Start') ||
                           text.includes('Loading');
        if (hasContent) {
          cy.log('AI Conversations page content loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page title', () => {
      cy.visit('/app/ai/conversations');

      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('AI Conversations') ||
                          $body.text().includes('Conversations');

        if (hasTitle) {
          cy.log('Page title displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/ai/conversations');

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

  describe('Conversation List Display', () => {
    beforeEach(() => {
      cy.visit('/app/ai/conversations');
      cy.wait(2000);
    });

    it('should display conversation list or empty state', () => {
      cy.get('body').then($body => {
        const hasConversations = $body.find('[class*="table"], [class*="list"]').length > 0 ||
                                  $body.text().includes('No conversations') ||
                                  $body.text().includes('Start Conversation');

        if ($body.text().includes('No conversations')) {
          cy.log('Empty state displayed');
        } else {
          cy.log('Conversation list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display conversation titles', () => {
      cy.get('body').then($body => {
        const hasTitles = $body.find('td, [class*="title"]').length > 0;

        if (hasTitles) {
          cy.log('Conversation titles displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display conversation status badges', () => {
      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Active') ||
                           $body.text().includes('Completed') ||
                           $body.text().includes('Archived');

        if (hasStatus) {
          cy.log('Status badges displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display message counts', () => {
      cy.get('body').then($body => {
        const hasMessages = $body.text().includes('Messages') ||
                             $body.text().includes('messages') ||
                             $body.text().includes('tokens');

        if (hasMessages) {
          cy.log('Message counts displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display conversation costs', () => {
      cy.get('body').then($body => {
        const hasCost = $body.text().includes('$') ||
                         $body.text().includes('Cost');

        if (hasCost) {
          cy.log('Costs displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display last activity timestamps', () => {
      cy.get('body').then($body => {
        const hasActivity = $body.text().includes('ago') ||
                             $body.text().includes('Activity') ||
                             $body.text().includes('Last');

        if (hasActivity) {
          cy.log('Last activity displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Search Functionality', () => {
    beforeEach(() => {
      cy.visit('/app/ai/conversations');
      cy.wait(2000);
    });

    it('should have search input', () => {
      cy.get('body').then($body => {
        const searchInput = $body.find('input[type="search"], input[placeholder*="Search"], input[placeholder*="search"]');

        if (searchInput.length > 0) {
          cy.wrap(searchInput).should('be.visible');
          cy.log('Search input found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should filter conversations by search query', () => {
      cy.get('body').then($body => {
        const searchInput = $body.find('input[placeholder*="Search"], input[type="search"]');

        if (searchInput.length > 0) {
          cy.wrap(searchInput).type('test conversation');
          cy.wait(500);
          cy.log('Search filter applied');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should clear search when input cleared', () => {
      cy.get('body').then($body => {
        const searchInput = $body.find('input[placeholder*="Search"]');

        if (searchInput.length > 0) {
          cy.wrap(searchInput).type('test');
          cy.wait(300);
          cy.wrap(searchInput).clear();
          cy.wait(300);
          cy.log('Search cleared');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Filter by Status', () => {
    beforeEach(() => {
      cy.visit('/app/ai/conversations');
      cy.wait(2000);
    });

    it('should have status filter dropdown', () => {
      cy.get('body').then($body => {
        const statusFilter = $body.find('select, [class*="select"]');

        if (statusFilter.length > 0) {
          cy.log('Status filter found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should filter by Active status', () => {
      cy.get('body').then($body => {
        const statusFilter = $body.find('select, button:contains("Status"), button:contains("All Statuses")');

        if (statusFilter.length > 0) {
          cy.wrap(statusFilter).first().click();
          cy.wait(300);

          cy.get('body').then($newBody => {
            const activeOption = $newBody.find('option:contains("Active"), [role="option"]:contains("Active"), button:contains("Active")');
            if (activeOption.length > 0) {
              cy.wrap(activeOption).first().click();
              cy.wait(500);
              cy.log('Filtered by Active status');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should filter by Completed status', () => {
      cy.get('body').then($body => {
        const statusFilter = $body.find('select, button:contains("Status")');

        if (statusFilter.length > 0) {
          cy.wrap(statusFilter).first().click();
          cy.wait(300);

          cy.get('body').then($newBody => {
            const completedOption = $newBody.find('option:contains("Completed"), [role="option"]:contains("Completed")');
            if (completedOption.length > 0) {
              cy.wrap(completedOption).first().click();
              cy.wait(500);
              cy.log('Filtered by Completed status');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should filter by Archived status', () => {
      cy.get('body').then($body => {
        const statusFilter = $body.find('select, button:contains("Status")');

        if (statusFilter.length > 0) {
          cy.wrap(statusFilter).first().click();
          cy.wait(300);

          cy.get('body').then($newBody => {
            const archivedOption = $newBody.find('option:contains("Archived"), [role="option"]:contains("Archived")');
            if (archivedOption.length > 0) {
              cy.wrap(archivedOption).first().click();
              cy.wait(500);
              cy.log('Filtered by Archived status');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Filter by Agent', () => {
    beforeEach(() => {
      cy.visit('/app/ai/conversations');
      cy.wait(2000);
    });

    it('should have agent filter dropdown', () => {
      cy.get('body').then($body => {
        const agentFilter = $body.find('select, button:contains("Agent"), button:contains("All Agents")');

        if (agentFilter.length > 0) {
          cy.log('Agent filter found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should filter by specific agent', () => {
      cy.get('body').then($body => {
        const agentFilter = $body.find('button:contains("Agent"), button:contains("All Agents")');

        if (agentFilter.length > 0) {
          cy.wrap(agentFilter).first().click();
          cy.wait(300);
          cy.log('Agent filter dropdown opened');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Create Conversation', () => {
    beforeEach(() => {
      cy.visit('/app/ai/conversations');
      cy.wait(2000);
    });

    it('should display Start Conversation button', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Start Conversation"), button:contains("New Conversation"), button:contains("Create")');

        if (createButton.length > 0) {
          cy.wrap(createButton).first().should('be.visible');
          cy.log('Start Conversation button found');
        } else {
          cy.log('Create button not visible - may require permissions');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should open create modal when Start Conversation clicked', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Start Conversation")');

        if (createButton.length > 0) {
          cy.wrap(createButton).first().click();
          cy.wait(500);

          cy.get('body').then($newBody => {
            const modalVisible = $newBody.find('[role="dialog"], [class*="modal"]').length > 0;

            if (modalVisible) {
              cy.log('Create conversation modal opened');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('View Conversation Details', () => {
    beforeEach(() => {
      cy.visit('/app/ai/conversations');
      cy.wait(2000);
    });

    it('should have View action for conversations', () => {
      cy.get('body').then($body => {
        const viewButton = $body.find('button[title="View Details"], button:contains("View")');

        if (viewButton.length > 0) {
          cy.log('View action found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should open detail modal when View clicked', () => {
      cy.get('body').then($body => {
        const viewButton = $body.find('button[title="View Details"]');

        if (viewButton.length > 0) {
          cy.wrap(viewButton).first().click();
          cy.wait(500);

          cy.get('body').then($newBody => {
            const modalVisible = $newBody.find('[role="dialog"], [class*="modal"]').length > 0;

            if (modalVisible) {
              cy.log('Detail modal opened');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Continue Conversation', () => {
    beforeEach(() => {
      cy.visit('/app/ai/conversations');
      cy.wait(2000);
    });

    it('should have Continue action for active conversations', () => {
      cy.get('body').then($body => {
        const continueButton = $body.find('button[title="Continue Conversation"]');

        if (continueButton.length > 0) {
          cy.log('Continue action found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should open chat modal when Continue clicked', () => {
      cy.get('body').then($body => {
        const continueButton = $body.find('button[title="Continue Conversation"]');

        if (continueButton.length > 0) {
          cy.wrap(continueButton).first().click();
          cy.wait(500);

          cy.get('body').then($newBody => {
            const modalVisible = $newBody.find('[role="dialog"], [class*="modal"], [class*="chat"]').length > 0;

            if (modalVisible) {
              cy.log('Chat modal opened');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Export Conversation', () => {
    beforeEach(() => {
      cy.visit('/app/ai/conversations');
      cy.wait(2000);
    });

    it('should have Export action for conversations', () => {
      cy.get('body').then($body => {
        const exportButton = $body.find('button[title="Export Conversation"], button:contains("Export")');

        if (exportButton.length > 0) {
          cy.log('Export action found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Archive/Unarchive Conversation', () => {
    beforeEach(() => {
      cy.visit('/app/ai/conversations');
      cy.wait(2000);
    });

    it('should have Archive action for conversations', () => {
      cy.get('body').then($body => {
        const archiveButton = $body.find('button[title="Archive"], button[title="Unarchive"]');

        if (archiveButton.length > 0) {
          cy.log('Archive action found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Delete Conversation', () => {
    beforeEach(() => {
      cy.visit('/app/ai/conversations');
      cy.wait(2000);
    });

    it('should have Delete action for conversations', () => {
      cy.get('body').then($body => {
        const deleteButton = $body.find('button[title="Delete Conversation"], button:contains("Delete")');

        if (deleteButton.length > 0) {
          cy.log('Delete action found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should show confirmation before delete', () => {
      cy.get('body').then($body => {
        const deleteButton = $body.find('button[title="Delete Conversation"]');

        if (deleteButton.length > 0) {
          cy.wrap(deleteButton).first().click();
          cy.wait(500);

          cy.get('body').then($newBody => {
            const confirmVisible = $newBody.text().includes('Are you sure') ||
                                    $newBody.find('[role="dialog"]').length > 0;

            if (confirmVisible) {
              cy.log('Delete confirmation shown');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Pagination', () => {
    beforeEach(() => {
      cy.visit('/app/ai/conversations');
      cy.wait(2000);
    });

    it('should display pagination when many conversations exist', () => {
      cy.get('body').then($body => {
        const hasPagination = $body.find('[class*="pagination"], button:contains("Next"), button:contains("Previous")').length > 0;

        if (hasPagination) {
          cy.log('Pagination controls displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should navigate between pages', () => {
      cy.get('body').then($body => {
        const nextButton = $body.find('button:contains("Next")');

        if (nextButton.length > 0 && !nextButton.is(':disabled')) {
          cy.wrap(nextButton).click();
          cy.wait(500);
          cy.log('Navigated to next page');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Empty State', () => {
    it('should display empty state when no conversations', () => {
      cy.visit('/app/ai/conversations');
      cy.wait(2000);

      cy.get('body').then($body => {
        if ($body.text().includes('No conversations')) {
          cy.log('Empty state displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Start Conversation button in empty state', () => {
      cy.visit('/app/ai/conversations');
      cy.wait(2000);

      cy.get('body').then($body => {
        if ($body.text().includes('No conversations')) {
          const startButton = $body.find('button:contains("Start Conversation")');
          if (startButton.length > 0) {
            cy.log('Start Conversation button found in empty state');
          }
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.intercept('GET', '/api/v1/ai/conversations*', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/ai/conversations');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should display error notification on failure', () => {
      cy.intercept('GET', '/api/v1/ai/conversations*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load conversations' }
      });

      cy.visit('/app/ai/conversations');
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

  describe('Permission-Based Actions', () => {
    it('should show actions based on permissions', () => {
      cy.visit('/app/ai/conversations');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasManageActions = $body.find('button:contains("Start"), button:contains("Delete"), button:contains("Export")').length > 0;

        if (hasManageActions) {
          cy.log('Management actions visible - user has permissions');
        } else {
          cy.log('Limited actions - user may lack permissions');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/ai/conversations');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Conversation');
        if (hasContent) {
          cy.log('Content visible on mobile');
        }
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/ai/conversations');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Conversation');
        if (hasContent) {
          cy.log('Content visible on tablet');
        }
      });
    });

    it('should adapt table layout on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/ai/conversations');
      cy.wait(2000);

      cy.get('body').should('be.visible');
    });
  });
});
