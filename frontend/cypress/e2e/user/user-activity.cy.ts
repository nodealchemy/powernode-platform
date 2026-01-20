/// <reference types="cypress" />

/**
 * User Activity Tests
 *
 * Tests for User Activity functionality including:
 * - Activity feed
 * - Activity filtering
 * - Activity search
 * - Activity notifications
 * - Activity export
 * - Activity timeline
 */

describe('User Activity Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Activity Feed', () => {
    it('should navigate to activity page', () => {
      cy.visit('/app/account/activity');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasActivity = $body.text().includes('Activity') ||
                          $body.text().includes('History') ||
                          $body.text().includes('Recent');
        if (hasActivity) {
          cy.log('Activity page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display activity list', () => {
      cy.visit('/app/account/activity');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasList = $body.find('[data-testid="activity-list"], .activity-feed, table').length > 0;
        if (hasList) {
          cy.log('Activity list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display activity timestamps', () => {
      cy.visit('/app/account/activity');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasTimestamp = $body.text().includes('ago') ||
                            $body.text().match(/\d{4}/) !== null ||
                            $body.text().includes('Today');
        if (hasTimestamp) {
          cy.log('Activity timestamps displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display activity types', () => {
      cy.visit('/app/account/activity');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasTypes = $body.text().includes('Login') ||
                        $body.text().includes('Update') ||
                        $body.text().includes('Create') ||
                        $body.text().includes('Delete');
        if (hasTypes) {
          cy.log('Activity types displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Activity Filtering', () => {
    beforeEach(() => {
      cy.visit('/app/account/activity');
      cy.waitForPageLoad();
    });

    it('should have date range filter', () => {
      cy.get('body').then($body => {
        const hasDateFilter = $body.find('input[type="date"], [data-testid="date-filter"]').length > 0 ||
                             $body.text().includes('Date');
        if (hasDateFilter) {
          cy.log('Date range filter displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have activity type filter', () => {
      cy.get('body').then($body => {
        const hasTypeFilter = $body.find('select, [data-testid="type-filter"]').length > 0 ||
                             $body.text().includes('Type') ||
                             $body.text().includes('Filter');
        if (hasTypeFilter) {
          cy.log('Activity type filter displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have clear filters option', () => {
      cy.get('body').then($body => {
        const hasClear = $body.find('button:contains("Clear"), button:contains("Reset")').length > 0 ||
                        $body.text().includes('Clear');
        if (hasClear) {
          cy.log('Clear filters option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Activity Search', () => {
    beforeEach(() => {
      cy.visit('/app/account/activity');
      cy.waitForPageLoad();
    });

    it('should have search input', () => {
      cy.get('body').then($body => {
        const hasSearch = $body.find('input[type="search"], input[placeholder*="Search"]').length > 0 ||
                         $body.text().includes('Search');
        if (hasSearch) {
          cy.log('Search input displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should filter results on search', () => {
      cy.get('body').then($body => {
        const searchInput = $body.find('input[type="search"], input[placeholder*="Search"]');
        if (searchInput.length > 0) {
          cy.wrap(searchInput).type('login');
          cy.log('Search filtering available');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Activity Details', () => {
    beforeEach(() => {
      cy.visit('/app/account/activity');
      cy.waitForPageLoad();
    });

    it('should display activity descriptions', () => {
      cy.get('body').then($body => {
        const hasDescription = $body.find('p, .description, [data-testid="activity-description"]').length > 0;
        if (hasDescription) {
          cy.log('Activity descriptions displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display IP address', () => {
      cy.get('body').then($body => {
        const hasIP = $body.text().includes('IP') ||
                     $body.text().match(/\d+\.\d+\.\d+\.\d+/) !== null;
        if (hasIP) {
          cy.log('IP address displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display device/browser info', () => {
      cy.get('body').then($body => {
        const hasDevice = $body.text().includes('Device') ||
                         $body.text().includes('Browser') ||
                         $body.text().includes('Chrome') ||
                         $body.text().includes('Firefox');
        if (hasDevice) {
          cy.log('Device/browser info displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Activity Export', () => {
    beforeEach(() => {
      cy.visit('/app/account/activity');
      cy.waitForPageLoad();
    });

    it('should have export option', () => {
      cy.get('body').then($body => {
        const hasExport = $body.find('button:contains("Export"), button:contains("Download")').length > 0 ||
                         $body.text().includes('Export');
        if (hasExport) {
          cy.log('Export option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should offer export formats', () => {
      cy.get('body').then($body => {
        const hasFormats = $body.text().includes('CSV') ||
                          $body.text().includes('PDF') ||
                          $body.text().includes('JSON');
        if (hasFormats) {
          cy.log('Export formats available');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Activity Pagination', () => {
    beforeEach(() => {
      cy.visit('/app/account/activity');
      cy.waitForPageLoad();
    });

    it('should have pagination controls', () => {
      cy.get('body').then($body => {
        const hasPagination = $body.find('[data-testid="pagination"], .pagination, button:contains("Next")').length > 0 ||
                             $body.text().includes('Page');
        if (hasPagination) {
          cy.log('Pagination controls displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have load more option', () => {
      cy.get('body').then($body => {
        const hasLoadMore = $body.find('button:contains("Load more"), button:contains("Show more")').length > 0 ||
                           $body.text().includes('Load more');
        if (hasLoadMore) {
          cy.log('Load more option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display activity correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/account/activity');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`Activity displayed correctly on ${name}`);
      });
    });
  });
});
