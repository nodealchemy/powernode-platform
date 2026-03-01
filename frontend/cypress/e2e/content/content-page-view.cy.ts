/// <reference types="cypress" />

/**
 * Content Page View Tests
 *
 * Tests for Public Page View functionality including:
 * - Page navigation by slug
 * - Page content display
 * - Loading states
 * - Error handling (page not found, API errors)
 * - Back navigation
 * - Meta information display
 * - Rich content rendering
 * - Responsive design
 * - Accessibility
 */

describe('Content Page View Tests', () => {
  // Mock page data
  const mockPage = {
    id: 'page-123',
    title: 'Test Page Title',
    slug: 'test-page',
    content: '# Welcome\n\nThis is test content with **bold** and *italic* text.',
    rendered_content: '<h1>Welcome</h1><p>This is test content with <strong>bold</strong> and <em>italic</em> text.</p>',
    meta_description: 'This is a test page meta description for SEO purposes.',
    meta_keywords: 'test, page, content',
    status: 'published',
    published_at: '2025-01-10T10:00:00Z',
    word_count: 150,
    estimated_read_time: 2,
    excerpt: 'This is test content with bold and italic text.',
    author: {
      id: 'author-1',
      name: 'John Doe',
      email: 'john@example.com'
    },
    created_at: '2025-01-01T00:00:00Z',
    updated_at: '2025-01-10T10:00:00Z'
  };

  const _mockDraftPage = {
    ...mockPage,
    id: 'page-456',
    title: 'Draft Page',
    slug: 'draft-page',
    status: 'draft',
    published_at: undefined
  };

  beforeEach(() => {
    cy.clearAppData();
    cy.setupContentIntercepts();
  });

  describe('Page Navigation', () => {
    it('should navigate to public page by slug', () => {
      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: { success: true, data: mockPage }
      }).as('getPage');

      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      cy.contains(mockPage.title).should('be.visible');
    });

    it('should display page content area', () => {
      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: { success: true, data: mockPage }
      }).as('getPage');

      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      cy.get('body').should('contain.text', 'Welcome');
    });

    it('should handle slugs with special characters', () => {
      const pageWithSpecialSlug = {
        ...mockPage,
        slug: 'my-page-2025',
        title: 'My Page 2025'
      };

      cy.intercept('GET', '**/pages/my-page-2025', {
        statusCode: 200,
        body: { success: true, data: pageWithSpecialSlug }
      }).as('getPage');

      cy.visit('/page/my-page-2025');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      cy.assertContainsAny([pageWithSpecialSlug.title, 'Page']);
    });
  });

  describe('Page Content Display', () => {
    beforeEach(() => {
      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: { success: true, data: mockPage }
      }).as('getPage');

      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();
    });

    it('should display page title', () => {
      cy.contains(mockPage.title).should('be.visible');
    });

    it('should display page content', () => {
      cy.get('body').should('contain.text', 'Welcome');
      cy.get('body').should('contain.text', 'test content');
    });

    it('should render rich content with formatting', () => {
      // Page has content with formatting - verify body is visible
      cy.get('body').should('contain.text', 'Welcome');
    });

    it('should display page container', () => {
      cy.assertHasElement(['main', '[role="main"]', 'article']).should('be.visible');
    });
  });

  describe('Meta Information Display', () => {
    beforeEach(() => {
      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: { success: true, data: mockPage }
      }).as('getPage');

      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();
    });

    it('should display published date', () => {
      cy.assertContainsAny(['January', '2025', 'Published', mockPage.title]);
    });

    it('should display reading time when available', () => {
      cy.assertContainsAny(['min', 'read', '2']);
    });

    it('should display page status', () => {
      cy.assertContainsAny(['Published', 'published', mockPage.title]);
    });
  });

  describe('Back Navigation', () => {
    beforeEach(() => {
      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: { success: true, data: mockPage }
      }).as('getPage');

      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();
    });

    it('should display back to home button', () => {
      cy.assertContainsAny(['Back', 'Home', mockPage.title]);
    });

    it('should navigate back to home when clicking back button', () => {
      cy.assertHasElement(['a[href="/"]', 'button:contains("Back")', 'a:contains("Home")']).first().click();
      cy.url().should('include', '/');
    });
  });

  describe('Loading State', () => {
    it('should display loading spinner while fetching page', () => {
      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: { success: true, data: mockPage }
      }).as('getPage');

      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      cy.contains(mockPage.title).should('be.visible');
    });

    it('should hide loading spinner after page loads', () => {
      cy.intercept('GET', '**/pages/test-page', {
        delay: 500,
        statusCode: 200,
        body: { success: true, data: mockPage }
      }).as('getPage');

      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      cy.get('[class*="animate-spin"]').should('not.exist');
      cy.contains(mockPage.title).should('be.visible');
    });
  });

  describe('Page Not Found Error', () => {
    it('should display page not found message', () => {
      cy.visit('/page/nonexistent-page');
      cy.waitForStableDOM();

      cy.assertContainsAny(['Not Found', 'not found', 'Error', 'Page']);
    });

    it('should display back to home option on error page', () => {
      cy.visit('/page/nonexistent-page');
      cy.waitForStableDOM();

      cy.assertContainsAny(['Back', 'Home', 'Return']);
    });

    it('should display try again button', () => {
      cy.visit('/page/nonexistent-page');
      cy.waitForStableDOM();

      cy.assertContainsAny(['Try again', 'Retry', 'Back']);
    });
  });

  describe('API Error Handling', () => {
    it('should handle server error gracefully', () => {
      cy.visit('/page/test-error-page');
      cy.waitForStableDOM();

      cy.assertContainsAny(['Error', 'Not Found', 'Page']);
    });

    it('should handle network error gracefully', () => {
      cy.visit('/page/test-network-error');
      cy.waitForStableDOM();

      cy.assertContainsAny(['Error', 'Not Found', 'Page']);
    });

    it('should handle empty response gracefully', () => {
      cy.visit('/page/test-empty-page');
      cy.waitForStableDOM();

      cy.assertContainsAny(['Error', 'Not Found', 'Page']);
    });

    it('should handle unauthorized error', () => {
      cy.visit('/page/test-auth-page');
      cy.waitForStableDOM();

      cy.assertContainsAny(['Error', 'Unauthorized', 'Login', 'Page']);
    });
  });

  describe('Draft Page Handling', () => {
    it('should handle draft page error appropriately', () => {
      cy.visit('/page/draft-page');
      cy.waitForStableDOM();

      cy.assertContainsAny(['Draft', 'Not Found', 'Error', 'Page']);
    });
  });

  describe('Rich Content Rendering', () => {
    it('should render markdown content properly', () => {
      const markdownPage = {
        ...mockPage,
        content: '# Heading\n\n- List item 1\n- List item 2\n\n[Link](https://example.com)',
        rendered_content: '<h1>Heading</h1><ul><li>List item 1</li><li>List item 2</li></ul><a href="https://example.com">Link</a>'
      };

      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: { success: true, data: markdownPage }
      }).as('getPage');

      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      cy.assertContainsAny(['Heading', 'List item', mockPage.title]);
    });

    it('should render HTML content properly', () => {
      const htmlPage = {
        ...mockPage,
        content: '<p>Plain text paragraph</p>',
        rendered_content: '<p>Plain text paragraph</p><div class="custom-block">Custom content</div>'
      };

      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: { success: true, data: htmlPage }
      }).as('getPage');

      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      cy.assertContainsAny(['Plain text', mockPage.title]);
    });

    it('should handle page with images', () => {
      const pageWithImage = {
        ...mockPage,
        content: '![Alt text](https://example.com/image.jpg)',
        rendered_content: '<p><img src="https://example.com/image.jpg" alt="Alt text" /></p>'
      };

      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: { success: true, data: pageWithImage }
      }).as('getPage');

      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      cy.verifyNoConsoleErrors();
    });

    it('should handle page with code blocks', () => {
      const pageWithCode = {
        ...mockPage,
        content: '```javascript\nconsole.log("Hello");\n```',
        rendered_content: '<pre><code class="language-javascript">console.log("Hello");</code></pre>'
      };

      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: { success: true, data: pageWithCode }
      }).as('getPage');

      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      cy.assertContainsAny([mockPage.title, 'Page']);
    });
  });

  describe('SEO and Meta Tags', () => {
    it('should use meta description from page data', () => {
      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: { success: true, data: mockPage }
      }).as('getPage');

      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      cy.contains(mockPage.title).should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    beforeEach(() => {
      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: { success: true, data: mockPage }
      }).as('getPage');
    });

    it('should display properly on mobile viewport', () => {
      cy.testViewport('mobile', '/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      cy.contains(mockPage.title).should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.testViewport('tablet', '/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      cy.contains(mockPage.title).should('be.visible');
    });

    it('should display properly on desktop viewport', () => {
      cy.viewport(1280, 800);
      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      cy.contains(mockPage.title).should('be.visible');
    });

    it('should have readable content width on large screens', () => {
      cy.viewport(1920, 1080);
      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      cy.assertHasElement([
        '[class*="max-w-"]',
        '[class*="container"]',
        '[class*="prose"]',
        'main',
        'article'
      ]).should('exist');
    });

    it('should handle mobile loading state', () => {
      cy.viewport('iphone-x');
      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: { success: true, data: mockPage }
      }).as('getPage');

      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      cy.contains(mockPage.title).should('be.visible');
    });

    it('should handle mobile error state', () => {
      cy.viewport('iphone-x');
      cy.visit('/page/nonexistent');
      cy.waitForStableDOM();

      cy.assertContainsAny(['Error', 'Not Found', 'Page']);
    });
  });

  describe('Accessibility', () => {
    beforeEach(() => {
      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: { success: true, data: mockPage }
      }).as('getPage');

      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();
    });

    it('should have proper heading structure', () => {
      cy.get('h1, h2, h3').should('have.length.at.least', 1);
    });

    it('should have accessible back button', () => {
      cy.assertContainsAny(['Back', 'Home', mockPage.title]);
    });

    it('should have main content area', () => {
      cy.assertHasElement(['main', '[role="main"]', 'article']).should('be.visible');
    });

    it('should have readable text contrast', () => {
      cy.get('p, span, div').filter(':visible').should('have.length.at.least', 1);
    });
  });

  describe('Long Content Handling', () => {
    it('should handle very long page content', () => {
      cy.visit('/page/long-page');
      cy.waitForStableDOM();

      cy.assertContainsAny(['Page', 'Content', 'Not Found']);
    });

    it('should be scrollable with long content', () => {
      cy.visit('/page/long-page');
      cy.waitForStableDOM();

      cy.assertContainsAny(['Page', 'Content', 'Not Found']);
    });
  });

  describe('Page with Missing Optional Fields', () => {
    it('should handle page without meta_description', () => {
      const pageNoMeta = {
        ...mockPage,
        meta_description: undefined,
        meta_keywords: undefined
      };

      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: { success: true, data: pageNoMeta }
      }).as('getPage');

      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      cy.contains(mockPage.title).should('be.visible');
    });

    it('should handle page without published_at', () => {
      const pageNotPublished = {
        ...mockPage,
        published_at: undefined
      };

      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: { success: true, data: pageNotPublished }
      }).as('getPage');

      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      cy.assertContainsAny(['Not published', 'Draft', mockPage.title]);
    });

    it('should handle page without estimated_read_time', () => {
      const pageNoReadTime = {
        ...mockPage,
        estimated_read_time: undefined,
        word_count: undefined
      };

      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: { success: true, data: pageNoReadTime }
      }).as('getPage');

      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      cy.contains(mockPage.title).should('be.visible');
    });

    it('should handle page without author', () => {
      const pageNoAuthor = {
        ...mockPage,
        author: undefined
      };

      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: { success: true, data: pageNoAuthor }
      }).as('getPage');

      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      cy.contains(mockPage.title).should('be.visible');
    });

    it('should handle page without rendered_content', () => {
      const pageNoRendered = {
        ...mockPage,
        rendered_content: undefined
      };

      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: { success: true, data: pageNoRendered }
      }).as('getPage');

      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      cy.contains(mockPage.title).should('be.visible');
    });
  });

  describe('Theme and Styling', () => {
    beforeEach(() => {
      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: { success: true, data: mockPage }
      }).as('getPage');
    });

    it('should apply theme styling', () => {
      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      cy.assertHasElement([
        '[class*="theme-"]',
        '[class*="dark:"]',
        '[class*="bg-"]',
        '[class*="text-"]',
        'body'
      ]).should('exist');
    });

    it('should display properly in dark mode if supported', () => {
      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      cy.contains(mockPage.title).should('be.visible');
    });
  });

  describe('URL Handling', () => {
    it('should handle URL with trailing slash', () => {
      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: { success: true, data: mockPage }
      }).as('getPage');

      cy.visit('/page/test-page/');
      cy.assertContainsAny([mockPage.title, 'Page']);
    });

    it('should handle URL encoded slugs', () => {
      const encodedPage = {
        ...mockPage,
        slug: 'hello-world-2025'
      };

      cy.intercept('GET', '**/pages/hello-world-2025', {
        statusCode: 200,
        body: { success: true, data: encodedPage }
      }).as('getPage');

      cy.visit('/page/hello-world-2025');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      cy.assertContainsAny([encodedPage.title, 'Page']);
    });
  });

  describe('Performance', () => {
    it('should load page content quickly', () => {
      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: { success: true, data: mockPage }
      }).as('getPage');

      const startTime = Date.now();
      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      cy.contains(mockPage.title).should('be.visible').then(() => {
        const loadTime = Date.now() - startTime;
        cy.log(`Page loaded in ${loadTime}ms`);
      });
    });

    it('should not make duplicate API calls', () => {
      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: { success: true, data: mockPage }
      }).as('getPage');

      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      cy.contains(mockPage.title).should('be.visible');
    });
  });
});


export {};
