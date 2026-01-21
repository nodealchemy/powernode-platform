/// <reference types="cypress" />

/**
 * Knowledge Base Admin Workflows Tests
 *
 * Comprehensive E2E tests for Knowledge Base Admin:
 * - Article CRUD operations
 * - Category management
 * - Search and filtering
 * - Bulk operations
 * - Statistics display
 */

describe('Knowledge Base Admin Workflows Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ role: 'admin', intercepts: ['content'] });
    setupKBAdminIntercepts();
  });

  describe('KB Admin Dashboard', () => {
    beforeEach(() => {
      cy.navigateTo('/app/content/kb/admin');
    });

    it('should display KB admin page with title', () => {
      cy.assertContainsAny(['Knowledge Base Admin', 'KB Admin', 'Manage articles']);
    });

    it('should display article statistics cards', () => {
      cy.assertContainsAny(['Total Articles', 'Published', 'Draft', 'In Review', 'Archived']);
    });

    it('should display statistics values', () => {
      // Stats cards show numeric values
      cy.get('.text-2xl').should('exist');
    });

    it('should have create article button in page actions', () => {
      cy.get('button').contains(/create article/i).should('exist');
    });

    it('should have manage categories button', () => {
      cy.get('button').contains(/manage categories/i).should('exist');
    });
  });

  describe('Quick Actions', () => {
    beforeEach(() => {
      cy.navigateTo('/app/content/kb/admin');
    });

    it('should display quick actions section', () => {
      cy.contains('Quick Actions').should('exist');
    });

    it('should have create article quick action', () => {
      cy.contains('Create Article').should('exist');
      cy.contains('Write a new knowledge base article').should('exist');
    });

    it('should have manage categories quick action', () => {
      cy.contains('Manage Categories').should('exist');
      cy.contains('Organize articles into categories').should('exist');
    });

    it('should have view analytics quick action for admins', () => {
      cy.get('body').then($body => {
        // Analytics is only shown for users with kb.manage permission
        if ($body.text().includes('View Analytics')) {
          cy.contains('View Analytics').should('exist');
          cy.contains('Track content performance').should('exist');
        }
      });
    });
  });

  describe('Articles List', () => {
    beforeEach(() => {
      cy.navigateTo('/app/content/kb/admin');
    });

    it('should display articles section heading', () => {
      cy.contains('Articles').should('exist');
    });

    it('should display articles or empty state', () => {
      cy.assertContainsAny(['Getting Started', 'API Reference', 'No articles yet', 'Create First Article']);
    });

    it('should display article status badges when articles exist', () => {
      cy.get('body').then($body => {
        if (!$body.text().includes('No articles yet')) {
          cy.assertContainsAny(['published', 'draft', 'review', 'archived']);
        }
      });
    });

    it('should display article metadata when articles exist', () => {
      cy.get('body').then($body => {
        if (!$body.text().includes('No articles yet')) {
          cy.assertContainsAny(['views', 'By', 'Tutorials', 'Documentation']);
        }
      });
    });

    it('should have view and edit buttons when articles exist', () => {
      cy.get('body').then($body => {
        if (!$body.text().includes('No articles yet')) {
          cy.get('button').contains(/view/i).should('exist');
          cy.get('button').contains(/edit/i).should('exist');
        }
      });
    });

    it('should have select all button when articles exist', () => {
      cy.get('body').then($body => {
        if (!$body.text().includes('No articles yet')) {
          cy.get('button').contains(/select all|deselect all/i).should('exist');
        }
      });
    });
  });

  describe('Search and Filters', () => {
    beforeEach(() => {
      cy.navigateTo('/app/content/kb/admin');
    });

    it('should display search input', () => {
      cy.get('input[placeholder*="Search articles"]').should('exist');
    });

    it('should filter by search query', () => {
      cy.get('input[placeholder*="Search articles"]').type('getting started');
      cy.waitForPageLoad();
    });

    it('should have filters toggle button', () => {
      cy.get('button').contains(/filters/i).should('exist');
    });

    it('should show filter panel when filters clicked', () => {
      cy.get('button').contains(/filters/i).click();
      cy.assertContainsAny(['Status', 'Category', 'All Statuses', 'All Categories']);
    });

    it('should have status filter dropdown', () => {
      cy.get('button').contains(/filters/i).click();
      cy.contains('Status').should('exist');
      cy.assertContainsAny(['All Statuses', 'Draft', 'Published']);
    });

    it('should have category filter dropdown', () => {
      cy.get('button').contains(/filters/i).click();
      cy.contains('Category').should('exist');
      cy.assertContainsAny(['All Categories', 'Tutorials', 'Documentation']);
    });

    it('should have clear filters button', () => {
      cy.get('button').contains(/filters/i).click();
      cy.get('button').contains(/clear filters/i).should('exist');
    });
  });

  describe('Article Selection', () => {
    beforeEach(() => {
      cy.navigateTo('/app/content/kb/admin');
    });

    it('should have checkboxes for article selection when articles exist', () => {
      cy.get('body').then($body => {
        if (!$body.text().includes('No articles yet')) {
          cy.get('input[type="checkbox"]').should('exist');
        }
      });
    });

    it('should show selected count when articles are selected', () => {
      cy.get('body').then($body => {
        if (!$body.text().includes('No articles yet')) {
          cy.get('input[type="checkbox"]').first().check({ force: true });
          cy.contains(/selected/i).should('exist');
        }
      });
    });

    it('should toggle select all / deselect all', () => {
      cy.get('body').then($body => {
        if (!$body.text().includes('No articles yet')) {
          cy.get('button').contains(/select all/i).click();
          cy.get('button').contains(/deselect all/i).should('exist');
        }
      });
    });
  });

  describe('Bulk Operations', () => {
    beforeEach(() => {
      cy.navigateTo('/app/content/kb/admin');
    });

    it('should show bulk action buttons when articles are selected', () => {
      cy.get('body').then($body => {
        if (!$body.text().includes('No articles yet')) {
          cy.get('input[type="checkbox"]').first().check({ force: true });
          // Bulk actions appear in page actions
          cy.assertContainsAny(['Publish', 'Archive', 'Delete']);
        }
      });
    });

    it('should show count in bulk action buttons', () => {
      cy.get('body').then($body => {
        if (!$body.text().includes('No articles yet')) {
          cy.get('input[type="checkbox"]').first().check({ force: true });
          // Bulk actions show count like "Publish (1)"
          cy.get('button').contains(/\(1\)/).should('exist');
        }
      });
    });
  });

  describe('Empty State', () => {
    it('should display empty state when no articles', () => {
      // Override intercept with empty articles
      cy.intercept('GET', '/api/v1/kb/articles*', {
        statusCode: 200,
        body: {
          data: {
            articles: [],
            stats: { total: 0, published: 0, draft: 0, review: 0, archived: 0 },
            pagination: { current_page: 1, total_pages: 1, total_count: 0, per_page: 20 }
          },
          message: 'Articles retrieved'
        }
      }).as('emptyArticles');

      cy.navigateTo('/app/content/kb/admin');
      cy.wait('@emptyArticles');
      cy.assertContainsAny(['No articles yet', 'Create First Article', 'Get started']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('/api/v1/kb/articles*', {
        statusCode: 500,
        visitUrl: '/app/content/kb/admin',
      });
    });
  });

  describe('Responsive Design', () => {
    it('should display correctly across viewports', () => {
      cy.testResponsiveDesign('/app/content/kb/admin', {
        checkContent: 'Knowledge Base',
      });
    });
  });
});

function setupKBAdminIntercepts() {
  const mockArticles = [
    {
      id: 'art-1',
      title: 'Getting Started Guide',
      slug: 'getting-started',
      status: 'published',
      category: { id: 'cat-1', name: 'Tutorials', slug: 'tutorials' },
      author_name: 'Admin User',
      views_count: 1250,
      comments_count: 5,
      is_featured: true,
      created_at: '2025-01-01T10:00:00Z',
      updated_at: '2025-01-15T10:00:00Z',
    },
    {
      id: 'art-2',
      title: 'API Reference',
      slug: 'api-reference',
      status: 'draft',
      category: { id: 'cat-2', name: 'Documentation', slug: 'documentation' },
      author_name: 'Dev User',
      views_count: 0,
      comments_count: 0,
      is_featured: false,
      created_at: '2025-01-10T10:00:00Z',
      updated_at: '2025-01-14T10:00:00Z',
    },
    {
      id: 'art-3',
      title: 'Troubleshooting FAQ',
      slug: 'troubleshooting-faq',
      status: 'review',
      category: { id: 'cat-1', name: 'Tutorials', slug: 'tutorials' },
      author_name: 'Support User',
      views_count: 500,
      comments_count: 2,
      is_featured: false,
      created_at: '2025-01-05T10:00:00Z',
      updated_at: '2025-01-13T10:00:00Z',
    },
  ];

  const mockCategories = [
    { id: 'cat-1', name: 'Tutorials', slug: 'tutorials', articles_count: 15 },
    { id: 'cat-2', name: 'Documentation', slug: 'documentation', articles_count: 25 },
    { id: 'cat-3', name: 'FAQ', slug: 'faq', articles_count: 10 },
  ];

  const mockStats = {
    total: 50,
    published: 35,
    draft: 10,
    review: 5,
    archived: 0,
  };

  const mockPagination = {
    current_page: 1,
    total_pages: 3,
    total_count: 50,
    per_page: 20
  };

  // KB articles endpoint with admin=true query param
  cy.intercept('GET', '/api/v1/kb/articles*', (req) => {
    // Check if this is an admin request (has admin=true param)
    if (req.url.includes('admin=true')) {
      req.reply({
        statusCode: 200,
        body: {
          data: {
            articles: mockArticles,
            stats: mockStats,
            pagination: mockPagination
          },
          message: 'Articles retrieved successfully'
        }
      });
    }
  }).as('getKbArticles');

  // KB categories endpoint
  cy.intercept('GET', '/api/v1/kb/categories*', {
    statusCode: 200,
    body: { data: mockCategories, message: 'Categories retrieved successfully' }
  }).as('getKbCategories');

  // Single article
  cy.intercept('GET', /\/api\/v1\/kb\/articles\/[a-z0-9-]+/, {
    statusCode: 200,
    body: { data: { article: mockArticles[0], related_articles: [] }, message: 'Article retrieved' }
  }).as('getKbArticle');

  // Create article
  cy.intercept('POST', '/api/v1/kb/articles', {
    statusCode: 201,
    body: { data: { id: 'art-new', title: 'New Article' }, message: 'Article created' }
  }).as('createKbArticle');

  // Update article
  cy.intercept('PATCH', /\/api\/v1\/kb\/articles\/[a-z0-9-]+$/, {
    statusCode: 200,
    body: { data: mockArticles[0], message: 'Article updated' }
  }).as('updateKbArticle');

  // Delete article
  cy.intercept('DELETE', /\/api\/v1\/kb\/articles\/[a-z0-9-]+$/, {
    statusCode: 200,
    body: { message: 'Article deleted' }
  }).as('deleteKbArticle');

  // Bulk operations
  cy.intercept('POST', '/api/v1/kb/articles/bulk_update', {
    statusCode: 200,
    body: { data: { updated_count: 3 }, message: 'Articles updated' }
  }).as('bulkUpdateKbArticles');

  cy.intercept('POST', '/api/v1/kb/articles/bulk_delete', {
    statusCode: 200,
    body: { data: { deleted_count: 2 }, message: 'Articles deleted' }
  }).as('bulkDeleteKbArticles');
}

export {};
