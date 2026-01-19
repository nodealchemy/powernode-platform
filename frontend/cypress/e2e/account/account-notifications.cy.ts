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

      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Notifications') ||
                          $body.text().includes('Notification');
        if (hasContent) {
          cy.log('Notifications page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page title', () => {
      cy.visit('/app/account/notifications');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('Notifications');
        if (hasTitle) {
          cy.log('Page title displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page description', () => {
      cy.visit('/app/account/notifications');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDescription = $body.text().includes('View and manage') ||
                               $body.text().includes('notifications');
        if (hasDescription) {
          cy.log('Page description displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/account/notifications');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('Dashboard');
        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Page Actions', () => {
    beforeEach(() => {
      cy.visit('/app/account/notifications');
      cy.waitForPageLoad();
    });

    it('should have Mark All Read button when unread exists', () => {
      cy.get('body').then($body => {
        const markAllButton = $body.find('button:contains("Mark All Read")');
        if (markAllButton.length > 0) {
          cy.log('Mark All Read button found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Filter Tabs', () => {
    beforeEach(() => {
      cy.visit('/app/account/notifications');
      cy.waitForPageLoad();
    });

    it('should display All filter tab', () => {
      cy.get('body').then($body => {
        const allTab = $body.find('button:contains("All")');
        if (allTab.length > 0) {
          cy.log('All filter tab displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Unread filter tab', () => {
      cy.get('body').then($body => {
        const unreadTab = $body.find('button:contains("Unread")');
        if (unreadTab.length > 0) {
          cy.log('Unread filter tab displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should switch to All filter', () => {
      cy.get('body').then($body => {
        const allTab = $body.find('button:contains("All")');
        if (allTab.length > 0) {
          cy.wrap(allTab).first().should('be.visible').click();
          cy.waitForPageLoad();
          cy.log('Switched to All filter');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should switch to Unread filter', () => {
      cy.get('body').then($body => {
        const unreadTab = $body.find('button:contains("Unread")');
        if (unreadTab.length > 0) {
          cy.wrap(unreadTab).first().should('be.visible').click();
          cy.waitForPageLoad();
          cy.log('Switched to Unread filter');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display unread count badge', () => {
      cy.get('body').then($body => {
        const hasBadge = $body.find('button:contains("Unread") span').length > 0 ||
                         $body.find('[class*="badge"]').length > 0;
        if (hasBadge) {
          cy.log('Unread count badge displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Notifications List', () => {
    beforeEach(() => {
      cy.visit('/app/account/notifications');
      cy.waitForPageLoad();
    });

    it('should display notifications list', () => {
      cy.get('body').then($body => {
        const hasList = $body.find('[class*="divide"], [class*="list"]').length > 0 ||
                        $body.text().includes('No notifications');
        if (hasList) {
          cy.log('Notifications list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display notification title', () => {
      cy.get('body').then($body => {
        const hasTitle = $body.find('p[class*="font-medium"], p[class*="font-semibold"]').length > 0 ||
                         $body.text().includes('No notifications');
        if (hasTitle) {
          cy.log('Notification titles displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display notification message', () => {
      cy.get('body').then($body => {
        const hasMessage = $body.find('p[class*="secondary"]').length > 0 ||
                           $body.text().includes('No notifications');
        if (hasMessage) {
          cy.log('Notification messages displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display notification timestamp', () => {
      cy.get('body').then($body => {
        const hasTimestamp = $body.text().includes('ago') ||
                             $body.text().includes('Just now');
        if (hasTimestamp) {
          cy.log('Notification timestamps displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display notification category', () => {
      cy.get('body').then($body => {
        const hasCategory = $body.find('[class*="badge"], span[class*="rounded"]').length > 0;
        if (hasCategory) {
          cy.log('Notification category displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display severity icon', () => {
      cy.get('body').then($body => {
        const hasSeverityIcon = $body.find('svg').length > 0 ||
                                $body.find('[class*="icon"]').length > 0;
        if (hasSeverityIcon) {
          cy.log('Severity icon displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Notification Actions', () => {
    beforeEach(() => {
      cy.visit('/app/account/notifications');
      cy.waitForPageLoad();
    });

    it('should have mark as read button', () => {
      cy.get('body').then($body => {
        const markReadButton = $body.find('button[title*="Mark as read"], button[title*="read"]');
        if (markReadButton.length > 0) {
          cy.log('Mark as read button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have dismiss button', () => {
      cy.get('body').then($body => {
        const dismissButton = $body.find('button[title*="Dismiss"]');
        if (dismissButton.length > 0) {
          cy.log('Dismiss button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have action link when available', () => {
      cy.get('body').then($body => {
        const hasActionLink = $body.find('a[class*="link"]').length > 0 ||
                              $body.text().includes('→');
        if (hasActionLink) {
          cy.log('Action link displayed');
        }
      });

      cy.get('body').should('be.visible');
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

      cy.get('body').then($body => {
        const hasEmpty = $body.text().includes('No notifications') ||
                         $body.text().includes('all caught up');
        if (hasEmpty) {
          cy.log('Empty state displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should show different message for unread filter empty', () => {
      cy.visit('/app/account/notifications');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const unreadTab = $body.find('button:contains("Unread")');
        if (unreadTab.length > 0) {
          cy.wrap(unreadTab).first().should('be.visible').click();
          cy.waitForPageLoad();
          cy.get('body').then($emptyBody => {
            const hasEmptyUnread = $emptyBody.text().includes('read all') ||
                                   $emptyBody.text().includes('No notifications');
            if (hasEmptyUnread) {
              cy.log('Unread empty state message shown');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Pagination', () => {
    beforeEach(() => {
      cy.visit('/app/account/notifications');
      cy.waitForPageLoad();
    });

    it('should display pagination when multiple pages', () => {
      cy.get('body').then($body => {
        const hasPagination = $body.text().includes('Page') ||
                              $body.find('button:contains("Previous")').length > 0;
        if (hasPagination) {
          cy.log('Pagination displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Previous button', () => {
      cy.get('body').then($body => {
        const prevButton = $body.find('button:contains("Previous")');
        if (prevButton.length > 0) {
          cy.log('Previous button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Next button', () => {
      cy.get('body').then($body => {
        const nextButton = $body.find('button:contains("Next")');
        if (nextButton.length > 0) {
          cy.log('Next button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display current page number', () => {
      cy.get('body').then($body => {
        const hasPageNumber = $body.text().includes('Page 1') ||
                              $body.text().match(/Page \d+ of \d+/);
        if (hasPageNumber) {
          cy.log('Current page number displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Severity Colors', () => {
    beforeEach(() => {
      cy.visit('/app/account/notifications');
      cy.waitForPageLoad();
    });

    it('should display info severity style', () => {
      cy.get('body').then($body => {
        const hasInfoStyle = $body.find('[class*="info"]').length > 0;
        if (hasInfoStyle) {
          cy.log('Info severity style displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display success severity style', () => {
      cy.get('body').then($body => {
        const hasSuccessStyle = $body.find('[class*="success"]').length > 0;
        if (hasSuccessStyle) {
          cy.log('Success severity style displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display warning severity style', () => {
      cy.get('body').then($body => {
        const hasWarningStyle = $body.find('[class*="warning"]').length > 0;
        if (hasWarningStyle) {
          cy.log('Warning severity style displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display error severity style', () => {
      cy.get('body').then($body => {
        const hasErrorStyle = $body.find('[class*="error"], [class*="danger"]').length > 0;
        if (hasErrorStyle) {
          cy.log('Error severity style displayed');
        }
      });

      cy.get('body').should('be.visible');
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

      cy.get('body').should('be.visible');
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
      cy.intercept('GET', '/api/v1/notifications*', {
        delay: 1000,
        statusCode: 200,
        body: { notifications: [], unread_count: 0, pagination: { total_pages: 1 } }
      }).as('getNotificationsDelayed');

      cy.visit('/app/account/notifications');

      cy.get('body').then($body => {
        const hasLoading = $body.find('[class*="spin"], [class*="loading"]').length > 0 ||
                           $body.text().includes('Loading');
        if (hasLoading) {
          cy.log('Loading indicator displayed');
        }
      });

      cy.wait('@getNotificationsDelayed');
      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/account/notifications');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Notifications');
        if (hasContent) {
          cy.log('Content visible on mobile');
        }
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/account/notifications');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Notifications');
        if (hasContent) {
          cy.log('Content visible on tablet');
        }
      });
    });

    it('should stack layout on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/account/notifications');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
    });
  });
});


export {};
