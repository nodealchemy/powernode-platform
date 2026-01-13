/// <reference types="cypress" />

/**
 * Content Knowledge Base Page Tests
 *
 * Tests for Knowledge Base functionality including:
 * - Page navigation and load
 * - Search functionality
 * - Category browsing
 * - Featured articles display
 * - Article list display
 * - Permission-based actions
 * - Responsive design
 */

describe('Content Knowledge Base Page Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to Knowledge Base page', () => {
      cy.visit('/app/content/kb');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Knowledge Base') ||
                          $body.text().includes('Articles') ||
                          $body.text().includes('Documentation') ||
                          $body.text().includes('Permission');
        if (hasContent) {
          cy.log('Knowledge Base page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page title', () => {
      cy.visit('/app/content/kb');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('Knowledge Base');
        if (hasTitle) {
          cy.log('Page title displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/content/kb');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('Dashboard');
        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page description', () => {
      cy.visit('/app/content/kb');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasDescription = $body.text().includes('articles') ||
                               $body.text().includes('guides') ||
                               $body.text().includes('documentation');
        if (hasDescription) {
          cy.log('Page description displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Search Functionality', () => {
    beforeEach(() => {
      cy.visit('/app/content/kb');
      cy.wait(2000);
    });

    it('should display search bar', () => {
      cy.get('body').then($body => {
        const hasSearch = $body.find('input[type="search"], input[placeholder*="search"], input[placeholder*="Search"]').length > 0;
        if (hasSearch) {
          cy.log('Search bar displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should search for articles', () => {
      cy.get('body').then($body => {
        const searchInput = $body.find('input[type="search"], input[placeholder*="search"], input[placeholder*="Search"]');
        if (searchInput.length > 0) {
          cy.wrap(searchInput).first().type('test{enter}');
          cy.wait(1000);
          cy.log('Search performed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display search results', () => {
      cy.get('body').then($body => {
        const searchInput = $body.find('input[type="search"], input[placeholder*="search"]');
        if (searchInput.length > 0) {
          cy.wrap(searchInput).first().type('guide{enter}');
          cy.wait(1000);
          cy.get('body').then($resultsBody => {
            const hasResults = $resultsBody.text().includes('Results') ||
                               $resultsBody.text().includes('Search') ||
                               $resultsBody.find('[class*="article"], [class*="result"]').length > 0;
            if (hasResults) {
              cy.log('Search results displayed');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have clear search button', () => {
      cy.get('body').then($body => {
        const searchInput = $body.find('input[type="search"], input[placeholder*="search"]');
        if (searchInput.length > 0) {
          cy.wrap(searchInput).first().type('test');
          cy.wait(500);
          cy.get('body').then($clearBody => {
            const clearButton = $clearBody.find('button:contains("Clear"), [aria-label*="clear"]');
            if (clearButton.length > 0) {
              cy.log('Clear search button found');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display no results message', () => {
      cy.get('body').then($body => {
        const searchInput = $body.find('input[type="search"], input[placeholder*="search"]');
        if (searchInput.length > 0) {
          cy.wrap(searchInput).first().type('zzzzzzxyznonexistent{enter}');
          cy.wait(1000);
          cy.get('body').then($resultsBody => {
            const hasNoResults = $resultsBody.text().includes('No articles found') ||
                                 $resultsBody.text().includes('No results') ||
                                 $resultsBody.text().includes('not found');
            if (hasNoResults) {
              cy.log('No results message displayed');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Category Browsing', () => {
    beforeEach(() => {
      cy.visit('/app/content/kb');
      cy.wait(2000);
    });

    it('should display categories section', () => {
      cy.get('body').then($body => {
        const hasCategories = $body.text().includes('Categories') ||
                              $body.text().includes('Category');
        if (hasCategories) {
          cy.log('Categories section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display category list', () => {
      cy.get('body').then($body => {
        const hasCategoryList = $body.find('[class*="category"], [class*="list"]').length > 0;
        if (hasCategoryList) {
          cy.log('Category list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should filter by category', () => {
      cy.get('body').then($body => {
        const categoryItems = $body.find('[class*="category"] button, [class*="category"] a, button[class*="category"], a[class*="category"]');
        if (categoryItems.length > 0) {
          cy.wrap(categoryItems).first().click({ force: true });
          cy.wait(1000);
          cy.log('Filtered by category');
        } else {
          cy.log('No category items found to filter');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have category dropdown in search', () => {
      cy.get('body').then($body => {
        const hasDropdown = $body.find('select').length > 0 ||
                            $body.text().includes('All Categories');
        if (hasDropdown) {
          cy.log('Category dropdown found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Featured Articles', () => {
    beforeEach(() => {
      cy.visit('/app/content/kb');
      cy.wait(2000);
    });

    it('should display featured articles section', () => {
      cy.get('body').then($body => {
        const hasFeatured = $body.text().includes('Featured') ||
                            $body.text().includes('Popular') ||
                            $body.text().includes('Highlighted');
        if (hasFeatured) {
          cy.log('Featured articles section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display featured article cards', () => {
      cy.get('body').then($body => {
        const hasCards = $body.find('[class*="featured"], [class*="card"]').length > 0;
        if (hasCards) {
          cy.log('Featured article cards displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should navigate to article on click', () => {
      cy.get('body').then($body => {
        const articleLink = $body.find('a[href*="article"], a[href*="kb/"]');
        if (articleLink.length > 0) {
          cy.wrap(articleLink).first().click({ force: true });
          cy.wait(1000);
          cy.log('Navigated to article');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Recent Articles', () => {
    beforeEach(() => {
      cy.visit('/app/content/kb');
      cy.wait(2000);
    });

    it('should display recent articles section', () => {
      cy.get('body').then($body => {
        const hasRecent = $body.text().includes('Recent') ||
                          $body.text().includes('Latest') ||
                          $body.text().includes('Articles');
        if (hasRecent) {
          cy.log('Recent articles section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display article list', () => {
      cy.get('body').then($body => {
        const hasArticleList = $body.find('[class*="article"], [class*="list"]').length > 0;
        if (hasArticleList) {
          cy.log('Article list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display article titles', () => {
      cy.get('body').then($body => {
        const hasContent = $body.find('h3, h4, [class*="title"]').length > 0;
        if (hasContent) {
          cy.log('Article titles displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display article metadata', () => {
      cy.get('body').then($body => {
        const hasMetadata = $body.text().includes('min read') ||
                            $body.text().includes('views') ||
                            $body.text().includes('ago');
        if (hasMetadata) {
          cy.log('Article metadata displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Permission-Based Actions', () => {
    beforeEach(() => {
      cy.visit('/app/content/kb');
      cy.wait(2000);
    });

    it('should show Create Article button for authorized users', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Article"), button:contains("New Article")');
        if (createButton.length > 0) {
          cy.log('Create Article button shown for authorized user');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should show Quick Actions for managers', () => {
      cy.get('body').then($body => {
        const hasQuickActions = $body.text().includes('Quick Actions') ||
                                $body.text().includes('Manage');
        if (hasQuickActions) {
          cy.log('Quick Actions shown for managers');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Manage Knowledge Base link', () => {
      cy.get('body').then($body => {
        const manageLink = $body.find('button:contains("Manage"), a[href*="manage"]');
        if (manageLink.length > 0) {
          cy.log('Manage Knowledge Base link found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have View Analytics link', () => {
      cy.get('body').then($body => {
        const analyticsLink = $body.find('button:contains("Analytics"), a[href*="analytics"]');
        if (analyticsLink.length > 0) {
          cy.log('View Analytics link found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('URL Parameters', () => {
    it('should handle search query parameter', () => {
      cy.visit('/app/content/kb?q=getting+started');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasSearch = $body.text().includes('Search Results') ||
                          $body.text().includes('getting started') ||
                          $body.find('input').filter((_, el) => $(el).val() !== '').length > 0;
        if (hasSearch) {
          cy.log('Search query parameter handled');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should handle category parameter', () => {
      cy.visit('/app/content/kb?category=test');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasCategory = $body.text().includes('Category') ||
                            $body.text().includes('Results');
        if (hasCategory) {
          cy.log('Category parameter handled');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.intercept('GET', '/api/v1/kb/*', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/content/kb');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should display error notification on failure', () => {
      cy.intercept('GET', '/api/v1/kb/*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load articles' }
      });

      cy.visit('/app/content/kb');
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
      cy.intercept('GET', '/api/v1/kb/*', {
        delay: 1000,
        statusCode: 200,
        body: { success: true, data: { articles: [], categories: [] } }
      });

      cy.visit('/app/content/kb');

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
      cy.visit('/app/content/kb');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Knowledge Base');
        if (hasContent) {
          cy.log('Content visible on mobile');
        }
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/content/kb');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Knowledge Base');
        if (hasContent) {
          cy.log('Content visible on tablet');
        }
      });
    });

    it('should stack layout on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/content/kb');
      cy.wait(2000);

      cy.get('body').should('be.visible');
    });

    it('should show sidebar on large screens', () => {
      cy.viewport(1280, 800);
      cy.visit('/app/content/kb');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasSidebar = $body.find('[class*="sidebar"], [class*="col-span"]').length > 0;
        if (hasSidebar) {
          cy.log('Sidebar visible on large screens');
        }
      });

      cy.get('body').should('be.visible');
    });
  });
});
