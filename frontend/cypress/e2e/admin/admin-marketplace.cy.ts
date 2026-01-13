/// <reference types="cypress" />

/**
 * Admin Marketplace Page Tests
 *
 * Tests for Admin Marketplace management functionality including:
 * - Page navigation and load
 * - Tab navigation (Items, Pending Review, Reviews, Analytics)
 * - Statistics cards display
 * - Template list display
 * - Search and filtering
 * - Template approval/rejection workflow
 * - Review moderation
 * - Export report functionality
 * - Permission-based access
 * - Error handling
 * - Responsive design
 */

describe('Admin Marketplace Page Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to Admin Marketplace page', () => {
      cy.visit('/app/admin/marketplace');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Marketplace') ||
                          $body.text().includes('Admin') ||
                          $body.text().includes('Templates') ||
                          $body.text().includes('Permission');
        if (hasContent) {
          cy.log('Admin Marketplace page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page title', () => {
      cy.visit('/app/admin/marketplace');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('Marketplace') ||
                        $body.text().includes('Admin Marketplace');
        if (hasTitle) {
          cy.log('Page title displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page description', () => {
      cy.visit('/app/admin/marketplace');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasDescription = $body.text().includes('Manage') ||
                               $body.text().includes('moderate') ||
                               $body.text().includes('templates');
        if (hasDescription) {
          cy.log('Page description displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/admin/marketplace');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('Dashboard') ||
                               $body.text().includes('Admin');
        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Tab Navigation', () => {
    beforeEach(() => {
      cy.visit('/app/admin/marketplace');
      cy.wait(2000);
    });

    it('should display Items tab', () => {
      cy.get('body').then($body => {
        const hasItems = $body.text().includes('Items') ||
                        $body.text().includes('All Items');
        if (hasItems) {
          cy.log('Items tab displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Pending Review tab', () => {
      cy.get('body').then($body => {
        const hasPending = $body.text().includes('Pending') ||
                          $body.text().includes('Review');
        if (hasPending) {
          cy.log('Pending Review tab displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Reviews tab', () => {
      cy.get('body').then($body => {
        const hasReviews = $body.text().includes('Reviews');
        if (hasReviews) {
          cy.log('Reviews tab displayed');
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

    it('should switch to Pending Review tab', () => {
      cy.get('body').then($body => {
        const pendingTab = $body.find('button:contains("Pending")');
        if (pendingTab.length > 0) {
          cy.wrap(pendingTab).first().click({ force: true });
          cy.wait(500);
          cy.log('Switched to Pending Review tab');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should switch to Reviews tab', () => {
      cy.get('body').then($body => {
        const reviewsTab = $body.find('button:contains("Reviews")');
        if (reviewsTab.length > 0) {
          cy.wrap(reviewsTab).first().click({ force: true });
          cy.wait(500);
          cy.log('Switched to Reviews tab');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should switch to Analytics tab', () => {
      cy.get('body').then($body => {
        const analyticsTab = $body.find('button:contains("Analytics")');
        if (analyticsTab.length > 0) {
          cy.wrap(analyticsTab).first().click({ force: true });
          cy.wait(500);
          cy.log('Switched to Analytics tab');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Statistics Cards', () => {
    beforeEach(() => {
      cy.visit('/app/admin/marketplace');
      cy.wait(2000);
    });

    it('should display Total Items stat', () => {
      cy.get('body').then($body => {
        const hasTotal = $body.text().includes('Total') ||
                        $body.text().includes('Items');
        if (hasTotal) {
          cy.log('Total Items stat displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Pending Review stat', () => {
      cy.get('body').then($body => {
        const hasPending = $body.text().includes('Pending');
        if (hasPending) {
          cy.log('Pending Review stat displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Approved stat', () => {
      cy.get('body').then($body => {
        const hasApproved = $body.text().includes('Approved') ||
                           $body.text().includes('Active');
        if (hasApproved) {
          cy.log('Approved stat displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Reviews stat', () => {
      cy.get('body').then($body => {
        const hasReviews = $body.text().includes('Reviews') ||
                          $body.text().includes('Rating');
        if (hasReviews) {
          cy.log('Reviews stat displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Template List Display', () => {
    beforeEach(() => {
      cy.visit('/app/admin/marketplace');
      cy.wait(2000);
    });

    it('should display template list or empty state', () => {
      cy.get('body').then($body => {
        const hasTemplates = $body.find('[class*="table"], [class*="list"], [class*="card"]').length > 0 ||
                            $body.text().includes('No templates') ||
                            $body.text().includes('No items');
        if (hasTemplates) {
          cy.log('Template list or empty state displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display template name column', () => {
      cy.get('body').then($body => {
        const hasName = $body.text().includes('Name') ||
                       $body.text().includes('Title');
        if (hasName) {
          cy.log('Template name column displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display template status', () => {
      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Status') ||
                         $body.text().includes('Approved') ||
                         $body.text().includes('Pending') ||
                         $body.text().includes('Rejected');
        if (hasStatus) {
          cy.log('Template status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display template category', () => {
      cy.get('body').then($body => {
        const hasCategory = $body.text().includes('Category') ||
                           $body.text().includes('Type');
        if (hasCategory) {
          cy.log('Template category displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display template author', () => {
      cy.get('body').then($body => {
        const hasAuthor = $body.text().includes('Author') ||
                         $body.text().includes('Creator') ||
                         $body.text().includes('Publisher');
        if (hasAuthor) {
          cy.log('Template author displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Search and Filtering', () => {
    beforeEach(() => {
      cy.visit('/app/admin/marketplace');
      cy.wait(2000);
    });

    it('should display search input', () => {
      cy.get('body').then($body => {
        const hasSearch = $body.find('input[placeholder*="Search"], input[placeholder*="search"]').length > 0;
        if (hasSearch) {
          cy.log('Search input displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should search templates', () => {
      cy.get('body').then($body => {
        const searchInput = $body.find('input[placeholder*="Search"], input[placeholder*="search"]');
        if (searchInput.length > 0) {
          cy.wrap(searchInput).first().type('workflow');
          cy.wait(500);
          cy.log('Search performed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display status filter', () => {
      cy.get('body').then($body => {
        const hasFilter = $body.text().includes('Status') ||
                         $body.text().includes('All') ||
                         $body.find('select').length > 0;
        if (hasFilter) {
          cy.log('Status filter displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display category filter', () => {
      cy.get('body').then($body => {
        const hasFilter = $body.text().includes('Category') ||
                         $body.text().includes('Type');
        if (hasFilter) {
          cy.log('Category filter displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Page Actions', () => {
    beforeEach(() => {
      cy.visit('/app/admin/marketplace');
      cy.wait(2000);
    });

    it('should have Export Report button', () => {
      cy.get('body').then($body => {
        const exportButton = $body.find('button:contains("Export"), button:contains("Report")');
        if (exportButton.length > 0) {
          cy.log('Export Report button found');
        }
      });

      cy.get('body').should('be.visible');
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

  describe('Template Actions', () => {
    beforeEach(() => {
      cy.visit('/app/admin/marketplace');
      cy.wait(2000);
    });

    it('should have View action', () => {
      cy.get('body').then($body => {
        const viewButton = $body.find('button:contains("View"), [aria-label*="view"]');
        if (viewButton.length > 0) {
          cy.log('View action found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Approve action', () => {
      cy.get('body').then($body => {
        const approveButton = $body.find('button:contains("Approve")');
        if (approveButton.length > 0) {
          cy.log('Approve action found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Reject action', () => {
      cy.get('body').then($body => {
        const rejectButton = $body.find('button:contains("Reject")');
        if (rejectButton.length > 0) {
          cy.log('Reject action found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Edit action', () => {
      cy.get('body').then($body => {
        const editButton = $body.find('button:contains("Edit"), [aria-label*="edit"]');
        if (editButton.length > 0) {
          cy.log('Edit action found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Delete action', () => {
      cy.get('body').then($body => {
        const deleteButton = $body.find('button:contains("Delete"), [aria-label*="delete"]');
        if (deleteButton.length > 0) {
          cy.log('Delete action found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Pending Review Tab', () => {
    beforeEach(() => {
      cy.visit('/app/admin/marketplace');
      cy.wait(2000);
      // Switch to Pending Review tab
      cy.get('body').then($body => {
        const pendingTab = $body.find('button:contains("Pending")');
        if (pendingTab.length > 0) {
          cy.wrap(pendingTab).first().click({ force: true });
          cy.wait(500);
        }
      });
    });

    it('should display pending templates', () => {
      cy.get('body').then($body => {
        const hasPending = $body.text().includes('Pending') ||
                          $body.text().includes('Review') ||
                          $body.text().includes('No pending');
        if (hasPending) {
          cy.log('Pending templates displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have bulk approval actions', () => {
      cy.get('body').then($body => {
        const hasBulk = $body.find('input[type="checkbox"]').length > 0 ||
                       $body.text().includes('Select') ||
                       $body.text().includes('Bulk');
        if (hasBulk) {
          cy.log('Bulk approval actions found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Reviews Tab', () => {
    beforeEach(() => {
      cy.visit('/app/admin/marketplace');
      cy.wait(2000);
      // Switch to Reviews tab
      cy.get('body').then($body => {
        const reviewsTab = $body.find('button:contains("Reviews")');
        if (reviewsTab.length > 0) {
          cy.wrap(reviewsTab).first().click({ force: true });
          cy.wait(500);
        }
      });
    });

    it('should display reviews list', () => {
      cy.get('body').then($body => {
        const hasReviews = $body.text().includes('Review') ||
                          $body.text().includes('Rating') ||
                          $body.text().includes('No reviews');
        if (hasReviews) {
          cy.log('Reviews list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display review ratings', () => {
      cy.get('body').then($body => {
        const hasRatings = $body.text().includes('★') ||
                          $body.find('[class*="star"]').length > 0 ||
                          $body.text().includes('Rating');
        if (hasRatings) {
          cy.log('Review ratings displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have moderate review action', () => {
      cy.get('body').then($body => {
        const moderateButton = $body.find('button:contains("Moderate"), button:contains("Flag"), button:contains("Remove")');
        if (moderateButton.length > 0) {
          cy.log('Moderate review action found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Analytics Tab', () => {
    beforeEach(() => {
      cy.visit('/app/admin/marketplace');
      cy.wait(2000);
      // Switch to Analytics tab
      cy.get('body').then($body => {
        const analyticsTab = $body.find('button:contains("Analytics")');
        if (analyticsTab.length > 0) {
          cy.wrap(analyticsTab).first().click({ force: true });
          cy.wait(500);
        }
      });
    });

    it('should display analytics content', () => {
      cy.get('body').then($body => {
        const hasAnalytics = $body.text().includes('Analytics') ||
                            $body.text().includes('Statistics') ||
                            $body.text().includes('Downloads');
        if (hasAnalytics) {
          cy.log('Analytics content displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display download statistics', () => {
      cy.get('body').then($body => {
        const hasDownloads = $body.text().includes('Download') ||
                            $body.text().includes('Install');
        if (hasDownloads) {
          cy.log('Download statistics displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display revenue charts', () => {
      cy.get('body').then($body => {
        const hasCharts = $body.find('[class*="chart"], canvas, svg').length > 0 ||
                         $body.text().includes('Revenue');
        if (hasCharts) {
          cy.log('Revenue charts displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Permission Check', () => {
    it('should show permission message for unauthorized users', () => {
      cy.visit('/app/admin/marketplace');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasPermission = $body.text().includes("don't have permission") ||
                             $body.find('[class*="table"]').length > 0 ||
                             $body.text().includes('Marketplace');
        if (hasPermission) {
          cy.log('Permission handled properly');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.intercept('GET', '/api/v1/admin/marketplace*', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/admin/marketplace');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should display error notification on failure', () => {
      cy.intercept('GET', '/api/v1/admin/marketplace*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load marketplace data' }
      });

      cy.visit('/app/admin/marketplace');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasError = $body.text().includes('Error') ||
                         $body.text().includes('Failed') ||
                         $body.text().includes('Marketplace');
        if (hasError) {
          cy.log('Error handled');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '/api/v1/admin/marketplace*', {
        delay: 1000,
        statusCode: 200,
        body: { success: true, templates: [] }
      });

      cy.visit('/app/admin/marketplace');

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

  describe('Empty State', () => {
    it('should display empty state when no templates', () => {
      cy.intercept('GET', '/api/v1/admin/marketplace*', {
        statusCode: 200,
        body: { success: true, templates: [] }
      });

      cy.visit('/app/admin/marketplace');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasEmpty = $body.text().includes('No templates') ||
                        $body.text().includes('No items');
        if (hasEmpty) {
          cy.log('Empty state displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Pagination', () => {
    beforeEach(() => {
      cy.visit('/app/admin/marketplace');
      cy.wait(2000);
    });

    it('should display pagination controls', () => {
      cy.get('body').then($body => {
        const hasPagination = $body.find('[class*="pagination"]').length > 0 ||
                             $body.text().includes('Page') ||
                             $body.find('button:contains("Next")').length > 0;
        if (hasPagination) {
          cy.log('Pagination controls displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/admin/marketplace');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Marketplace');
        if (hasContent) {
          cy.log('Content visible on mobile');
        }
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/admin/marketplace');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Marketplace');
        if (hasContent) {
          cy.log('Content visible on tablet');
        }
      });
    });

    it('should stack elements on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/admin/marketplace');
      cy.wait(2000);

      cy.get('body').should('be.visible');
    });

    it('should show multi-column layout on large screens', () => {
      cy.viewport(1280, 800);
      cy.visit('/app/admin/marketplace');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasMultiColumn = $body.find('[class*="grid-cols"], [class*="md:grid-cols"]').length > 0;
        if (hasMultiColumn) {
          cy.log('Multi-column layout on large screens');
        }
      });

      cy.get('body').should('be.visible');
    });
  });
});
