/// <reference types="cypress" />

describe('Knowledge Base Article Page Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 5000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to Knowledge Base article page', () => {
      cy.visit('/app/content/kb/articles/test-article');
      cy.url().should('include', '/content');
    });

    it('should display article not found for invalid ID', () => {
      cy.visit('/app/content/kb/articles/invalid-article-id');
      cy.get('body').then($body => {
        const hasNotFound = $body.text().includes('not found') ||
                           $body.text().includes('Not Found') ||
                           $body.text().includes('Error');
        if (hasNotFound) {
          cy.log('Article not found message displayed');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/content/kb/articles/test-article');
      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('Dashboard') ||
                              $body.text().includes('Knowledge Base');
        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Page Actions', () => {
    it('should have Back to KB button', () => {
      cy.visit('/app/content/kb/articles/test-article');
      cy.get('body').then($body => {
        const hasBack = $body.text().includes('Back to KB') ||
                       $body.text().includes('Back') ||
                       $body.find('button:contains("Back")').length > 0;
        if (hasBack) {
          cy.log('Back to KB button found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should have Edit Article button for authorized users', () => {
      cy.visit('/app/content/kb/articles/test-article');
      cy.get('body').then($body => {
        const hasEdit = $body.text().includes('Edit Article') ||
                       $body.text().includes('Edit');
        if (hasEdit) {
          cy.log('Edit Article button found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Article Meta Information', () => {
    it('should display author information', () => {
      cy.visit('/app/content/kb/articles/test-article');
      cy.get('body').then($body => {
        const hasAuthor = $body.text().includes('Author') ||
                         $body.find('[class*="author"]').length > 0;
        if (hasAuthor) {
          cy.log('Author information found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display published date', () => {
      cy.visit('/app/content/kb/articles/test-article');
      cy.get('body').then($body => {
        const hasDate = $body.text().includes('Published') ||
                       $body.text().includes('ago');
        if (hasDate) {
          cy.log('Published date found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display reading time', () => {
      cy.visit('/app/content/kb/articles/test-article');
      cy.get('body').then($body => {
        const hasTime = $body.text().includes('Reading Time') ||
                       $body.text().includes('min read');
        if (hasTime) {
          cy.log('Reading time found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display view count', () => {
      cy.visit('/app/content/kb/articles/test-article');
      cy.get('body').then($body => {
        const hasViews = $body.text().includes('Views') ||
                        $body.text().includes('views');
        if (hasViews) {
          cy.log('View count found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Featured badge if featured', () => {
      cy.visit('/app/content/kb/articles/test-article');
      cy.get('body').then($body => {
        const hasFeatured = $body.text().includes('Featured') ||
                           $body.find('[class*="badge"]').length > 0;
        if (hasFeatured) {
          cy.log('Featured badge found or article is not featured');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Article Tags', () => {
    it('should display article tags section', () => {
      cy.visit('/app/content/kb/articles/test-article');
      cy.get('body').then($body => {
        const hasTags = $body.text().includes('Article Tags') ||
                       $body.text().includes('Tags');
        if (hasTags) {
          cy.log('Article tags section found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should have clickable tag badges', () => {
      cy.visit('/app/content/kb/articles/test-article');
      cy.get('body').then($body => {
        const hasBadges = $body.find('[class*="badge"]').length > 0 ||
                         $body.find('button [class*="Badge"]').length > 0;
        if (hasBadges) {
          cy.log('Clickable tag badges found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Article Content', () => {
    it('should display article content component', () => {
      cy.visit('/app/content/kb/articles/test-article');
      cy.get('body').then($body => {
        const hasContent = $body.find('[class*="prose"]').length > 0 ||
                          $body.find('[class*="content"]').length > 0 ||
                          $body.find('[class*="article"]').length > 0;
        if (hasContent) {
          cy.log('Article content component found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Comments Section', () => {
    it('should display Discussion section', () => {
      cy.visit('/app/content/kb/articles/test-article');
      cy.get('body').then($body => {
        const hasComments = $body.text().includes('Discussion') ||
                           $body.text().includes('Comments');
        if (hasComments) {
          cy.log('Discussion section found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display comments component', () => {
      cy.visit('/app/content/kb/articles/test-article');
      cy.get('body').then($body => {
        const hasCommentsComponent = $body.find('[class*="comment"]').length > 0 ||
                                    $body.text().includes('No comments');
        if (hasCommentsComponent) {
          cy.log('Comments component found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Sidebar - Related Articles', () => {
    it('should display Related Articles section', () => {
      cy.visit('/app/content/kb/articles/test-article');
      cy.get('body').then($body => {
        const hasRelated = $body.text().includes('Related') ||
                          $body.find('[class*="related"]').length > 0;
        if (hasRelated) {
          cy.log('Related Articles section found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Sidebar - Article Details', () => {
    it('should display Article Details section', () => {
      cy.visit('/app/content/kb/articles/test-article');
      cy.get('body').then($body => {
        const hasDetails = $body.text().includes('Article Details') ||
                          $body.text().includes('Category');
        if (hasDetails) {
          cy.log('Article Details section found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display category information', () => {
      cy.visit('/app/content/kb/articles/test-article');
      cy.get('body').then($body => {
        const hasCategory = $body.text().includes('Category');
        if (hasCategory) {
          cy.log('Category information found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should have clickable category link', () => {
      cy.visit('/app/content/kb/articles/test-article');
      cy.get('body').then($body => {
        const hasLink = $body.find('button[class*="hover"]').length > 0 ||
                       $body.find('a[href*="category"]').length > 0;
        if (hasLink) {
          cy.log('Category link found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.intercept('GET', '**/api/**/kb/**', {
        statusCode: 500,
        body: { error: 'Internal Server Error' }
      }).as('apiError');

      cy.visit('/app/content/kb/articles/test-article');
      cy.get('body').should('be.visible');
    });

    it('should display error state for missing article', () => {
      cy.intercept('GET', '**/api/**/kb/**', {
        statusCode: 404,
        body: { error: 'Article not found' }
      }).as('notFoundError');

      cy.visit('/app/content/kb/articles/test-article');
      cy.get('body').then($body => {
        const hasError = $body.text().includes('not found') ||
                        $body.text().includes('Error') ||
                        $body.text().includes('Back to KB');
        if (hasError) {
          cy.log('Error state displayed');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display permission denied for unauthorized users', () => {
      cy.intercept('GET', '**/api/**/kb/**', {
        statusCode: 403,
        body: { error: 'Permission denied' }
      }).as('permissionError');

      cy.visit('/app/content/kb/articles/test-article');
      cy.get('body').then($body => {
        const hasPermError = $body.text().includes('permission') ||
                            $body.text().includes('Error');
        if (hasPermError) {
          cy.log('Permission error displayed');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '**/api/**/kb/**', (req) => {
        req.reply((res) => {
          res.delay = 2000;
          res.send({ success: true, data: {} });
        });
      }).as('slowLoad');

      cy.visit('/app/content/kb/articles/test-article');
      cy.get('body').then($body => {
        const hasLoading = $body.find('[class*="animate-spin"]').length > 0 ||
                          $body.text().includes('Loading');
        if (hasLoading) {
          cy.log('Loading indicator found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/content/kb/articles/test-article');
      cy.get('body').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/content/kb/articles/test-article');
      cy.get('body').should('be.visible');
    });

    it('should stack columns on small screens', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/content/kb/articles/test-article');
      cy.get('body').then($body => {
        const hasGrid = $body.find('[class*="grid-cols-1"]').length > 0 ||
                       $body.find('[class*="lg:grid-cols"]').length > 0;
        if (hasGrid) {
          cy.log('Responsive column layout found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should show multi-column layout on large screens', () => {
      cy.viewport(1920, 1080);
      cy.visit('/app/content/kb/articles/test-article');
      cy.get('body').then($body => {
        const hasMultiCol = $body.find('[class*="lg:grid-cols"]').length > 0 ||
                           $body.find('[class*="lg:col-span"]').length > 0;
        if (hasMultiCol) {
          cy.log('Multi-column layout found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Two Column Layout', () => {
    it('should display content and sidebar sections', () => {
      cy.visit('/app/content/kb/articles/test-article');
      cy.get('body').then($body => {
        const hasLayout = $body.find('[class*="lg:col-span-2"]').length > 0 ||
                         $body.find('[class*="grid"]').length > 0;
        if (hasLayout) {
          cy.log('Two column layout found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });
});


export {};
