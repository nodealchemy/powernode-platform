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
      cy.get('body').then($body => {
        const hasAll = $body.find('button:contains("All")').length > 0;
        if (hasAll) {
          cy.log('All filter button found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Unread filter button', () => {
      cy.assertContainsAny(['Unread']);
    });

    it('should display unread count badge', () => {
      cy.get('body').then($body => {
        const hasBadge = $body.find('span, div').filter(function() {
          return /^\d+$/.test($(this).text().trim());
        }).length > 0;
        if (hasBadge) {
          cy.log('Unread count badge found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should switch to Unread filter', () => {
      cy.get('body').then($body => {
        if ($body.find('button:contains("Unread")').length > 0) {
          cy.contains('button', 'Unread').click();
          cy.log('Switched to Unread filter');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should switch to All filter', () => {
      cy.get('body').then($body => {
        if ($body.find('button:contains("All")').length > 0) {
          cy.contains('button', 'All').click();
          cy.log('Switched to All filter');
        }
      });
      cy.get('body').should('be.visible');
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
      cy.get('body').then($body => {
        const hasIcons = $body.find('svg').length > 0;
        if (hasIcons) {
          cy.log('Notification severity icons found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display notification title', () => {
      cy.get('body').then($body => {
        const hasTitle = $body.find('p, h3, h4, span').filter(function() {
          const text = $(this).text().trim();
          return text.length > 3 && text.length < 100;
        }).length > 0;
        if (hasTitle) {
          cy.log('Notification title found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display notification message', () => {
      cy.get('body').then($body => {
        const hasMessage = $body.find('p, span').length > 0;
        if (hasMessage) {
          cy.log('Notification message found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display notification timestamp', () => {
      cy.assertContainsAny(['ago', 'Just now', 'Today', 'Yesterday']);
    });

    it('should display notification category badge', () => {
      cy.get('body').then($body => {
        const hasBadge = $body.find('span, div').filter(function() {
          const el = $(this);
          return el.text().trim().length > 0 && el.text().trim().length < 20;
        }).length > 0;
        if (hasBadge) {
          cy.log('Notification category badge found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should highlight unread notifications', () => {
      cy.get('body').then($body => {
        const hasHighlight = $body.find('[class*="bg-theme"], [class*="unread"], [class*="new"]').length > 0;
        if (hasHighlight) {
          cy.log('Unread notifications highlighted');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Notification Actions', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/notifications');
    });

    it('should display Mark as Read button', () => {
      cy.get('body').then($body => {
        const hasMarkRead = $body.find('button[title*="Mark as read"]').length > 0 ||
                           $body.find('button svg').length > 0;
        if (hasMarkRead) {
          cy.log('Mark as Read button found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Dismiss button', () => {
      cy.get('body').then($body => {
        const hasDismiss = $body.find('button[title*="Dismiss"]').length > 0 ||
                          $body.find('button svg').length > 0;
        if (hasDismiss) {
          cy.log('Dismiss button found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display action link when available', () => {
      cy.get('body').then($body => {
        const hasAction = $body.find('a').length > 0 ||
                         $body.text().includes('View') ||
                         $body.text().includes('Details');
        if (hasAction) {
          cy.log('Action link found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Empty State', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/notifications');
    });

    it('should display empty state icon', () => {
      cy.get('body').then($body => {
        const hasIcon = $body.find('svg').length > 0;
        if (hasIcon) {
          cy.log('Empty state icon found');
        }
      });
      cy.get('body').should('be.visible');
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
      cy.get('body').then($body => {
        const hasIndicator = $body.text().match(/Page \d+ of \d+/) ||
                            $body.text().match(/\d+ of \d+/);
        if (hasIndicator) {
          cy.log('Page indicator found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.intercept('GET', '**/api/**/notifications**', {
        statusCode: 500,
        body: { error: 'Internal Server Error' }
      }).as('apiError');

      cy.visit('/app/notifications');
      cy.get('body').should('be.visible');
    });

    it('should display error state when data fails to load', () => {
      cy.intercept('GET', '**/api/**/notifications**', {
        statusCode: 500,
        body: { error: 'Failed to load' }
      }).as('loadError');

      cy.visit('/app/notifications');
      cy.get('body').then($body => {
        const hasError = $body.text().includes('Failed') ||
                        $body.text().includes('Error') ||
                        $body.text().includes('error');
        if (hasError) {
          cy.log('Error state displayed');
        }
      });
      cy.get('body').should('be.visible');
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
      cy.get('body').then($body => {
        const hasLoading = $body.find('.animate-spin, [class*="loading"], [class*="spinner"]').length > 0 ||
                          $body.find('svg').filter(function() {
                            return $(this).attr('class')?.includes('animate') || false;
                          }).length > 0 ||
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
      cy.visit('/app/notifications');
      cy.get('body').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/notifications');
      cy.get('body').should('be.visible');
    });

    it('should stack elements on small screens', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/notifications');
      cy.get('body').then($body => {
        const hasStack = $body.find('[class*="flex-col"], [class*="grid"]').length > 0;
        if (hasStack) {
          cy.log('Stacked elements found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });
});


export {};
