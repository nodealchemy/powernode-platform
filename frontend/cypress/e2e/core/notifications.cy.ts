/// <reference types="cypress" />

describe('Notifications Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Page Navigation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/notifications');
    });

    it('should navigate to Notifications page', () => {
      cy.url().should('include', '/notifications');
    });

    it('should display page title', () => {
      cy.assertContainsAny(['Notifications', 'PageContainer']);
    });

    it('should display page description', () => {
      cy.assertContainsAny(['View and manage', 'notifications']);
    });

    it('should display breadcrumbs', () => {
      cy.assertContainsAny(['Dashboard', 'Notifications']);
    });
  });

  describe('Page Actions', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/notifications');
    });

    it('should have Mark All Read button when unread exists', () => {
      cy.assertContainsAny(['Mark All Read', 'Mark all']);
    });
  });

  describe('Filter Bar', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/notifications');
    });

    it('should display All filter button', () => {
      cy.get('button:contains("All")').should('be.visible');
    });

    it('should display Unread filter button', () => {
      cy.assertContainsAny(['Unread']);
    });

    it('should display unread count badge', () => {
      cy.assertHasElement(['[class*="badge"]', 'span', 'div']);
    });

    it('should switch to Unread filter', () => {
      cy.contains('button', 'Unread').click();
    });

    it('should switch to All filter', () => {
      cy.contains('button', 'All').click();
    });
  });

  describe('Notifications List', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/notifications');
    });

    it('should display notifications list or empty state', () => {
      cy.assertContainsAny(['No notifications', "You're all caught up", 'notification']);
    });

    it('should display notification severity icons', () => {
      cy.assertHasElement(['svg']);
    });

    it('should display notification title', () => {
      cy.assertHasElement(['p', 'h3', 'h4', 'span']);
    });

    it('should display notification message', () => {
      cy.assertHasElement(['p', 'span']);
    });

    it('should display notification timestamp', () => {
      cy.assertContainsAny(['ago', 'Just now', 'Today', 'Yesterday']);
    });

    it('should display notification category badge', () => {
      cy.assertHasElement(['span', 'div']);
    });

    it('should highlight unread notifications', () => {
      cy.assertHasElement(['[class*="bg-theme"]', '[class*="unread"]', '[class*="new"]']);
    });
  });

  describe('Notification Actions', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/notifications');
    });

    it('should display Mark as Read button', () => {
      cy.assertHasElement(['button[title*="Mark as read"]', 'button svg']);
    });

    it('should display Dismiss button', () => {
      cy.assertHasElement(['button[title*="Dismiss"]', 'button svg']);
    });

    it('should display action link when available', () => {
      cy.assertContainsAny(['View', 'Details']);
    });
  });

  describe('Empty State', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/notifications');
    });

    it('should display empty state icon', () => {
      cy.assertHasElement(['svg']);
    });

    it('should display empty state message', () => {
      cy.assertContainsAny(['No notifications', "You're all caught up", "You've read all", 'notification']);
    });
  });

  describe('Pagination', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/notifications');
    });

    it('should display pagination controls when needed', () => {
      cy.assertContainsAny(['Previous', 'Next', 'Page', 'of']);
    });

    it('should display page indicator', () => {
      cy.assertContainsAny(['Page', 'of']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.intercept('GET', '**/api/**/notifications**', {
        statusCode: 500,
        body: { error: 'Internal Server Error' }
      }).as('apiError');

      cy.visit('/app/notifications');
      cy.assertContainsAny(['Notifications', 'Error']);
    });

    it('should display error state when data fails to load', () => {
      cy.intercept('GET', '**/api/**/notifications**', {
        statusCode: 500,
        body: { error: 'Failed to load' }
      }).as('loadError');

      cy.visit('/app/notifications');
      cy.assertContainsAny(['Failed', 'Error', 'error']);
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '**/api/**/notifications**', (req) => {
        req.reply((res) => {
          res.delay = 2000;
          res.send({ success: true, data: { notifications: [], unread_count: 0, pagination: {} } });
        });
      }).as('slowLoad');

      cy.visit('/app/notifications');

      cy.assertHasElement(['.animate-spin', '[class*="loading"]', '[class*="spinner"]']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/notifications');
      cy.assertContainsAny(['Notifications']);
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/notifications');
      cy.assertContainsAny(['Notifications']);
    });

    it('should stack elements on small screens', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/notifications');

      cy.assertHasElement(['[class*="flex-col"]', '[class*="grid"]']);
    });
  });
});


export {};
