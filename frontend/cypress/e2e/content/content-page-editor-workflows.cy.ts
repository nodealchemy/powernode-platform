/// <reference types="cypress" />

/**
 * Content Page Editor Workflows Tests
 *
 * Comprehensive E2E tests for Content Page Editor:
 * - Page CRUD operations
 * - Rich text editing (MDEditor)
 * - SEO settings
 * - Publishing workflow
 */

describe('Content Page Editor Workflows Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['content'] });
    setupPageEditorIntercepts();
  });

  describe('Pages List', () => {
    beforeEach(() => {
      cy.navigateTo('/app/content/pages');
    });

    it('should display pages list with title', () => {
      cy.contains('Pages').should('exist');
    });

    it('should display pages table', () => {
      cy.get('table').should('exist');
    });

    it('should display table headers', () => {
      cy.contains('th', 'Title').should('exist');
      cy.contains('th', 'Status').should('exist');
      cy.contains('th', 'Published').should('exist');
      cy.contains('th', 'Word Count').should('exist');
      cy.contains('th', 'Actions').should('exist');
    });

    it('should display page items', () => {
      cy.contains('Home Page').should('exist');
      cy.contains('About Us').should('exist');
    });

    it('should display page status badges', () => {
      cy.assertContainsAny(['Published', 'Draft']);
    });

    it('should display word count for pages', () => {
      cy.contains('words').should('exist');
    });

    it('should have create page button', () => {
      cy.get('button').contains('Create Page').should('exist');
    });

    it('should have refresh button', () => {
      cy.get('button').contains('Refresh').should('exist');
    });
  });

  describe('Search and Filters', () => {
    beforeEach(() => {
      cy.navigateTo('/app/content/pages');
    });

    it('should display search input', () => {
      cy.get('input[placeholder*="Search pages"]').should('exist');
    });

    it('should filter by search query', () => {
      cy.get('input[placeholder*="Search pages"]').type('home');
      cy.waitForPageLoad();
    });

    it('should have status filter', () => {
      cy.get('select').contains('All Status').should('exist');
    });

    it('should filter by draft status', () => {
      cy.get('select').select('Draft');
      cy.waitForPageLoad();
    });

    it('should filter by published status', () => {
      cy.get('select').select('Published');
      cy.waitForPageLoad();
    });
  });

  describe('Create Page', () => {
    beforeEach(() => {
      cy.navigateTo('/app/content/pages');
      cy.get('button').contains('Create Page').click();
      cy.waitForPageLoad();
    });

    it('should open create page editor', () => {
      cy.contains('Create New Page').should('exist');
    });

    it('should have page title input', () => {
      cy.get('input[placeholder*="Enter page title"]').should('exist');
    });

    it('should have status selector', () => {
      cy.get('select').contains('Draft').should('exist');
    });

    it('should have content editor', () => {
      // MDEditor renders a div with w-md-editor class
      cy.get('[class*="w-md-editor"], [data-color-mode]').should('exist');
    });

    it('should have editor tabs', () => {
      cy.contains('button', 'editor').should('exist');
      cy.contains('button', 'preview').should('exist');
      cy.contains('button', 'SEO').should('exist');
    });

    it('should have cancel button', () => {
      cy.get('button').contains('Cancel').should('exist');
    });

    it('should have save draft button', () => {
      cy.get('button').contains('Save Draft').should('exist');
    });

    it('should have save and publish button', () => {
      cy.get('button').contains('Save & Publish').should('exist');
    });

    it('should show URL preview when title entered', () => {
      cy.get('input[placeholder*="Enter page title"]').type('My Test Page');
      cy.contains('my-test-page').should('exist');
    });

    it('should create page when save clicked', () => {
      cy.get('input[placeholder*="Enter page title"]').type('New Test Page');
      // Type content in MDEditor textarea
      cy.get('.w-md-editor-text-input, textarea').first().type('Test content for the page', { force: true });
      cy.get('button').contains('Save Draft').click();
      cy.wait('@createPage');
    });
  });

  describe('Edit Page', () => {
    beforeEach(() => {
      cy.navigateTo('/app/content/pages');
    });

    it('should have edit buttons for each page', () => {
      // Edit buttons are icon-only with title attribute
      cy.get('button[title="Edit page"]').should('have.length.gte', 1);
    });

    it('should open page editor when edit clicked', () => {
      cy.get('button[title="Edit page"]').first().click();
      cy.wait('@getPage');
      cy.contains('Edit').should('exist');
    });

    it('should pre-fill page data', () => {
      cy.get('button[title="Edit page"]').first().click();
      cy.wait('@getPage');
      cy.get('input[placeholder*="Enter page title"]').should('not.have.value', '');
    });

    it('should update page when saved', () => {
      cy.get('button[title="Edit page"]').first().click();
      cy.wait('@getPage');
      cy.get('input[placeholder*="Enter page title"]').clear().type('Updated Page Title');
      cy.get('button').contains('Save Draft').click();
      cy.wait('@updatePage');
    });

    it('should close editor when cancelled', () => {
      cy.get('button[title="Edit page"]').first().click();
      cy.wait('@getPage');
      cy.get('button').contains('Cancel').click();
      cy.contains('Pages List').should('exist');
    });
  });

  describe('SEO Settings', () => {
    beforeEach(() => {
      cy.navigateTo('/app/content/pages');
      cy.get('button').contains('Create Page').click();
      cy.waitForPageLoad();
    });

    it('should navigate to SEO tab', () => {
      cy.contains('button', 'SEO').click();
      cy.contains('SEO Settings').should('exist');
    });

    it('should have meta description input', () => {
      cy.contains('button', 'SEO').click();
      cy.contains('Meta Description').should('exist');
      cy.get('textarea[placeholder*="description"]').should('exist');
    });

    it('should have meta keywords input', () => {
      cy.contains('button', 'SEO').click();
      cy.contains('Meta Keywords').should('exist');
    });

    it('should show character count for meta description', () => {
      cy.contains('button', 'SEO').click();
      cy.contains('/160 characters').should('exist');
    });

    it('should display search engine preview', () => {
      cy.contains('button', 'SEO').click();
      cy.contains('Search Engine Preview').should('exist');
    });
  });

  describe('Preview Functionality', () => {
    beforeEach(() => {
      cy.navigateTo('/app/content/pages');
      cy.get('button').contains('Create Page').click();
      cy.waitForPageLoad();
    });

    it('should have preview tab', () => {
      cy.contains('button', 'preview').should('exist');
    });

    it('should show preview content', () => {
      // Enter some content first
      cy.get('.w-md-editor-text-input, textarea').first().type('# Test Heading', { force: true });
      cy.contains('button', 'preview').click();
      cy.assertContainsAny(['Preview', 'how your page will look']);
    });

    it('should show empty state when no content', () => {
      cy.contains('button', 'preview').click();
      cy.contains('No content to preview').should('exist');
    });
  });

  describe('Publishing Workflow', () => {
    beforeEach(() => {
      cy.navigateTo('/app/content/pages');
    });

    it('should have view page button', () => {
      cy.get('button[title="View public page"]').should('exist');
    });

    it('should have publish/unpublish toggle button', () => {
      // Publish button for draft or unpublish button for published
      cy.get('button[title*="ublish"]').should('exist');
    });

    it('should publish page when publish clicked', () => {
      cy.get('button[title="Publish page"]').first().click();
      cy.wait('@publishPage');
    });

    it('should unpublish page when unpublish clicked', () => {
      cy.get('button[title="Unpublish page"]').first().click();
      cy.wait('@unpublishPage');
    });
  });

  describe('Duplicate Page', () => {
    beforeEach(() => {
      cy.navigateTo('/app/content/pages');
    });

    it('should have duplicate button', () => {
      cy.get('button[title="Duplicate page"]').should('exist');
    });

    it('should duplicate page when clicked', () => {
      cy.get('button[title="Duplicate page"]').first().click();
      cy.wait('@duplicatePage');
    });
  });

  describe('Delete Page', () => {
    beforeEach(() => {
      cy.navigateTo('/app/content/pages');
    });

    it('should have delete button', () => {
      cy.get('button[title="Delete page"]').should('exist');
    });

    it('should show confirmation dialog before delete', () => {
      cy.get('button[title="Delete page"]').first().click();
      cy.contains('Delete Page').should('exist');
      cy.contains('Are you sure').should('exist');
    });

    it('should have cancel option in confirmation', () => {
      cy.get('button[title="Delete page"]').first().click();
      cy.get('button').contains(/cancel/i).should('exist');
    });

    it('should delete page when confirmed', () => {
      cy.get('button[title="Delete page"]').first().click();
      cy.get('button').contains('Delete').last().click();
      cy.wait('@deletePage');
    });
  });

  describe('Empty State', () => {
    it('should display empty state when no pages', () => {
      // Override intercept with empty pages
      cy.intercept('GET', '/api/v1/admin/pages*', {
        statusCode: 200,
        body: {
          data: [],
          meta: { current_page: 1, per_page: 10, total_count: 0, total_pages: 1 }
        }
      }).as('emptyPages');

      cy.navigateTo('/app/content/pages');
      cy.wait('@emptyPages');
      cy.contains('No pages yet').should('exist');
      cy.contains('Create your first page').should('exist');
    });
  });

  describe('Pagination', () => {
    it('should display pagination when multiple pages', () => {
      // Override with pagination
      cy.intercept('GET', '/api/v1/admin/pages*', {
        statusCode: 200,
        body: {
          data: mockPages,
          meta: { current_page: 1, per_page: 10, total_count: 25, total_pages: 3 }
        }
      }).as('paginatedPages');

      cy.navigateTo('/app/content/pages');
      cy.wait('@paginatedPages');
      cy.contains('Page 1 of 3').should('exist');
      cy.get('button').contains('Previous').should('be.disabled');
      cy.get('button').contains('Next').should('not.be.disabled');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('/api/v1/admin/pages*', {
        statusCode: 500,
        visitUrl: '/app/content/pages',
      });
    });

    it('should disable save when title missing', () => {
      cy.navigateTo('/app/content/pages');
      cy.get('button').contains('Create Page').click();
      cy.waitForPageLoad();
      // Enter content but no title
      cy.get('.w-md-editor-text-input, textarea').first().type('Some content', { force: true });
      // Save Draft button should be disabled when title is empty
      cy.get('button').contains('Save Draft').should('be.disabled');
      cy.get('button').contains('Save & Publish').should('be.disabled');
    });
  });

  describe('Responsive Design', () => {
    it('should display correctly across viewports', () => {
      cy.testResponsiveDesign('/app/content/pages', {
        checkContent: 'Pages',
      });
    });
  });
});

const mockPages = [
  {
    id: 'page-1',
    title: 'Home Page',
    slug: 'home',
    content: '# Welcome\n\nThis is the home page.',
    status: 'published',
    meta_description: 'Welcome to our homepage',
    meta_keywords: 'home, welcome',
    word_count: 150,
    published_at: '2025-01-15T10:00:00Z',
    created_at: '2025-01-01T10:00:00Z',
    updated_at: '2025-01-15T10:00:00Z',
  },
  {
    id: 'page-2',
    title: 'About Us',
    slug: 'about',
    content: '# About Us\n\nLearn about our company.',
    status: 'published',
    meta_description: 'Learn about our company',
    meta_keywords: 'about, company',
    word_count: 250,
    published_at: '2025-01-14T10:00:00Z',
    created_at: '2025-01-05T10:00:00Z',
    updated_at: '2025-01-14T10:00:00Z',
  },
  {
    id: 'page-3',
    title: 'Contact',
    slug: 'contact',
    content: '# Contact Us\n\nGet in touch.',
    status: 'draft',
    meta_description: 'Contact our team',
    meta_keywords: 'contact, support',
    word_count: 100,
    created_at: '2025-01-10T10:00:00Z',
    updated_at: '2025-01-13T10:00:00Z',
  },
];

function setupPageEditorIntercepts() {
  // List pages
  cy.intercept('GET', '/api/v1/admin/pages*', {
    statusCode: 200,
    body: {
      data: mockPages,
      meta: { current_page: 1, per_page: 10, total_count: 3, total_pages: 1 }
    }
  }).as('getPages');

  // Get single page
  cy.intercept('GET', /\/api\/v1\/admin\/pages\/[a-z0-9-]+$/, {
    statusCode: 200,
    body: {
      data: mockPages[0]
    }
  }).as('getPage');

  // Create page
  cy.intercept('POST', '/api/v1/admin/pages', {
    statusCode: 201,
    body: {
      data: { id: 'page-new', title: 'New Page', slug: 'new-page', status: 'draft' }
    }
  }).as('createPage');

  // Update page
  cy.intercept('PUT', /\/api\/v1\/admin\/pages\/[a-z0-9-]+$/, {
    statusCode: 200,
    body: {
      data: mockPages[0]
    }
  }).as('updatePage');

  // Delete page
  cy.intercept('DELETE', /\/api\/v1\/admin\/pages\/[a-z0-9-]+$/, {
    statusCode: 200,
    body: { message: 'Page deleted' }
  }).as('deletePage');

  // Publish page
  cy.intercept('POST', /\/api\/v1\/admin\/pages\/[a-z0-9-]+\/publish$/, {
    statusCode: 200,
    body: {
      data: { ...mockPages[0], status: 'published', published_at: new Date().toISOString() }
    }
  }).as('publishPage');

  // Unpublish page
  cy.intercept('POST', /\/api\/v1\/admin\/pages\/[a-z0-9-]+\/unpublish$/, {
    statusCode: 200,
    body: {
      data: { ...mockPages[0], status: 'draft', published_at: null }
    }
  }).as('unpublishPage');

  // Duplicate page
  cy.intercept('POST', /\/api\/v1\/admin\/pages\/[a-z0-9-]+\/duplicate$/, {
    statusCode: 200,
    body: {
      data: { id: 'page-copy', title: 'Home Page (Copy)', slug: 'home-copy', status: 'draft' }
    }
  }).as('duplicatePage');
}

export {};
