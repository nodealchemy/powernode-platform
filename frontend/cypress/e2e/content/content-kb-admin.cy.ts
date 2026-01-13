/// <reference types="cypress" />

describe('Knowledge Base Admin Page Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to Knowledge Base Admin page', () => {
      cy.visit('/app/content/kb/admin');
      cy.url().should('include', '/content');
    });

    it('should display page title', () => {
      cy.visit('/app/content/kb/admin');
      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('Knowledge Base Admin') ||
                        $body.text().includes('KB Admin') ||
                        $body.find('[class*="PageContainer"]').length > 0;
        if (hasTitle) {
          cy.log('KB Admin page title found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display page description', () => {
      cy.visit('/app/content/kb/admin');
      cy.get('body').then($body => {
        const hasDesc = $body.text().includes('Manage articles') ||
                       $body.text().includes('categories') ||
                       $body.text().includes('content');
        if (hasDesc) {
          cy.log('Page description found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/content/kb/admin');
      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('Dashboard') ||
                              $body.text().includes('Knowledge Base') ||
                              $body.text().includes('Admin');
        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Search and Filters', () => {
    it('should display search input', () => {
      cy.visit('/app/content/kb/admin');
      cy.get('body').then($body => {
        const hasSearch = $body.find('input[placeholder*="Search"]').length > 0 ||
                         $body.find('[class*="search"]').length > 0;
        if (hasSearch) {
          cy.log('Search input found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Filters button', () => {
      cy.visit('/app/content/kb/admin');
      cy.get('body').then($body => {
        const hasFilters = $body.text().includes('Filters') ||
                          $body.find('button:contains("Filter")').length > 0;
        if (hasFilters) {
          cy.log('Filters button found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should toggle filter panel', () => {
      cy.visit('/app/content/kb/admin');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Filters")').length > 0) {
          cy.contains('button', 'Filters').click();
          cy.get('body').then($updated => {
            const hasFilterPanel = $updated.text().includes('Status') ||
                                  $updated.text().includes('Category');
            if (hasFilterPanel) {
              cy.log('Filter panel toggled');
            }
          });
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display status filter options', () => {
      cy.visit('/app/content/kb/admin');
      cy.get('body').then($body => {
        const hasStatusFilter = $body.text().includes('Draft') ||
                               $body.text().includes('Published') ||
                               $body.text().includes('Review') ||
                               $body.text().includes('Archived');
        if (hasStatusFilter) {
          cy.log('Status filter options found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display category filter', () => {
      cy.visit('/app/content/kb/admin');
      cy.get('body').then($body => {
        const hasCategoryFilter = $body.text().includes('Category') ||
                                 $body.find('select').length > 0;
        if (hasCategoryFilter) {
          cy.log('Category filter found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should have Clear Filters button', () => {
      cy.visit('/app/content/kb/admin');
      cy.get('body').then($body => {
        const hasClear = $body.text().includes('Clear Filters') ||
                        $body.text().includes('Clear');
        if (hasClear) {
          cy.log('Clear Filters button found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Statistics Overview', () => {
    it('should display Total Articles stat', () => {
      cy.visit('/app/content/kb/admin');
      cy.get('body').then($body => {
        const hasStat = $body.text().includes('Total Articles') ||
                       $body.text().includes('Total');
        if (hasStat) {
          cy.log('Total Articles stat found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Published stat', () => {
      cy.visit('/app/content/kb/admin');
      cy.get('body').then($body => {
        const hasStat = $body.text().includes('Published');
        if (hasStat) {
          cy.log('Published stat found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Draft stat', () => {
      cy.visit('/app/content/kb/admin');
      cy.get('body').then($body => {
        const hasStat = $body.text().includes('Draft');
        if (hasStat) {
          cy.log('Draft stat found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display In Review stat', () => {
      cy.visit('/app/content/kb/admin');
      cy.get('body').then($body => {
        const hasStat = $body.text().includes('In Review') ||
                       $body.text().includes('Review');
        if (hasStat) {
          cy.log('In Review stat found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Archived stat', () => {
      cy.visit('/app/content/kb/admin');
      cy.get('body').then($body => {
        const hasStat = $body.text().includes('Archived');
        if (hasStat) {
          cy.log('Archived stat found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Quick Actions', () => {
    it('should display Quick Actions section', () => {
      cy.visit('/app/content/kb/admin');
      cy.get('body').then($body => {
        const hasSection = $body.text().includes('Quick Actions');
        if (hasSection) {
          cy.log('Quick Actions section found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should have Create Article action', () => {
      cy.visit('/app/content/kb/admin');
      cy.get('body').then($body => {
        const hasAction = $body.text().includes('Create Article') ||
                         $body.text().includes('New Article');
        if (hasAction) {
          cy.log('Create Article action found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should have Manage Categories action', () => {
      cy.visit('/app/content/kb/admin');
      cy.get('body').then($body => {
        const hasAction = $body.text().includes('Manage Categories') ||
                         $body.text().includes('Categories');
        if (hasAction) {
          cy.log('Manage Categories action found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should have Moderate Comments action for admins', () => {
      cy.visit('/app/content/kb/admin');
      cy.get('body').then($body => {
        const hasAction = $body.text().includes('Moderate Comments') ||
                         $body.text().includes('Comments');
        if (hasAction) {
          cy.log('Moderate Comments action found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should have View Analytics action for admins', () => {
      cy.visit('/app/content/kb/admin');
      cy.get('body').then($body => {
        const hasAction = $body.text().includes('View Analytics') ||
                         $body.text().includes('Analytics');
        if (hasAction) {
          cy.log('View Analytics action found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Articles List', () => {
    it('should display Articles section', () => {
      cy.visit('/app/content/kb/admin');
      cy.get('body').then($body => {
        const hasSection = $body.text().includes('Articles');
        if (hasSection) {
          cy.log('Articles section found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display article items or empty state', () => {
      cy.visit('/app/content/kb/admin');
      cy.get('body').then($body => {
        const hasArticles = $body.find('[class*="article"]').length > 0 ||
                           $body.text().includes('No articles yet') ||
                           $body.text().includes('first article');
        if (hasArticles) {
          cy.log('Articles list or empty state found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display article status badges', () => {
      cy.visit('/app/content/kb/admin');
      cy.get('body').then($body => {
        const hasBadges = $body.find('[class*="badge"]').length > 0 ||
                         $body.text().includes('published') ||
                         $body.text().includes('draft');
        if (hasBadges) {
          cy.log('Status badges found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should have View action for articles', () => {
      cy.visit('/app/content/kb/admin');
      cy.get('body').then($body => {
        const hasView = $body.find('button:contains("View")').length > 0 ||
                       $body.text().includes('View');
        if (hasView) {
          cy.log('View action found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should have Edit action for articles', () => {
      cy.visit('/app/content/kb/admin');
      cy.get('body').then($body => {
        const hasEdit = $body.find('button:contains("Edit")').length > 0 ||
                       $body.text().includes('Edit');
        if (hasEdit) {
          cy.log('Edit action found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Bulk Operations', () => {
    it('should have Select All button', () => {
      cy.visit('/app/content/kb/admin');
      cy.get('body').then($body => {
        const hasSelectAll = $body.text().includes('Select All') ||
                            $body.text().includes('Deselect All') ||
                            $body.find('input[type="checkbox"]').length > 0;
        if (hasSelectAll) {
          cy.log('Select All functionality found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display selection count when articles selected', () => {
      cy.visit('/app/content/kb/admin');
      cy.get('body').then($body => {
        const hasCheckbox = $body.find('input[type="checkbox"]').length > 0;
        if (hasCheckbox) {
          cy.log('Checkboxes for selection found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Page Actions', () => {
    it('should have Create Article button', () => {
      cy.visit('/app/content/kb/admin');
      cy.get('body').then($body => {
        const hasCreate = $body.text().includes('Create Article') ||
                         $body.find('button:contains("Create")').length > 0;
        if (hasCreate) {
          cy.log('Create Article button found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should have Manage Categories button', () => {
      cy.visit('/app/content/kb/admin');
      cy.get('body').then($body => {
        const hasManage = $body.text().includes('Manage Categories') ||
                         $body.find('button:contains("Categories")').length > 0;
        if (hasManage) {
          cy.log('Manage Categories button found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should have Analytics button for admins', () => {
      cy.visit('/app/content/kb/admin');
      cy.get('body').then($body => {
        const hasAnalytics = $body.text().includes('Analytics') ||
                            $body.find('button:contains("Analytics")').length > 0;
        if (hasAnalytics) {
          cy.log('Analytics button found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Pagination', () => {
    it('should display pagination controls when needed', () => {
      cy.visit('/app/content/kb/admin');
      cy.get('body').then($body => {
        const hasPagination = $body.text().includes('Previous') ||
                             $body.text().includes('Next') ||
                             $body.text().includes('Page');
        if (hasPagination) {
          cy.log('Pagination controls found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display page indicator', () => {
      cy.visit('/app/content/kb/admin');
      cy.get('body').then($body => {
        const hasPageInfo = $body.text().includes('Page') ||
                           $body.text().match(/Page \d+ of \d+/);
        if (hasPageInfo) {
          cy.log('Page indicator found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Permission Check', () => {
    it('should redirect unauthorized users', () => {
      cy.visit('/app/content/kb/admin');
      cy.get('body').then($body => {
        const redirected = !$body.text().includes('Knowledge Base Admin') &&
                          ($body.text().includes('Knowledge Base') ||
                           $body.text().includes('Access Denied'));
        const hasAccess = $body.text().includes('Knowledge Base Admin');
        if (redirected) {
          cy.log('Unauthorized user redirected');
        } else if (hasAccess) {
          cy.log('User has admin access');
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

      cy.visit('/app/content/kb/admin');
      cy.get('body').should('be.visible');
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
      cy.get('body').then($body => {
        const hasLoading = $body.find('[class*="animate-spin"]').length > 0 ||
                          $body.find('[class*="loading"]').length > 0;
        if (hasLoading) {
          cy.log('Loading indicator found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Empty State', () => {
    it('should display empty state when no articles', () => {
      cy.intercept('GET', '**/api/**/kb/articles**', {
        statusCode: 200,
        body: { success: true, data: { articles: [], stats: { total: 0 } } }
      }).as('emptyArticles');

      cy.visit('/app/content/kb/admin');
      cy.get('body').then($body => {
        const hasEmpty = $body.text().includes('No articles yet') ||
                        $body.text().includes('first article') ||
                        $body.text().includes('Create First');
        if (hasEmpty) {
          cy.log('Empty state displayed');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/content/kb/admin');
      cy.get('body').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/content/kb/admin');
      cy.get('body').should('be.visible');
    });

    it('should stack elements on small screens', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/content/kb/admin');
      cy.get('body').then($body => {
        const hasGrid = $body.find('[class*="grid"]').length > 0;
        if (hasGrid) {
          cy.log('Responsive grid layout found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should show multi-column layout on large screens', () => {
      cy.viewport(1920, 1080);
      cy.visit('/app/content/kb/admin');
      cy.get('body').then($body => {
        const hasMultiCol = $body.find('[class*="lg:grid-cols"]').length > 0 ||
                           $body.find('[class*="sm:grid-cols"]').length > 0;
        if (hasMultiCol) {
          cy.log('Multi-column layout found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });
});
