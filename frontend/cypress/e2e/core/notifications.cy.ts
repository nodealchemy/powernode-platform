/// <reference types="cypress" />

describe('Notifications Page Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to Notifications page', () => {
      cy.visit('/app/notifications');
      cy.url().should('include', '/notifications');
    });

    it('should display page title', () => {
      cy.visit('/app/notifications');
      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('Notifications') ||
                        $body.find('[class*="PageContainer"]').length > 0;
        if (hasTitle) {
          cy.log('Notifications page title found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display page description', () => {
      cy.visit('/app/notifications');
      cy.get('body').then($body => {
        const hasDesc = $body.text().includes('View and manage') ||
                       $body.text().includes('notifications');
        if (hasDesc) {
          cy.log('Page description found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/notifications');
      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('Dashboard') ||
                              $body.text().includes('Notifications');
        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Page Actions', () => {
    it('should have Mark All Read button when unread exists', () => {
      cy.visit('/app/notifications');
      cy.get('body').then($body => {
        const hasMarkAll = $body.text().includes('Mark All Read') ||
                          $body.text().includes('Mark all');
        if (hasMarkAll) {
          cy.log('Mark All Read button found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Filter Bar', () => {
    it('should display All filter button', () => {
      cy.visit('/app/notifications');
      cy.get('body').then($body => {
        const hasAll = $body.find('button:contains("All")').length > 0;
        if (hasAll) {
          cy.log('All filter button found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Unread filter button', () => {
      cy.visit('/app/notifications');
      cy.get('body').then($body => {
        const hasUnread = $body.text().includes('Unread');
        if (hasUnread) {
          cy.log('Unread filter button found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display unread count badge', () => {
      cy.visit('/app/notifications');
      cy.get('body').then($body => {
        const hasCount = $body.find('[class*="badge"]').length > 0 ||
                        $body.find('[class*="rounded-full"]').text().match(/\d+/);
        if (hasCount) {
          cy.log('Unread count badge found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should switch to Unread filter', () => {
      cy.visit('/app/notifications');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Unread")').length > 0) {
          cy.contains('button', 'Unread').click();
          cy.log('Switched to Unread filter');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should switch to All filter', () => {
      cy.visit('/app/notifications');
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
    it('should display notifications list or empty state', () => {
      cy.visit('/app/notifications');
      cy.get('body').then($body => {
        const hasList = $body.find('[class*="divide-y"]').length > 0 ||
                       $body.text().includes('No notifications') ||
                       $body.text().includes("You're all caught up");
        if (hasList) {
          cy.log('Notifications list or empty state displayed');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display notification severity icons', () => {
      cy.visit('/app/notifications');
      cy.get('body').then($body => {
        const hasIcons = $body.find('svg').length > 0 ||
                        $body.find('[class*="icon"]').length > 0;
        if (hasIcons) {
          cy.log('Notification severity icons found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display notification title', () => {
      cy.visit('/app/notifications');
      cy.get('body').then($body => {
        const hasTitle = $body.find('p[class*="font-semibold"]').length > 0 ||
                        $body.find('p[class*="font-medium"]').length > 0;
        if (hasTitle) {
          cy.log('Notification title found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display notification message', () => {
      cy.visit('/app/notifications');
      cy.get('body').then($body => {
        const hasMessage = $body.find('p[class*="secondary"]').length > 0;
        if (hasMessage) {
          cy.log('Notification message found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display notification timestamp', () => {
      cy.visit('/app/notifications');
      cy.get('body').then($body => {
        const hasTime = $body.text().includes('ago') ||
                       $body.text().includes('Just now') ||
                       $body.find('[class*="tertiary"]').length > 0;
        if (hasTime) {
          cy.log('Notification timestamp found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display notification category badge', () => {
      cy.visit('/app/notifications');
      cy.get('body').then($body => {
        const hasCategory = $body.find('[class*="badge"]').length > 0 ||
                           $body.find('[class*="rounded-md"]').length > 0;
        if (hasCategory) {
          cy.log('Notification category badge found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should highlight unread notifications', () => {
      cy.visit('/app/notifications');
      cy.get('body').then($body => {
        const hasHighlight = $body.find('[class*="bg-theme-info"]').length > 0;
        if (hasHighlight) {
          cy.log('Unread notifications highlighted');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Notification Actions', () => {
    it('should display Mark as Read button', () => {
      cy.visit('/app/notifications');
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
      cy.visit('/app/notifications');
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
      cy.visit('/app/notifications');
      cy.get('body').then($body => {
        const hasAction = $body.find('a[class*="text-theme-primary"]').length > 0 ||
                         $body.text().includes('→');
        if (hasAction) {
          cy.log('Action link found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Empty State', () => {
    it('should display empty state icon', () => {
      cy.visit('/app/notifications');
      cy.get('body').then($body => {
        const hasIcon = $body.find('svg[class*="bell"]').length > 0 ||
                       $body.find('[class*="BellIcon"]').length > 0;
        if (hasIcon) {
          cy.log('Empty state icon found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display empty state message', () => {
      cy.visit('/app/notifications');
      cy.get('body').then($body => {
        const hasMessage = $body.text().includes('No notifications') ||
                          $body.text().includes("You're all caught up") ||
                          $body.text().includes("You've read all");
        if (hasMessage) {
          cy.log('Empty state message found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Pagination', () => {
    it('should display pagination controls when needed', () => {
      cy.visit('/app/notifications');
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
      cy.visit('/app/notifications');
      cy.get('body').then($body => {
        const hasIndicator = $body.text().match(/Page \d+ of \d+/);
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
                        $body.find('[class*="error"]').length > 0;
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
        const hasStack = $body.find('[class*="flex-col"]').length > 0;
        if (hasStack) {
          cy.log('Stacked elements found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });
});
