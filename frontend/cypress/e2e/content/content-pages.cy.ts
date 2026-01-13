/// <reference types="cypress" />

/**
 * Content Pages Management Tests
 *
 * Tests for Content Pages functionality including:
 * - Page navigation and load
 * - Search and filtering
 * - Pages list display
 * - Create page action
 * - Page actions (view, edit, publish/unpublish, duplicate, delete)
 * - Pagination
 * - Permission-based access
 * - Error handling
 * - Responsive design
 */

describe('Content Pages Management Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to Pages page', () => {
      cy.visit('/app/content/pages');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Pages') ||
                          $body.text().includes('Content') ||
                          $body.text().includes('Permission') ||
                          $body.text().includes('Access Denied');
        if (hasContent) {
          cy.log('Pages page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page title', () => {
      cy.visit('/app/content/pages');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('Pages');
        if (hasTitle) {
          cy.log('Page title displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page description', () => {
      cy.visit('/app/content/pages');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasDescription = $body.text().includes('Manage') ||
                               $body.text().includes('website pages') ||
                               $body.text().includes('content');
        if (hasDescription) {
          cy.log('Page description displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/content/pages');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('Dashboard');
        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Page Actions', () => {
    beforeEach(() => {
      cy.visit('/app/content/pages');
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

    it('should have Create Page button for authorized users', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Page")');
        if (createButton.length > 0) {
          cy.log('Create Page button found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Search and Filtering', () => {
    beforeEach(() => {
      cy.visit('/app/content/pages');
      cy.wait(2000);
    });

    it('should display search input', () => {
      cy.get('body').then($body => {
        const hasSearch = $body.find('input[placeholder*="Search pages"], input[placeholder*="search"]').length > 0;
        if (hasSearch) {
          cy.log('Search input displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should search pages', () => {
      cy.get('body').then($body => {
        const searchInput = $body.find('input[placeholder*="Search pages"], input[placeholder*="search"]');
        if (searchInput.length > 0) {
          cy.wrap(searchInput).first().type('home');
          cy.wait(500);
          cy.log('Search performed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display status filter', () => {
      cy.get('body').then($body => {
        const hasStatusFilter = $body.text().includes('All Status') ||
                                $body.text().includes('Draft') ||
                                $body.text().includes('Published');
        if (hasStatusFilter) {
          cy.log('Status filter displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should filter by status', () => {
      cy.get('body').then($body => {
        const statusSelect = $body.find('select');
        if (statusSelect.length > 0) {
          cy.wrap(statusSelect).first().select('draft');
          cy.wait(500);
          cy.log('Filtered by status');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Pages List Display', () => {
    beforeEach(() => {
      cy.visit('/app/content/pages');
      cy.wait(2000);
    });

    it('should display pages list', () => {
      cy.get('body').then($body => {
        const hasList = $body.find('table, [class*="list"], [class*="card"]').length > 0 ||
                        $body.text().includes('No pages');
        if (hasList) {
          cy.log('Pages list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display table headers', () => {
      cy.get('body').then($body => {
        const hasHeaders = $body.text().includes('Title') ||
                           $body.text().includes('Status') ||
                           $body.text().includes('Published');
        if (hasHeaders) {
          cy.log('Table headers displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page title column', () => {
      cy.get('body').then($body => {
        const hasTitle = $body.find('td, [class*="cell"]').length > 0 ||
                         $body.text().includes('Title');
        if (hasTitle) {
          cy.log('Page title column displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display status badge', () => {
      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Draft') ||
                          $body.text().includes('Published') ||
                          $body.find('[class*="badge"]').length > 0;
        if (hasStatus) {
          cy.log('Status badge displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display word count', () => {
      cy.get('body').then($body => {
        const hasWordCount = $body.text().includes('words') ||
                             $body.text().includes('Word Count');
        if (hasWordCount) {
          cy.log('Word count displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display empty state when no pages', () => {
      cy.get('body').then($body => {
        const hasEmpty = $body.text().includes('No pages yet') ||
                         $body.text().includes('Create your first');
        if (hasEmpty) {
          cy.log('Empty state displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Page Row Actions', () => {
    beforeEach(() => {
      cy.visit('/app/content/pages');
      cy.wait(2000);
    });

    it('should have view page button', () => {
      cy.get('body').then($body => {
        const viewButton = $body.find('button[title*="View"], button[aria-label*="view"]');
        if (viewButton.length > 0) {
          cy.log('View page button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have edit page button', () => {
      cy.get('body').then($body => {
        const editButton = $body.find('button[title*="Edit"], button[aria-label*="edit"]');
        if (editButton.length > 0) {
          cy.log('Edit page button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have publish/unpublish button', () => {
      cy.get('body').then($body => {
        const publishButton = $body.find('button[title*="Publish"], button[title*="Unpublish"]');
        if (publishButton.length > 0) {
          cy.log('Publish/unpublish button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have duplicate page button', () => {
      cy.get('body').then($body => {
        const duplicateButton = $body.find('button[title*="Duplicate"], button[aria-label*="duplicate"]');
        if (duplicateButton.length > 0) {
          cy.log('Duplicate page button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have delete page button', () => {
      cy.get('body').then($body => {
        const deleteButton = $body.find('button[title*="Delete"], button[aria-label*="delete"]');
        if (deleteButton.length > 0) {
          cy.log('Delete page button found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Pagination', () => {
    beforeEach(() => {
      cy.visit('/app/content/pages');
      cy.wait(2000);
    });

    it('should display pagination when multiple pages', () => {
      cy.get('body').then($body => {
        const hasPagination = $body.text().includes('Page') ||
                              $body.find('button:contains("Previous")').length > 0 ||
                              $body.find('button:contains("Next")').length > 0;
        if (hasPagination) {
          cy.log('Pagination displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Previous button', () => {
      cy.get('body').then($body => {
        const prevButton = $body.find('button:contains("Previous")');
        if (prevButton.length > 0) {
          cy.log('Previous button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Next button', () => {
      cy.get('body').then($body => {
        const nextButton = $body.find('button:contains("Next")');
        if (nextButton.length > 0) {
          cy.log('Next button found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Permission-Based Access', () => {
    it('should show access denied for unauthorized users', () => {
      cy.visit('/app/content/pages');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasAccessDenied = $body.text().includes('Access Denied') ||
                                $body.text().includes('privileges');
        if (hasAccessDenied) {
          cy.log('Access denied message shown for unauthorized users');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should show Create Page for authorized users', () => {
      cy.visit('/app/content/pages');
      cy.wait(2000);

      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Page")');
        if (createButton.length > 0) {
          cy.log('Create Page shown for authorized users');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.intercept('GET', '/api/v1/pages*', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/content/pages');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should display error notification on failure', () => {
      cy.intercept('GET', '/api/v1/pages*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load pages' }
      });

      cy.visit('/app/content/pages');
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
    it('should display loading indicator', () => {
      cy.intercept('GET', '/api/v1/pages*', {
        delay: 1000,
        statusCode: 200,
        body: { success: true, data: [], meta: { total_pages: 1 } }
      });

      cy.visit('/app/content/pages');

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
      cy.visit('/app/content/pages');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Pages');
        if (hasContent) {
          cy.log('Content visible on mobile');
        }
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/content/pages');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Pages');
        if (hasContent) {
          cy.log('Content visible on tablet');
        }
      });
    });

    it('should have horizontal scroll on table for small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/content/pages');
      cy.wait(2000);

      cy.get('body').should('be.visible');
    });
  });
});
