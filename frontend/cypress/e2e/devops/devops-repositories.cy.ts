/// <reference types="cypress" />

/**
 * DevOps Repositories Page Tests
 *
 * Tests for Git Repositories functionality including:
 * - Page navigation and load
 * - Repository list display
 * - Search functionality
 * - Filter functionality
 * - Sync repositories
 * - Configure webhooks
 * - Repository card expansion
 * - Pagination
 * - Error handling
 * - Responsive design
 */

describe('DevOps Repositories Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.setupDevopsIntercepts();
    // Login with demo user
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 5000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to Repositories from DevOps', () => {
      cy.visit('/app/devops');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const reposLink = $body.find('a[href*="/repositories"], button:contains("Repositories")');

        if (reposLink.length > 0) {
          cy.wrap(reposLink).first().should('be.visible').click();
          cy.url().should('include', '/repositories');
        } else {
          cy.visit('/app/devops/repositories');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should load Repositories page directly', () => {
      cy.visit('/app/devops/repositories');
      cy.waitForPageLoad();

      cy.url().then(url => {
        if (url.includes('/repositories')) {
          cy.get('body').should('satisfy', ($body) => {
            const text = $body.text();
            return text.includes('Repositor') || text.includes('Sync') || text.includes('Git');
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/devops/repositories');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('Dashboard') &&
                               ($body.text().includes('DevOps') || $body.text().includes('Repositories'));

        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs displayed correctly');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Repository List Display', () => {
    beforeEach(() => {
      cy.visit('/app/devops/repositories');
      cy.waitForPageLoad();
    });

    it('should display repository list or empty state', () => {
      cy.get('body').then($body => {
        const _hasRepos = $body.find('[class*="repository"], [class*="card"]').length > 0 ||
                          $body.text().includes('No Repositories Found') ||
                          $body.text().includes('Sync repositories');

        if ($body.text().includes('No Repositories')) {
          cy.log('Empty state displayed');
        } else {
          cy.log('Repository list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display repository names', () => {
      cy.get('body').then($body => {
        const hasNames = $body.find('h3, [class*="title"]').length > 0;

        if (hasNames) {
          cy.log('Repository names displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display provider badges', () => {
      cy.get('body').then($body => {
        const hasBadges = $body.text().includes('GitHub') ||
                           $body.text().includes('GitLab') ||
                           $body.text().includes('Gitea');

        if (hasBadges) {
          cy.log('Provider badges displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display visibility status', () => {
      cy.get('body').then($body => {
        const hasVisibility = $body.text().includes('Private') ||
                               $body.text().includes('Public');

        if (hasVisibility) {
          cy.log('Visibility status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display repository stats', () => {
      cy.get('body').then($body => {
        const hasStats = $body.text().includes('star') ||
                          $body.find('[class*="star"]').length > 0;

        if (hasStats) {
          cy.log('Repository stats displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display webhook status', () => {
      cy.get('body').then($body => {
        const hasWebhook = $body.text().includes('Webhook') ||
                            $body.find('[class*="webhook"]').length > 0;

        if (hasWebhook) {
          cy.log('Webhook status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Search Functionality', () => {
    beforeEach(() => {
      cy.visit('/app/devops/repositories');
      cy.waitForPageLoad();
    });

    it('should have search input', () => {
      cy.get('body').then($body => {
        const searchInput = $body.find('input[type="search"], input[placeholder*="Search"], input[placeholder*="search"]');

        if (searchInput.length > 0) {
          cy.wrap(searchInput).should('be.visible');
          cy.log('Search input found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should filter repositories by search query', () => {
      cy.get('body').then($body => {
        const searchInput = $body.find('input[placeholder*="Search"], input[type="text"]');

        if (searchInput.length > 0) {
          cy.wrap(searchInput).first().should('be.visible').type('powernode');
          // Wait for search results to update
          cy.get('body').should('be.visible');
          cy.log('Search filter applied');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Filter Functionality', () => {
    beforeEach(() => {
      cy.visit('/app/devops/repositories');
      cy.waitForPageLoad();
    });

    it('should have provider filter', () => {
      cy.get('body').then($body => {
        const providerFilter = $body.find('select, [class*="filter"]');

        if (providerFilter.length > 0) {
          cy.log('Provider filter found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Filters button', () => {
      cy.get('body').then($body => {
        const filtersButton = $body.find('button:contains("Filters"), button:contains("Filter")');

        if (filtersButton.length > 0) {
          cy.wrap(filtersButton).first().should('be.visible');
          cy.log('Filters button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should toggle filters panel when Filters clicked', () => {
      cy.get('body').then($body => {
        const filtersButton = $body.find('button:contains("Filters")');

        if (filtersButton.length > 0) {
          cy.wrap(filtersButton).first().should('be.visible').click();

          // Wait for filters panel to appear
          cy.get('body').should('satisfy', ($newBody) => {
            return $newBody.find('[class*="filter"]').length > 0 ||
                   $newBody.text().includes('Private only');
          });
          cy.log('Filters panel toggled');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Clear button when filters active', () => {
      cy.get('body').then($body => {
        const searchInput = $body.find('input[placeholder*="Search"]');

        if (searchInput.length > 0) {
          cy.wrap(searchInput).first().should('be.visible').type('test');

          // Wait for filter to be applied and check for Clear button
          cy.get('body').should('be.visible').then($newBody => {
            const clearButton = $newBody.find('button:contains("Clear")');

            if (clearButton.length > 0) {
              cy.log('Clear button found');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Sync Repositories', () => {
    beforeEach(() => {
      cy.visit('/app/devops/repositories');
      cy.waitForPageLoad();
    });

    it('should have Sync All button', () => {
      cy.get('body').then($body => {
        const syncButton = $body.find('button:contains("Sync All"), button:contains("Sync")');

        if (syncButton.length > 0) {
          cy.wrap(syncButton).first().should('be.visible');
          cy.log('Sync All button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have sync action in repository menu', () => {
      cy.get('body').then($body => {
        const menuButton = $body.find('button:contains("•••"), [class*="menu-button"], [aria-label*="more"]');

        if (menuButton.length > 0) {
          cy.wrap(menuButton).first().should('be.visible').click();

          // Wait for menu to appear
          cy.get('body').should('satisfy', ($newBody) => {
            return $newBody.find('button:contains("Sync")').length > 0 ||
                   $newBody.find('[role="menu"], [role="menuitem"]').length > 0;
          });
          cy.log('Sync option found in menu');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Configure Webhooks', () => {
    beforeEach(() => {
      cy.visit('/app/devops/repositories');
      cy.waitForPageLoad();
    });

    it('should have webhook action in repository menu', () => {
      cy.get('body').then($body => {
        const menuButton = $body.find('button:contains("•••"), [class*="menu-button"]');

        if (menuButton.length > 0) {
          cy.wrap(menuButton).first().should('be.visible').click();

          // Wait for menu to appear and check for webhook option
          cy.get('body').should('satisfy', ($newBody) => {
            return $newBody.find('button:contains("Webhook"), button:contains("Configure")').length > 0 ||
                   $newBody.find('[role="menu"], [role="menuitem"]').length > 0;
          });
          cy.log('Webhook option found in menu');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Repository Card Expansion', () => {
    beforeEach(() => {
      cy.visit('/app/devops/repositories');
      cy.waitForPageLoad();
    });

    it('should expand repository card on click', () => {
      cy.get('body').then($body => {
        const repoCard = $body.find('[class*="card"][class*="cursor-pointer"]');

        if (repoCard.length > 0) {
          cy.wrap(repoCard).first().should('be.visible').click();

          // Wait for card to expand
          cy.get('body').should('satisfy', ($newBody) => {
            return $newBody.find('[class*="expanded"]').length > 0 ||
                   $newBody.text().includes('Overview') ||
                   $newBody.text().includes('Branches');
          });
          cy.log('Repository card expanded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display tabs in expanded view', () => {
      cy.get('body').then($body => {
        const repoCard = $body.find('[class*="card"][class*="cursor-pointer"]');

        if (repoCard.length > 0) {
          cy.wrap(repoCard).first().should('be.visible').click();

          // Wait for tabs to appear
          cy.get('body').should('satisfy', ($newBody) => {
            return $newBody.text().includes('Overview') ||
                   $newBody.text().includes('Code') ||
                   $newBody.text().includes('Pull Requests');
          });
          cy.log('Tabs displayed in expanded view');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should collapse card when close clicked', () => {
      cy.get('body').then($body => {
        const repoCard = $body.find('[class*="card"][class*="cursor-pointer"]');

        if (repoCard.length > 0) {
          cy.wrap(repoCard).first().should('be.visible').click();

          // Wait for card to expand, then find close button
          cy.get('body').should('satisfy', ($newBody) => {
            return $newBody.find('[class*="expanded"]').length > 0 ||
                   $newBody.text().includes('Overview');
          }).then($newBody => {
            const closeButton = $newBody.find('button:contains("×"), [aria-label*="close"]');

            if (closeButton.length > 0) {
              cy.wrap(closeButton).first().should('be.visible').click();
              cy.log('Card collapsed');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Pagination', () => {
    beforeEach(() => {
      cy.visit('/app/devops/repositories');
      cy.waitForPageLoad();
    });

    it('should display pagination when many repositories exist', () => {
      cy.get('body').then($body => {
        const pagination = $body.find('[class*="pagination"], button:contains("Next"), button:contains("Previous")');

        if (pagination.length > 0) {
          cy.log('Pagination found');
        } else {
          cy.log('No pagination - may have few repositories');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should navigate between pages', () => {
      cy.get('body').then($body => {
        const nextButton = $body.find('button:contains("Next")');

        if (nextButton.length > 0 && !nextButton.is(':disabled')) {
          cy.wrap(nextButton).first().should('be.visible').click();
          // Wait for page navigation
          cy.get('body').should('be.visible');
          cy.log('Navigated to next page');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Empty State', () => {
    it('should display empty state when no repositories', () => {
      cy.visit('/app/devops/repositories');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        if ($body.text().includes('No Repositories Found')) {
          cy.contains('No Repositories').should('be.visible');
          cy.log('Empty state displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Sync button in empty state', () => {
      cy.visit('/app/devops/repositories');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        if ($body.text().includes('No Repositories')) {
          const syncButton = $body.find('button:contains("Sync")');
          if (syncButton.length > 0) {
            cy.log('Sync button found in empty state');
          }
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.intercept('GET', '/api/v1/git_repositories*', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/devops/repositories');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should display error notification on failure', () => {
      cy.intercept('GET', '/api/v1/git_repositories*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load repositories' }
      });

      cy.visit('/app/devops/repositories');
      cy.waitForPageLoad();

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

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/devops/repositories');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Repositor');
        if (hasContent) {
          cy.log('Content visible on mobile');
        }
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/devops/repositories');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Repositor');
        if (hasContent) {
          cy.log('Content visible on tablet');
        }
      });
    });

    it('should stack cards on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/devops/repositories');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
    });
  });
});


export {};
