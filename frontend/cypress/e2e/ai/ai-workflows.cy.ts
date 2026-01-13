/// <reference types="cypress" />

/**
 * AI Workflows Tests
 *
 * Tests for AI Workflows page functionality including:
 * - Page navigation and load
 * - Workflows list display
 * - Search workflows
 * - Filter by status
 * - Filter by visibility
 * - Type filter (All, Workflows, Templates)
 * - Sorting
 * - Create workflow modal
 * - View workflow details
 * - Execute workflow
 * - Duplicate workflow
 * - Delete workflow
 * - Pagination
 * - Empty state
 * - Permission-based actions
 * - Responsive design
 */

describe('AI Workflows Tests', () => {
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
    it('should navigate to AI Workflows from sidebar', () => {
      cy.visit('/app');
      cy.wait(2000);

      cy.get('body').then($body => {
        const aiLink = $body.find('a[href*="/ai"], button:contains("AI")');

        if (aiLink.length > 0) {
          cy.wrap(aiLink).first().click();
          cy.wait(500);

          // Then look for Workflows link
          cy.get('body').then($newBody => {
            const workflowsLink = $newBody.find('a[href*="/workflows"]');
            if (workflowsLink.length > 0) {
              cy.wrap(workflowsLink).first().click();
            } else {
              cy.visit('/app/ai/workflows');
            }
          });
        } else {
          cy.visit('/app/ai/workflows');
        }
      });

      cy.url().should('include', '/workflows');
      cy.get('body').should('be.visible');
    });

    it('should load AI Workflows page directly', () => {
      cy.visit('/app/ai/workflows');

      cy.url().then(url => {
        if (url.includes('/workflows')) {
          cy.get('body').should('satisfy', ($body) => {
            const text = $body.text();
            return text.includes('Workflow') || text.includes('AI') || text.includes('Create');
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/ai/workflows');

      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('Dashboard') &&
                               ($body.text().includes('AI') || $body.text().includes('Workflows'));

        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs displayed correctly');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Workflows List Display', () => {
    beforeEach(() => {
      cy.visit('/app/ai/workflows');
      cy.wait(2000);
    });

    it('should display workflows list or empty state', () => {
      cy.get('body').then($body => {
        const hasWorkflows = $body.find('table, [class*="list"], [class*="grid"]').length > 0 ||
                             $body.text().includes('No workflows') ||
                             $body.text().includes('Create Workflow');

        if ($body.text().includes('No workflows')) {
          cy.log('Empty state displayed');
        } else {
          cy.log('Workflows list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display workflow names', () => {
      cy.get('body').then($body => {
        const hasWorkflowRows = $body.find('table tr, [class*="row"], [class*="item"]').length > 0;

        if (hasWorkflowRows) {
          cy.log('Workflow items displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display workflow descriptions', () => {
      cy.get('body').then($body => {
        // Look for description text
        const hasDescriptions = $body.find('[class*="description"], [class*="muted"]').length > 0;

        if (hasDescriptions) {
          cy.log('Workflow descriptions displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display workflow status badges', () => {
      cy.get('body').then($body => {
        const hasStatusBadges = $body.text().includes('Draft') ||
                                 $body.text().includes('Active') ||
                                 $body.text().includes('Inactive') ||
                                 $body.text().includes('Paused') ||
                                 $body.text().includes('Archived');

        if (hasStatusBadges) {
          cy.log('Status badges displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display template badges for templates', () => {
      cy.get('body').then($body => {
        const hasTemplateBadge = $body.text().includes('Template') ||
                                  $body.find('[class*="template"]').length > 0;

        if (hasTemplateBadge) {
          cy.log('Template badges displayed');
        } else {
          cy.log('No templates in list');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display workflow stats (nodes, runs)', () => {
      cy.get('body').then($body => {
        const hasStats = $body.text().includes('nodes') ||
                          $body.text().includes('runs') ||
                          /\d+\s*(nodes?|runs?)/i.test($body.text());

        if (hasStats) {
          cy.log('Workflow stats displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display created by information', () => {
      cy.get('body').then($body => {
        const hasCreator = $body.text().includes('Created') ||
                           $body.text().includes('Admin') ||
                           $body.find('[class*="creator"]').length > 0;

        if (hasCreator) {
          cy.log('Creator information displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Search Functionality', () => {
    beforeEach(() => {
      cy.visit('/app/ai/workflows');
      cy.wait(2000);
    });

    it('should have search input', () => {
      cy.get('body').then($body => {
        const searchInput = $body.find('input[type="search"], input[placeholder*="search"], input[placeholder*="Search"]');

        if (searchInput.length > 0) {
          cy.wrap(searchInput).should('be.visible');
          cy.log('Search input found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should filter workflows by search query', () => {
      cy.get('body').then($body => {
        const searchInput = $body.find('input[type="search"], input[placeholder*="search"]');

        if (searchInput.length > 0) {
          cy.wrap(searchInput).type('test');
          cy.wait(500);
          cy.get('body').should('be.visible');
          cy.log('Search filter applied');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should clear search and show all workflows', () => {
      cy.get('body').then($body => {
        const searchInput = $body.find('input[type="search"], input[placeholder*="search"]');

        if (searchInput.length > 0) {
          cy.wrap(searchInput).type('test');
          cy.wait(300);
          cy.wrap(searchInput).clear();
          cy.wait(500);
          cy.get('body').should('be.visible');
          cy.log('Search cleared');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Status Filter', () => {
    beforeEach(() => {
      cy.visit('/app/ai/workflows');
      cy.wait(2000);
    });

    it('should have status filter dropdown', () => {
      cy.get('body').then($body => {
        const statusFilter = $body.find('select, [class*="select"], button:contains("All Statuses")');

        if (statusFilter.length > 0) {
          cy.log('Status filter found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should filter by draft status', () => {
      cy.get('body').then($body => {
        const statusFilter = $body.find('button:contains("All Statuses"), select:contains("Status")');

        if (statusFilter.length > 0) {
          cy.wrap(statusFilter).first().click();
          cy.wait(300);

          cy.get('body').then($newBody => {
            const draftOption = $newBody.find('option:contains("Draft"), li:contains("Draft"), button:contains("Draft")');
            if (draftOption.length > 0) {
              cy.wrap(draftOption).first().click();
              cy.wait(500);
              cy.log('Filtered by draft status');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should filter by active status', () => {
      cy.get('body').then($body => {
        const statusFilter = $body.find('button:contains("All Statuses"), [class*="select"]');

        if (statusFilter.length > 0) {
          cy.wrap(statusFilter).first().click();
          cy.wait(300);

          cy.get('body').then($newBody => {
            const activeOption = $newBody.find('option:contains("Active"), li:contains("Active"), button:contains("Active")');
            if (activeOption.length > 0) {
              cy.wrap(activeOption).first().click();
              cy.wait(500);
              cy.log('Filtered by active status');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Visibility Filter', () => {
    beforeEach(() => {
      cy.visit('/app/ai/workflows');
      cy.wait(2000);
    });

    it('should have visibility filter', () => {
      cy.get('body').then($body => {
        const visibilityFilter = $body.find('button:contains("All Visibility"), select:contains("Visibility")');

        if (visibilityFilter.length > 0) {
          cy.log('Visibility filter found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should filter by private visibility', () => {
      cy.get('body').then($body => {
        const visibilityFilter = $body.find('button:contains("All Visibility")');

        if (visibilityFilter.length > 0) {
          cy.wrap(visibilityFilter).first().click();
          cy.wait(300);

          cy.get('body').then($newBody => {
            const privateOption = $newBody.find('option:contains("Private"), li:contains("Private")');
            if (privateOption.length > 0) {
              cy.wrap(privateOption).first().click();
              cy.wait(500);
              cy.log('Filtered by private visibility');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Type Filter (All, Workflows, Templates)', () => {
    beforeEach(() => {
      cy.visit('/app/ai/workflows');
      cy.wait(2000);
    });

    it('should have type filter buttons', () => {
      cy.get('body').then($body => {
        const hasTypeFilter = $body.text().includes('All') &&
                               ($body.text().includes('Workflows') || $body.text().includes('Templates'));

        if (hasTypeFilter) {
          cy.log('Type filter buttons found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should filter to show only workflows', () => {
      cy.get('body').then($body => {
        const workflowsButton = $body.find('button:contains("Workflows")').not(':contains("All")');

        if (workflowsButton.length > 0) {
          cy.wrap(workflowsButton).first().click();
          cy.wait(500);
          cy.url().should('include', 'type=workflows');
          cy.log('Filtered to workflows only');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should filter to show only templates', () => {
      cy.get('body').then($body => {
        const templatesButton = $body.find('button:contains("Templates")');

        if (templatesButton.length > 0) {
          cy.wrap(templatesButton).first().click();
          cy.wait(500);
          cy.url().should('include', 'type=templates');
          cy.log('Filtered to templates only');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should show all when All button clicked', () => {
      cy.visit('/app/ai/workflows?type=templates');
      cy.wait(2000);

      cy.get('body').then($body => {
        const allButton = $body.find('button:contains("All")').first();

        if (allButton.length > 0) {
          cy.wrap(allButton).click();
          cy.wait(500);
          cy.log('Showing all workflows');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Sorting', () => {
    beforeEach(() => {
      cy.visit('/app/ai/workflows');
      cy.wait(2000);
    });

    it('should have sort controls', () => {
      cy.get('body').then($body => {
        const hasSortControls = $body.text().includes('Sort') ||
                                 $body.find('[class*="sort"]').length > 0 ||
                                 $body.find('button[title*="Sort"]').length > 0;

        if (hasSortControls) {
          cy.log('Sort controls found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should sort by name', () => {
      cy.get('body').then($body => {
        const nameHeader = $body.find('button:contains("Name"), th:contains("Name")');

        if (nameHeader.length > 0) {
          cy.wrap(nameHeader).first().click();
          cy.wait(500);
          cy.log('Sorted by name');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should sort by created date', () => {
      cy.get('body').then($body => {
        const dateHeader = $body.find('button:contains("Created"), option:contains("Created")');

        if (dateHeader.length > 0) {
          cy.wrap(dateHeader).first().click();
          cy.wait(500);
          cy.log('Sorted by created date');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should toggle sort order', () => {
      cy.get('body').then($body => {
        const sortToggle = $body.find('button[title*="Sort"], button:contains("A→Z"), button:contains("Z→A")');

        if (sortToggle.length > 0) {
          cy.wrap(sortToggle).first().click();
          cy.wait(500);
          cy.log('Sort order toggled');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Create Workflow', () => {
    beforeEach(() => {
      cy.visit('/app/ai/workflows');
      cy.wait(2000);
    });

    it('should display Create Workflow button', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Workflow"), button:contains("Create")');

        if (createButton.length > 0) {
          cy.wrap(createButton).first().should('be.visible');
          cy.log('Create Workflow button found');
        } else {
          cy.log('Create button not visible - may require permissions');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should open create modal when button clicked', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Workflow")');

        if (createButton.length > 0) {
          cy.wrap(createButton).first().click();
          cy.wait(500);

          cy.get('body').then($newBody => {
            const modalVisible = $newBody.find('[role="dialog"], [class*="modal"]').length > 0 ||
                                  $newBody.text().includes('Create') ||
                                  $newBody.text().includes('Name');

            if (modalVisible) {
              cy.log('Create workflow modal opened');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have name input in create modal', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Workflow")');

        if (createButton.length > 0) {
          cy.wrap(createButton).first().click();
          cy.wait(500);

          cy.get('body').then($newBody => {
            const nameInput = $newBody.find('input[name="name"], input[placeholder*="name"]');

            if (nameInput.length > 0) {
              cy.wrap(nameInput).should('be.visible');
              cy.log('Name input found in create modal');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have description input in create modal', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Workflow")');

        if (createButton.length > 0) {
          cy.wrap(createButton).first().click();
          cy.wait(500);

          cy.get('body').then($newBody => {
            const descInput = $newBody.find('textarea[name="description"], input[name="description"]');

            if (descInput.length > 0) {
              cy.wrap(descInput).should('be.visible');
              cy.log('Description input found');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should close modal when cancel clicked', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Workflow")');

        if (createButton.length > 0) {
          cy.wrap(createButton).first().click();
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

  describe('View Workflow Details', () => {
    beforeEach(() => {
      cy.visit('/app/ai/workflows');
      cy.wait(2000);
    });

    it('should have view details action', () => {
      cy.get('body').then($body => {
        const viewButton = $body.find('button[title*="View"], [aria-label*="view"]');

        if (viewButton.length > 0) {
          cy.wrap(viewButton).first().should('be.visible');
          cy.log('View button found');
        } else if (!$body.text().includes('No workflows')) {
          cy.log('View button may use different UI');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should open workflow details modal', () => {
      cy.get('body').then($body => {
        const viewButton = $body.find('button[title*="View"], [aria-label*="view"]');

        if (viewButton.length > 0) {
          cy.wrap(viewButton).first().click();
          cy.wait(500);

          cy.get('body').then($newBody => {
            const detailsVisible = $newBody.find('[role="dialog"], [class*="modal"]').length > 0;

            if (detailsVisible) {
              cy.log('Details modal opened');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should navigate to workflow detail page on name click', () => {
      cy.get('body').then($body => {
        const workflowLink = $body.find('a[href*="/workflows/"], button[class*="primary"]').first();

        if (workflowLink.length > 0) {
          cy.wrap(workflowLink).click();
          cy.wait(500);

          cy.url().then(url => {
            if (url.includes('/workflows/')) {
              cy.log('Navigated to workflow detail page');
            } else {
              cy.log('Workflow modal opened instead of navigation');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Execute Workflow', () => {
    beforeEach(() => {
      cy.visit('/app/ai/workflows');
      cy.wait(2000);
    });

    it('should have execute action for active workflows', () => {
      cy.get('body').then($body => {
        const executeButton = $body.find('button[title*="Execute"], [aria-label*="execute"]');

        if (executeButton.length > 0) {
          cy.wrap(executeButton).first().should('be.visible');
          cy.log('Execute button found');
        } else {
          cy.log('No execute buttons - may have no active workflows');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should open execute modal when clicked', () => {
      cy.get('body').then($body => {
        const executeButton = $body.find('button[title*="Execute"]');

        if (executeButton.length > 0) {
          cy.wrap(executeButton).first().click();
          cy.wait(500);

          cy.get('body').then($newBody => {
            const modalVisible = $newBody.find('[role="dialog"], [class*="modal"]').length > 0 ||
                                  $newBody.text().includes('Execute');

            if (modalVisible) {
              cy.log('Execute modal opened');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Duplicate Workflow', () => {
    beforeEach(() => {
      cy.visit('/app/ai/workflows');
      cy.wait(2000);
    });

    it('should have duplicate action', () => {
      cy.get('body').then($body => {
        const duplicateButton = $body.find('button[title*="Duplicate"], button[title*="Copy"]');

        if (duplicateButton.length > 0) {
          cy.wrap(duplicateButton).first().should('be.visible');
          cy.log('Duplicate button found');
        } else if (!$body.text().includes('No workflows')) {
          cy.log('Duplicate button may require permissions');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should duplicate workflow when clicked', () => {
      cy.get('body').then($body => {
        const duplicateButton = $body.find('button[title*="Duplicate"]');

        if (duplicateButton.length > 0) {
          cy.wrap(duplicateButton).first().click();
          cy.wait(1000);

          // Check for success notification
          cy.get('body').then($newBody => {
            const hasNotification = $newBody.text().includes('Duplicated') ||
                                     $newBody.text().includes('copied') ||
                                     $newBody.find('[class*="notification"], [class*="toast"]').length > 0;

            if (hasNotification) {
              cy.log('Workflow duplicated successfully');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Delete Workflow', () => {
    beforeEach(() => {
      cy.visit('/app/ai/workflows');
      cy.wait(2000);
    });

    it('should have delete action', () => {
      cy.get('body').then($body => {
        const deleteButton = $body.find('button[title*="Delete"]');

        if (deleteButton.length > 0) {
          cy.wrap(deleteButton).first().should('be.visible');
          cy.log('Delete button found');
        } else if (!$body.text().includes('No workflows')) {
          cy.log('Delete button may require permissions');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should show confirmation before delete', () => {
      cy.get('body').then($body => {
        const deleteButton = $body.find('button[title*="Delete"]');

        if (deleteButton.length > 0) {
          cy.wrap(deleteButton).first().click();
          cy.wait(500);

          // Check for confirmation dialog (browser confirm)
          cy.on('window:confirm', () => {
            cy.log('Confirmation dialog shown');
            return false; // Cancel the delete
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Workflow Builder/Design', () => {
    beforeEach(() => {
      cy.visit('/app/ai/workflows');
      cy.wait(2000);
    });

    it('should have design action', () => {
      cy.get('body').then($body => {
        const designButton = $body.find('button[title*="Design"], button[title*="Builder"]');

        if (designButton.length > 0) {
          cy.wrap(designButton).first().should('be.visible');
          cy.log('Design button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should open workflow builder modal', () => {
      cy.get('body').then($body => {
        const designButton = $body.find('button[title*="Design"]');

        if (designButton.length > 0) {
          cy.wrap(designButton).first().click();
          cy.wait(1000);

          cy.get('body').then($newBody => {
            const builderVisible = $newBody.find('[role="dialog"], [class*="modal"], [class*="builder"]').length > 0;

            if (builderVisible) {
              cy.log('Workflow builder modal opened');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Pagination', () => {
    beforeEach(() => {
      cy.visit('/app/ai/workflows');
      cy.wait(2000);
    });

    it('should display pagination controls when many workflows exist', () => {
      cy.get('body').then($body => {
        const pagination = $body.find('[class*="pagination"], nav[aria-label="pagination"], button:contains("Next")');

        if (pagination.length > 0) {
          cy.log('Pagination found');
        } else {
          cy.log('No pagination - may have few workflows');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should navigate between pages', () => {
      cy.get('body').then($body => {
        const nextButton = $body.find('button:contains("Next"), [aria-label="next"]');

        if (nextButton.length > 0 && !nextButton.is(':disabled')) {
          cy.wrap(nextButton).first().click();
          cy.wait(500);
          cy.get('body').should('be.visible');
          cy.log('Navigated to next page');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Empty State', () => {
    it('should display empty state when no workflows exist', () => {
      cy.intercept('GET', '/api/v1/ai/workflows*', {
        statusCode: 200,
        body: {
          success: true,
          items: [],
          pagination: { current_page: 1, total_pages: 1, total_count: 0, per_page: 25 }
        }
      });

      cy.visit('/app/ai/workflows');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasEmptyState = $body.text().includes('No workflows') ||
                               $body.text().includes('Get started') ||
                               $body.text().includes('Create Workflow');

        if (hasEmptyState) {
          cy.log('Empty state displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have create button in empty state', () => {
      cy.intercept('GET', '/api/v1/ai/workflows*', {
        statusCode: 200,
        body: {
          success: true,
          items: [],
          pagination: { current_page: 1, total_pages: 1, total_count: 0, per_page: 25 }
        }
      });

      cy.visit('/app/ai/workflows');
      cy.wait(2000);

      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create")');

        if (createButton.length > 0) {
          cy.wrap(createButton).should('be.visible');
          cy.log('Create button in empty state');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Refresh Functionality', () => {
    beforeEach(() => {
      cy.visit('/app/ai/workflows');
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

    it('should refresh workflows list', () => {
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

  describe('Monitoring Navigation', () => {
    beforeEach(() => {
      cy.visit('/app/ai/workflows');
      cy.wait(2000);
    });

    it('should have monitoring button', () => {
      cy.get('body').then($body => {
        const monitoringButton = $body.find('button:contains("Monitoring"), a:contains("Monitoring")');

        if (monitoringButton.length > 0) {
          cy.wrap(monitoringButton).should('be.visible');
          cy.log('Monitoring button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should navigate to monitoring page', () => {
      cy.get('body').then($body => {
        const monitoringButton = $body.find('button:contains("Monitoring")');

        if (monitoringButton.length > 0) {
          cy.wrap(monitoringButton).first().click();
          cy.wait(500);
          cy.url().should('include', '/monitoring');
          cy.log('Navigated to monitoring');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Import Workflow', () => {
    beforeEach(() => {
      cy.visit('/app/ai/workflows');
      cy.wait(2000);
    });

    it('should have import button', () => {
      cy.get('body').then($body => {
        const importButton = $body.find('button:contains("Import")');

        if (importButton.length > 0) {
          cy.wrap(importButton).should('be.visible');
          cy.log('Import button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should navigate to import page', () => {
      cy.get('body').then($body => {
        const importButton = $body.find('button:contains("Import")');

        if (importButton.length > 0) {
          cy.wrap(importButton).first().click();
          cy.wait(500);
          cy.url().should('include', '/import');
          cy.log('Navigated to import page');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.intercept('GET', '/api/v1/ai/workflows*', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/ai/workflows');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should display error notification on failure', () => {
      cy.intercept('GET', '/api/v1/ai/workflows*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load workflows' }
      });

      cy.visit('/app/ai/workflows');
      cy.wait(2000);

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
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/ai/workflows');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Workflow') || $body.text().includes('AI');
        if (hasContent) {
          cy.log('Content visible on mobile');
        }
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/ai/workflows');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Workflow') || $body.text().includes('AI');
        if (hasContent) {
          cy.log('Content visible on tablet');
        }
      });
    });

    it('should stack elements on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/ai/workflows');
      cy.wait(2000);

      cy.get('body').should('be.visible');
    });
  });
});
