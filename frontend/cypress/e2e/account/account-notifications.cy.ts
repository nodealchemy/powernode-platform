/// <reference types="cypress" />

/**
 * Account Notifications Page Tests
 *
 * Tests for Notifications functionality including:
 * - Page navigation and load
 * - Notification list display
 * - Filter tabs (All/Unread)
 * - Mark as read action
 * - Dismiss action
 * - Mark all read action
 * - Pagination
 * - Empty state handling
 * - Error handling
 * - Responsive design
 */

describe('Account Notifications Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Page Navigation', () => {
    it('should navigate to Notifications page', () => {
      cy.visit('/app/account/notifications');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Notifications', 'Notification']);
    });

    it('should display page title', () => {
      cy.visit('/app/account/notifications');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Notifications']);
    });

    it('should display page description', () => {
      cy.visit('/app/account/notifications');
      cy.waitForPageLoad();
      cy.assertContainsAny(['View and manage', 'notifications']);
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/account/notifications');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Dashboard']);
    });
  });

  describe('Page Actions', () => {
    beforeEach(() => {
      cy.visit('/app/account/notifications');
      cy.waitForPageLoad();
    });

    it('should have Mark All Read button when unread exists', () => {
      cy.get('button').contains(/Mark All Read/i).should('exist');
    });
  });

  describe('Filter Tabs', () => {
    beforeEach(() => {
      cy.visit('/app/account/notifications');
      cy.waitForPageLoad();
    });

    it('should display All filter tab', () => {
      cy.get('button').contains(/^All$/i).should('exist');
    });

    it('should display Unread filter tab', () => {
      cy.get('button').contains(/^Unread$/i).should('exist');
    });

    it('should switch to All filter', () => {
      cy.get('button').contains(/^All$/i).first().click();
      cy.waitForPageLoad();
      cy.assertContainsAny(['Notifications', 'All']);
    });

    it('should switch to Unread filter', () => {
      cy.get('button').contains(/^Unread$/i).first().click();
      cy.waitForPageLoad();
      cy.assertContainsAny(['Notifications', 'Unread']);
    });

    it('should display unread count badge', () => {
      cy.assertHasElement(['button:contains("Unread") span', '[class*="badge"]']);
    });
  });

  describe('Notifications List', () => {
    beforeEach(() => {
      cy.visit('/app/account/notifications');
      cy.waitForPageLoad();
    });

    it('should display notifications list', () => {
      cy.assertHasElement(['[class*="divide"]', '[class*="list"]']);
    });

    it('should display notification title', () => {
      cy.assertHasElement(['p[class*="font-medium"]', 'p[class*="font-semibold"]']);
    });

    it('should display notification message', () => {
      cy.get('p[class*="secondary"]').should('exist');
    });

    it('should display notification timestamp', () => {
      cy.assertContainsAny(['ago', 'Just now']);
    });

    it('should display notification category', () => {
      cy.assertHasElement(['[class*="badge"]', 'span[class*="rounded"]']);
    });

    it('should display severity icon', () => {
      cy.assertHasElement(['svg', '[class*="icon"]']);
    });
  });

  describe('Notification Actions', () => {
    beforeEach(() => {
      cy.visit('/app/account/notifications');
      cy.waitForPageLoad();
    });

    it('should have mark as read button', () => {
      cy.assertHasElement(['button[title*="Mark as read"]', 'button[title*="read"]']);
    });

    it('should have dismiss button', () => {
      cy.get('button[title*="Dismiss"]').should('exist');
    });

    it('should have action link when available', () => {
      cy.get('a[class*="link"]').should('exist');
    });
  });

  describe('Empty State', () => {
    it('should display empty state when no notifications', () => {
      cy.intercept('GET', '/api/v1/notifications*', {
        statusCode: 200,
        body: { notifications: [], unread_count: 0, pagination: { total_pages: 1 } }
      }).as('getEmptyNotifications');

      cy.visit('/app/account/notifications');
      cy.wait('@getEmptyNotifications');
      cy.waitForPageLoad();
      cy.assertContainsAny(['No notifications', 'all caught up']);
    });

    it('should show different message for unread filter empty', () => {
      cy.visit('/app/account/notifications');
      cy.waitForPageLoad();
      cy.get('button').contains(/^Unread$/i).first().click();
      cy.waitForPageLoad();
      cy.assertContainsAny(['read all', 'No notifications']);
    });
  });

  describe('Pagination', () => {
    beforeEach(() => {
      cy.visit('/app/account/notifications');
      cy.waitForPageLoad();
    });

    it('should display pagination when multiple pages', () => {
      cy.assertContainsAny(['Page', 'Previous']);
    });

    it('should have Previous button', () => {
      cy.get('button').contains(/Previous/i).should('exist');
    });

    it('should have Next button', () => {
      cy.get('button').contains(/Next/i).should('exist');
    });

    it('should display current page number', () => {
      cy.assertContainsAny(['Page 1', 'Page']);
    });
  });

  describe('Severity Colors', () => {
    beforeEach(() => {
      cy.visit('/app/account/notifications');
      cy.waitForPageLoad();
    });

    it('should display info severity style', () => {
      cy.get('[class*="info"]').should('exist');
    });

    it('should display success severity style', () => {
      cy.get('[class*="success"]').should('exist');
    });

    it('should display warning severity style', () => {
      cy.get('[class*="warning"]').should('exist');
    });

    it('should display error severity style', () => {
      cy.assertHasElement(['[class*="error"]', '[class*="danger"]']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.intercept('GET', '/api/v1/notifications*', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      }).as('getNotificationsError');

      cy.visit('/app/account/notifications');
      cy.wait('@getNotificationsError');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Notifications', 'Error']);
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should display error notification on failure', () => {
      cy.intercept('GET', '/api/v1/notifications*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load notifications' }
      }).as('getNotificationsFailed');

      cy.visit('/app/account/notifications');
      cy.wait('@getNotificationsFailed');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Error', 'Failed']);
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '/api/v1/notifications*', {
        delay: 1000,
        statusCode: 200,
        body: { notifications: [], unread_count: 0, pagination: { total_pages: 1 } }
      }).as('getNotificationsDelayed');

      cy.visit('/app/account/notifications');
      cy.assertHasElement(['[class*="spin"]', '[class*="loading"]']);
      cy.wait('@getNotificationsDelayed');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/account/notifications');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Notifications']);
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/account/notifications');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Notifications']);
    });

    it('should stack layout on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/account/notifications');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Notifications']);
    });
  });
});


export {};
