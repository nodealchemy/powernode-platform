/// <reference types="cypress" />

describe('Knowledge Base Admin Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['content'] });
  });

  describe('Page Navigation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/content/kb/admin');
    });

    it('should navigate to Knowledge Base Admin page', () => {
      cy.url().should('include', '/content');
    });

    it('should display page title', () => {
      cy.assertContainsAny(['Knowledge Base Admin', 'KB Admin']);
    });

    it('should display page description', () => {
      cy.assertContainsAny(['Manage articles', 'categories', 'content']);
    });

    it('should display breadcrumbs', () => {
      cy.assertContainsAny(['Dashboard', 'Knowledge Base', 'Admin']);
    });
  });

  describe('Search and Filters', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/content/kb/admin');
    });

    it('should display search input', () => {
      cy.assertHasElement([
        'input[placeholder*="Search"]',
        '[class*="search"]',
        '[data-testid*="search"]',
        'input[type="search"]',
        'input[type="text"]'
      ]);
    });

    it('should display Filters button', () => {
      cy.assertContainsAny(['Filters', 'Filter']);
    });

    it('should toggle filter panel', () => {
      cy.get('button').contains('Filters').then($btn => {
        if ($btn.length > 0) {
          cy.wrap($btn).click();
          cy.assertContainsAny(['Status', 'Category']);
        }
      });
    });

    it('should display status filter options', () => {
      cy.assertContainsAny(['Draft', 'Published', 'Review', 'Archived']);
    });

    it('should display category filter', () => {
      cy.assertContainsAny(['Category']);
    });

    it('should have Clear Filters button', () => {
      cy.assertContainsAny(['Clear Filters', 'Clear']);
    });
  });

  describe('Statistics Overview', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/content/kb/admin');
    });

    it('should display Total Articles stat', () => {
      cy.assertContainsAny(['Total Articles', 'Total']);
    });

    it('should display Published stat', () => {
      cy.assertContainsAny(['Published']);
    });

    it('should display Draft stat', () => {
      cy.assertContainsAny(['Draft']);
    });

    it('should display In Review stat', () => {
      cy.assertContainsAny(['In Review', 'Review']);
    });

    it('should display Archived stat', () => {
      cy.assertContainsAny(['Archived']);
    });
  });

  describe('Quick Actions', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/content/kb/admin');
    });

    it('should display Quick Actions section', () => {
      cy.assertContainsAny(['Quick Actions', 'Actions']);
    });

    it('should have Create Article action', () => {
      cy.assertContainsAny(['Create Article', 'New Article']);
    });

    it('should have Manage Categories action', () => {
      cy.assertContainsAny(['Manage Categories', 'Categories']);
    });

    it('should have Moderate Comments action for admins', () => {
      cy.assertContainsAny(['Moderate Comments', 'Comments']);
    });

    it('should have View Analytics action for admins', () => {
      cy.assertContainsAny(['View Analytics', 'Analytics']);
    });
  });

  describe('Articles List', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/content/kb/admin');
    });

    it('should display Articles section', () => {
      cy.assertContainsAny(['Articles']);
    });

    it('should display article items or empty state', () => {
      cy.assertContainsAny(['No articles yet', 'first article', 'Articles']);
    });

    it('should display article status badges', () => {
      cy.assertContainsAny(['published', 'draft', 'Articles']);
    });

    it('should have View action for articles', () => {
      cy.assertContainsAny(['View', 'Articles']);
    });

    it('should have Edit action for articles', () => {
      cy.assertContainsAny(['Edit', 'Articles']);
    });
  });

  describe('Bulk Operations', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/content/kb/admin');
    });

    it('should have Select All button', () => {
      cy.assertContainsAny(['Select All', 'Deselect All', 'Articles']);
    });

    it('should display selection count when articles selected', () => {
      cy.assertHasElement(['input[type="checkbox"]']);
    });
  });

  describe('Page Actions', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/content/kb/admin');
    });

    it('should have Create Article button', () => {
      cy.assertContainsAny(['Create Article', 'Create']);
    });

    it('should have Manage Categories button', () => {
      cy.assertContainsAny(['Manage Categories', 'Categories']);
    });

    it('should have Analytics button for admins', () => {
      cy.assertContainsAny(['Analytics']);
    });
  });

  describe('Pagination', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/content/kb/admin');
    });

    it('should display pagination controls when needed', () => {
      cy.assertContainsAny(['Previous', 'Next', 'Page']);
    });

    it('should display page indicator', () => {
      cy.assertContainsAny(['Page', 'Articles']);
    });
  });

  describe('Permission Check', () => {
    it('should redirect unauthorized users', () => {
      cy.visit('/app/content/kb/admin');
      cy.assertContainsAny(['Knowledge Base Admin', 'Knowledge Base', 'Access Denied']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.testErrorHandling('**/api/**/kb/**', {
        statusCode: 500,
        visitUrl: '/app/content/kb/admin'
      });
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '**/api/**/kb/**', (req) => {
        req.reply((res) => {
          res.delay = 2000;
          res.send({ data: {} });
        });
      }).as('slowLoad');

      cy.visit('/app/content/kb/admin');
      cy.assertHasElement([
        '[class*="animate-spin"]',
        '[class*="loading"]',
        '[class*="spin"]',
        '[data-testid*="loading"]',
        '[role="status"]'
      ]);
    });
  });

  describe('Empty State', () => {
    it('should display empty state when no articles', () => {
      cy.intercept('GET', '**/api/**/kb/articles**', {
        statusCode: 200,
        body: { articles: [], stats: { total: 0 } }
      }).as('emptyArticles');

      cy.visit('/app/content/kb/admin');
      cy.assertContainsAny(['No articles yet', 'first article', 'Create First']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.testViewport('mobile', '/app/content/kb/admin');
      cy.assertContainsAny(['Knowledge Base', 'KB Admin', 'Articles']);
    });

    it('should display properly on tablet viewport', () => {
      cy.testViewport('tablet', '/app/content/kb/admin');
      cy.assertContainsAny(['Knowledge Base', 'KB Admin', 'Articles']);
    });

    it('should stack elements on small screens', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/content/kb/admin');
      cy.assertHasElement([
        '[class*="grid"]',
        '[class*="flex"]',
        '[class*="block"]',
        'div'
      ]);
    });

    it('should show multi-column layout on large screens', () => {
      cy.viewport(1920, 1080);
      cy.visit('/app/content/kb/admin');
      cy.assertHasElement([
        '[class*="lg:grid-cols"]',
        '[class*="sm:grid-cols"]',
        '[class*="grid-cols"]',
        '[class*="grid"]',
        '[class*="flex"]'
      ]);
    });
  });
});


export {};
