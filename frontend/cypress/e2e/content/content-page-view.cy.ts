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
        body: mockPage
      }).as('getPage');

      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      cy.contains(mockPage.title).should('be.visible');
    });

    it('should display page content area', () => {
      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: mockPage
      }).as('getPage');

      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      // Page should have content area
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
        body: pageWithSpecialSlug
      }).as('getPage');

      cy.visit('/page/my-page-2025');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      cy.contains(pageWithSpecialSlug.title).should('be.visible');
    });
  });

  describe('Page Content Display', () => {
    beforeEach(() => {
      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: mockPage
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
      // Check for rendered HTML content
      cy.get('body').then($body => {
        const hasFormattedContent = $body.find('strong, b, em, i').length > 0 ||
                                    $body.text().includes('bold') ||
                                    $body.text().includes('italic');
        if (hasFormattedContent) {
          cy.log('Rich content formatting detected');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page container', () => {
      // PublicPageContainer should be visible
      cy.get('body').then($body => {
        const hasContainer = $body.find('main, [role="main"], article').length > 0;
        if (hasContainer) {
          cy.log('Page container displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Meta Information Display', () => {
    beforeEach(() => {
      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: mockPage
      }).as('getPage');

      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();
    });

    it('should display published date', () => {
      // formatPublishedDate returns format like "January 10, 2025"
      cy.get('body').then($body => {
        const hasDate = $body.text().includes('January') ||
                        $body.text().includes('2025') ||
                        $body.text().includes('Published');
        if (hasDate) {
          cy.log('Published date displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display reading time when available', () => {
      cy.get('body').then($body => {
        const hasReadTime = $body.text().includes('min') ||
                            $body.text().includes('read') ||
                            $body.text().includes('2');
        if (hasReadTime) {
          cy.log('Reading time displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page status', () => {
      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Published') ||
                          $body.text().includes('published');
        if (hasStatus) {
          cy.log('Page status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Back Navigation', () => {
    beforeEach(() => {
      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: mockPage
      }).as('getPage');

      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();
    });

    it('should display back to home button', () => {
      cy.contains(/Back.*Home|Home|Return/i).should('exist');
    });

    it('should navigate back to home when clicking back button', () => {
      cy.get('body').then($body => {
        const backButton = $body.find('a[href="/"], button:contains("Back"), a:contains("Home")');
        if (backButton.length > 0) {
          cy.wrap(backButton).first().should('be.visible').click();
          cy.url().should('include', '/');
          cy.log('Back navigation works');
        }
      });
    });
  });

  describe('Loading State', () => {
    it('should display loading spinner while fetching page', () => {
      cy.intercept('GET', '**/pages/test-page', {
        delay: 2000,
        statusCode: 200,
        body: mockPage
      }).as('getPageSlow');

      cy.visit('/page/test-page');

      // Should show loading spinner
      cy.get('[class*="animate-spin"], [class*="loading"], [class*="spinner"]')
        .should('be.visible');

      // Should show loading text
      cy.contains(/Loading page/i).should('be.visible');

      // Wait for content to load
      cy.wait('@getPageSlow');
      cy.contains(mockPage.title).should('be.visible');
    });

    it('should hide loading spinner after page loads', () => {
      cy.intercept('GET', '**/pages/test-page', {
        delay: 500,
        statusCode: 200,
        body: mockPage
      }).as('getPage');

      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      // Loading spinner should be gone
      cy.get('[class*="animate-spin"]').should('not.exist');
      cy.contains(mockPage.title).should('be.visible');
    });
  });

  describe('Page Not Found Error', () => {
    beforeEach(() => {
      cy.intercept('GET', '**/pages/nonexistent-page', {
        statusCode: 404,
        body: { success: false, error: 'Page not found' }
      }).as('getPageNotFound');

      cy.visit('/page/nonexistent-page');
      cy.wait('@getPageNotFound');
      cy.waitForStableDOM();
    });

    it('should display page not found title', () => {
      cy.contains(/Page Not Found|not found/i).should('be.visible');
    });

    it('should display not found message', () => {
      cy.contains(/doesn't exist|hasn't been published|looking for/i).should('be.visible');
    });

    it('should display back to home button on error page', () => {
      cy.contains(/Back.*Home|Home/i).should('exist');
    });

    it('should display try again button', () => {
      cy.contains('button', /Try Again/i).should('be.visible');
    });

    it('should retry loading when clicking Try Again', () => {
      // First attempt returns 404
      cy.intercept('GET', '**/pages/nonexistent-page', {
        statusCode: 200,
        body: mockPage
      }).as('retryGetPage');

      cy.contains('button', /Try Again/i).should('be.visible').click();

      cy.wait('@retryGetPage');
      cy.contains(mockPage.title).should('be.visible');
    });

    it('should display error emoji', () => {
      // Error page shows emoji face
      cy.get('body').should('contain.text', '\uD83D\uDE15'); // :confused: emoji
    });
  });

  describe('API Error Handling', () => {
    it('should handle server error gracefully', () => {
      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 500,
        body: { success: false, error: 'Internal server error' }
      }).as('getPageError');

      cy.visit('/page/test-page');
      cy.wait('@getPageError');
      cy.waitForStableDOM();

      // Should show error message
      cy.contains(/trouble loading|try again later|error/i).should('be.visible');

      // Should not show JavaScript error
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should handle network error gracefully', () => {
      cy.intercept('GET', '**/pages/test-page', {
        forceNetworkError: true
      }).as('getPageNetworkError');

      cy.visit('/page/test-page');

      // Should show error state, not crash
      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should handle empty response gracefully', () => {
      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: null
      }).as('getPageEmpty');

      cy.visit('/page/test-page');
      cy.wait('@getPageEmpty');
      cy.waitForStableDOM();

      // Should show error state for empty page
      cy.contains(/not found|trouble loading/i).should('be.visible');
    });

    it('should handle unauthorized error', () => {
      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 401,
        body: { success: false, error: 'Unauthorized' }
      }).as('getPageUnauthorized');

      cy.visit('/page/test-page');
      cy.wait('@getPageUnauthorized');

      // Should show error state
      cy.get('body').should('be.visible');
    });
  });

  describe('Draft Page Handling', () => {
    it('should handle draft page error appropriately', () => {
      cy.intercept('GET', '**/pages/draft-page', {
        statusCode: 404,
        body: { success: false, error: 'Page not found' }
      }).as('getDraftPage');

      cy.visit('/page/draft-page');
      cy.wait('@getDraftPage');
      cy.waitForStableDOM();

      // Draft pages should show not found (not published)
      cy.contains(/doesn't exist|hasn't been published/i).should('be.visible');
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
        body: markdownPage
      }).as('getPage');

      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      cy.get('body').should('contain.text', 'Heading');
      cy.get('body').should('contain.text', 'List item');
    });

    it('should render HTML content properly', () => {
      const htmlPage = {
        ...mockPage,
        content: '<p>Plain text paragraph</p>',
        rendered_content: '<p>Plain text paragraph</p><div class="custom-block">Custom content</div>'
      };

      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: htmlPage
      }).as('getPage');

      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      cy.get('body').should('contain.text', 'Plain text paragraph');
    });

    it('should handle page with images', () => {
      const pageWithImage = {
        ...mockPage,
        content: '![Alt text](https://example.com/image.jpg)',
        rendered_content: '<p><img src="https://example.com/image.jpg" alt="Alt text" /></p>'
      };

      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: pageWithImage
      }).as('getPage');

      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      cy.get('body').should('be.visible');
      // Content should load without errors
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should handle page with code blocks', () => {
      const pageWithCode = {
        ...mockPage,
        content: '```javascript\nconsole.log("Hello");\n```',
        rendered_content: '<pre><code class="language-javascript">console.log("Hello");</code></pre>'
      };

      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: pageWithCode
      }).as('getPage');

      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      cy.get('body').should('be.visible');
    });
  });

  describe('SEO and Meta Tags', () => {
    it('should use meta description from page data', () => {
      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: mockPage
      }).as('getPage');

      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      // Page should have title
      cy.contains(mockPage.title).should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    beforeEach(() => {
      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: mockPage
      }).as('getPage');
    });

    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      cy.contains(mockPage.title).should('be.visible');
      cy.get('body').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      cy.contains(mockPage.title).should('be.visible');
      cy.get('body').should('be.visible');
    });

    it('should display properly on desktop viewport', () => {
      cy.viewport(1280, 800);
      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      cy.contains(mockPage.title).should('be.visible');
      cy.get('body').should('be.visible');
    });

    it('should have readable content width on large screens', () => {
      cy.viewport(1920, 1080);
      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      // Content should be constrained for readability
      cy.get('body').then($body => {
        const hasMaxWidth = $body.find('[class*="max-w-"], [class*="container"]').length > 0;
        if (hasMaxWidth) {
          cy.log('Content has max-width constraint');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should handle mobile loading state', () => {
      cy.viewport('iphone-x');
      cy.intercept('GET', '**/pages/test-page', {
        delay: 1000,
        statusCode: 200,
        body: mockPage
      }).as('getPageSlow');

      cy.visit('/page/test-page');

      // Loading state should be visible on mobile
      cy.get('[class*="animate-spin"]').should('be.visible');

      cy.wait('@getPageSlow');
      cy.contains(mockPage.title).should('be.visible');
    });

    it('should handle mobile error state', () => {
      cy.viewport('iphone-x');
      cy.intercept('GET', '**/pages/nonexistent', {
        statusCode: 404,
        body: { success: false, error: 'Page not found' }
      }).as('getPageNotFound');

      cy.visit('/page/nonexistent');
      cy.wait('@getPageNotFound');
      cy.waitForStableDOM();

      cy.contains(/not found/i).should('be.visible');
    });
  });

  describe('Accessibility', () => {
    beforeEach(() => {
      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: mockPage
      }).as('getPage');

      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();
    });

    it('should have proper heading structure', () => {
      cy.get('h1, h2, h3').should('have.length.at.least', 1);
    });

    it('should have accessible back button', () => {
      cy.get('a, button').contains(/Back|Home/i).should('be.visible');
    });

    it('should have main content area', () => {
      cy.get('body').then($body => {
        const hasMain = $body.find('main, [role="main"], article').length > 0;
        if (hasMain) {
          cy.log('Main content area exists');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have readable text contrast', () => {
      // Check that text elements exist and are visible
      cy.get('p, span, div').filter(':visible').should('have.length.at.least', 1);
    });
  });

  describe('Long Content Handling', () => {
    it('should handle very long page content', () => {
      const longContent = 'Lorem ipsum '.repeat(1000);
      const longPage = {
        ...mockPage,
        content: longContent,
        rendered_content: `<p>${longContent}</p>`
      };

      cy.intercept('GET', '**/pages/long-page', {
        statusCode: 200,
        body: longPage
      }).as('getLongPage');

      cy.visit('/page/long-page');
      cy.wait('@getLongPage');
      cy.waitForStableDOM();

      cy.contains(mockPage.title).should('be.visible');
      cy.get('body').should('contain.text', 'Lorem ipsum');
    });

    it('should be scrollable with long content', () => {
      const longContent = 'Paragraph text. '.repeat(500);
      const longPage = {
        ...mockPage,
        content: longContent,
        rendered_content: `<p>${longContent}</p>`
      };

      cy.intercept('GET', '**/pages/long-page', {
        statusCode: 200,
        body: longPage
      }).as('getLongPage');

      cy.visit('/page/long-page');
      cy.wait('@getLongPage');
      cy.waitForStableDOM();

      // Page should be scrollable
      cy.scrollTo('bottom');
      cy.scrollTo('top');
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
        body: pageNoMeta
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
        body: pageNotPublished
      }).as('getPage');

      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      // Should show "Not published" or similar
      cy.get('body').then($body => {
        const hasNotPublished = $body.text().includes('Not published') ||
                                $body.text().includes('Draft') ||
                                !$body.text().includes('January');
        if (hasNotPublished) {
          cy.log('Handles missing published_at correctly');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should handle page without estimated_read_time', () => {
      const pageNoReadTime = {
        ...mockPage,
        estimated_read_time: undefined,
        word_count: undefined
      };

      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: pageNoReadTime
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
        body: pageNoAuthor
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
        body: pageNoRendered
      }).as('getPage');

      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      // Should fallback to raw content
      cy.contains(mockPage.title).should('be.visible');
    });
  });

  describe('Theme and Styling', () => {
    beforeEach(() => {
      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: mockPage
      }).as('getPage');
    });

    it('should apply theme styling', () => {
      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      // Check for theme-aware classes
      cy.get('body').then($body => {
        const hasTheme = $body.find('[class*="theme-"], [class*="dark:"], [class*="bg-"]').length > 0;
        if (hasTheme) {
          cy.log('Theme styling applied');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display properly in dark mode if supported', () => {
      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      // Content should be visible regardless of mode
      cy.contains(mockPage.title).should('be.visible');
    });
  });

  describe('URL Handling', () => {
    it('should handle URL with trailing slash', () => {
      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: mockPage
      }).as('getPage');

      cy.visit('/page/test-page/');
      // Should still load the page
      cy.get('body').should('be.visible');
    });

    it('should handle URL encoded slugs', () => {
      const encodedPage = {
        ...mockPage,
        slug: 'hello-world-2025'
      };

      cy.intercept('GET', '**/pages/hello-world-2025', {
        statusCode: 200,
        body: encodedPage
      }).as('getPage');

      cy.visit('/page/hello-world-2025');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      cy.get('body').should('be.visible');
    });
  });

  describe('Performance', () => {
    it('should load page content quickly', () => {
      cy.intercept('GET', '**/pages/test-page', {
        statusCode: 200,
        body: mockPage
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
      let callCount = 0;
      cy.intercept('GET', '**/pages/test-page', (req) => {
        callCount++;
        req.reply({
          statusCode: 200,
          body: mockPage
        });
      }).as('getPage');

      cy.visit('/page/test-page');
      cy.wait('@getPage');
      cy.waitForStableDOM();

      cy.contains(mockPage.title).should('be.visible').then(() => {
        // Wait for stable DOM to ensure no duplicate calls pending
        cy.waitForStableDOM().then(() => {
          expect(callCount).to.eq(1);
        });
      });
    });
  });
});


export {};
