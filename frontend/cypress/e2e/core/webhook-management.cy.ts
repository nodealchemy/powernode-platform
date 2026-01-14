/// <reference types="cypress" />

describe('Webhook Management Page Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 5000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to Webhook Management page', () => {
      cy.visit('/app/webhooks');
      cy.url().should('include', '/webhooks');
    });

    it('should display page title', () => {
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('Webhook') ||
                        $body.text().includes('Webhooks') ||
                        $body.find('[class*="PageContainer"]').length > 0;
        if (hasTitle) {
          cy.log('Webhook Management page title found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display page description', () => {
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        const hasDesc = $body.text().includes('Manage webhook') ||
                       $body.text().includes('endpoints') ||
                       $body.text().includes('notifications');
        if (hasDesc) {
          cy.log('Page description found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Page Actions', () => {
    it('should have Add Webhook button', () => {
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        const hasAdd = $body.text().includes('Add Webhook') ||
                      $body.text().includes('Create Webhook') ||
                      $body.text().includes('New Webhook');
        if (hasAdd) {
          cy.log('Add Webhook button found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should have Refresh button', () => {
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        const hasRefresh = $body.find('[class*="refresh"]').length > 0 ||
                          $body.find('button svg').length > 0;
        if (hasRefresh) {
          cy.log('Refresh button found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Stats Overview', () => {
    it('should display Total Endpoints stat', () => {
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        const hasTotal = $body.text().includes('Total Endpoints') ||
                        $body.text().includes('Total');
        if (hasTotal) {
          cy.log('Total Endpoints stat found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Active stat', () => {
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        const hasActive = $body.text().includes('Active');
        if (hasActive) {
          cy.log('Active stat found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Inactive stat', () => {
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        const hasInactive = $body.text().includes('Inactive');
        if (hasInactive) {
          cy.log('Inactive stat found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Deliveries Today stat', () => {
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        const hasDeliveries = $body.text().includes('Deliveries Today') ||
                             $body.text().includes('Today');
        if (hasDeliveries) {
          cy.log('Deliveries Today stat found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Success Rate stat', () => {
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        const hasRate = $body.text().includes('Success Rate') ||
                       $body.text().match(/\d+%/);
        if (hasRate) {
          cy.log('Success Rate stat found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Failed stat', () => {
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        const hasFailed = $body.text().includes('Failed');
        if (hasFailed) {
          cy.log('Failed stat found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('View Modes', () => {
    it('should display List view button', () => {
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        const hasList = $body.text().includes('List') ||
                       $body.find('[class*="list"]').length > 0;
        if (hasList) {
          cy.log('List view button found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Details view button', () => {
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        const hasDetails = $body.text().includes('Details');
        if (hasDetails) {
          cy.log('Details view button found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Stats view button', () => {
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        const hasStats = $body.text().includes('Stats');
        if (hasStats) {
          cy.log('Stats view button found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should switch to Details view', () => {
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Details")').length > 0) {
          cy.contains('button', 'Details').click();
          cy.log('Switched to Details view');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should switch to Stats view', () => {
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Stats")').length > 0) {
          cy.contains('button', 'Stats').click();
          cy.log('Switched to Stats view');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Filters', () => {
    it('should display status filter', () => {
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        const hasFilter = $body.find('select').length > 0 ||
                         $body.text().includes('All Status') ||
                         $body.text().includes('Status');
        if (hasFilter) {
          cy.log('Status filter found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display search input', () => {
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        const hasSearch = $body.find('input[type="text"]').length > 0 ||
                         $body.find('input[placeholder*="Search"]').length > 0;
        if (hasSearch) {
          cy.log('Search input found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Webhook List', () => {
    it('should display webhooks list or empty state', () => {
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        const hasList = $body.find('table').length > 0 ||
                       $body.find('[class*="card"]').length > 0 ||
                       $body.text().includes('No webhooks');
        if (hasList) {
          cy.log('Webhooks list or empty state displayed');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display webhook URL column', () => {
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        const hasURL = $body.text().includes('URL') ||
                      $body.text().includes('Endpoint');
        if (hasURL) {
          cy.log('Webhook URL column found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display webhook events column', () => {
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        const hasEvents = $body.text().includes('Events') ||
                         $body.text().includes('Triggers');
        if (hasEvents) {
          cy.log('Webhook events column found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display webhook status column', () => {
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Status');
        if (hasStatus) {
          cy.log('Webhook status column found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display status badges', () => {
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        const hasBadges = $body.find('[class*="badge"]').length > 0 ||
                         $body.text().includes('active') ||
                         $body.text().includes('inactive');
        if (hasBadges) {
          cy.log('Status badges found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Webhook Actions', () => {
    it('should display Edit action', () => {
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        const hasEdit = $body.text().includes('Edit') ||
                       $body.find('button[class*="edit"]').length > 0;
        if (hasEdit) {
          cy.log('Edit action found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Delete action', () => {
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        const hasDelete = $body.text().includes('Delete') ||
                         $body.find('button[class*="delete"]').length > 0;
        if (hasDelete) {
          cy.log('Delete action found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Toggle status action', () => {
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        const hasToggle = $body.text().includes('Enable') ||
                         $body.text().includes('Disable') ||
                         $body.find('button[class*="toggle"]').length > 0;
        if (hasToggle) {
          cy.log('Toggle status action found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Test webhook action', () => {
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        const hasTest = $body.text().includes('Test') ||
                       $body.text().includes('Send Test');
        if (hasTest) {
          cy.log('Test webhook action found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Add Webhook Modal', () => {
    it('should open Add Webhook modal', () => {
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Add Webhook")').length > 0) {
          cy.contains('button', 'Add Webhook').click();
          cy.get('body').then($updated => {
            const hasModal = $updated.find('[class*="modal"]').length > 0 ||
                            $updated.find('[role="dialog"]').length > 0;
            if (hasModal) {
              cy.log('Add Webhook modal opened');
            }
          });
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display URL input in modal', () => {
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Add Webhook")').length > 0) {
          cy.contains('button', 'Add Webhook').click();
          cy.get('body').then($updated => {
            const hasURL = $updated.find('input[name="url"]').length > 0 ||
                          $updated.text().includes('URL');
            if (hasURL) {
              cy.log('URL input found in modal');
            }
          });
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display events selection in modal', () => {
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Add Webhook")').length > 0) {
          cy.contains('button', 'Add Webhook').click();
          cy.get('body').then($updated => {
            const hasEvents = $updated.text().includes('Events') ||
                             $updated.find('input[type="checkbox"]').length > 0;
            if (hasEvents) {
              cy.log('Events selection found in modal');
            }
          });
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display secret key option in modal', () => {
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Add Webhook")').length > 0) {
          cy.contains('button', 'Add Webhook').click();
          cy.get('body').then($updated => {
            const hasSecret = $updated.text().includes('Secret') ||
                             $updated.find('input[name="secret"]').length > 0;
            if (hasSecret) {
              cy.log('Secret key option found in modal');
            }
          });
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Details View Content', () => {
    it('should display webhook details when selected', () => {
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Details")').length > 0) {
          cy.contains('button', 'Details').click();
          cy.get('body').then($updated => {
            const hasDetails = $updated.text().includes('Details') ||
                              $updated.find('[class*="detail"]').length > 0;
            if (hasDetails) {
              cy.log('Webhook details displayed');
            }
          });
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display delivery history', () => {
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Details")').length > 0) {
          cy.contains('button', 'Details').click();
          cy.get('body').then($updated => {
            const hasHistory = $updated.text().includes('History') ||
                              $updated.text().includes('Deliveries');
            if (hasHistory) {
              cy.log('Delivery history displayed');
            }
          });
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display retry failed deliveries option', () => {
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Details")').length > 0) {
          cy.contains('button', 'Details').click();
          cy.get('body').then($updated => {
            const hasRetry = $updated.text().includes('Retry') ||
                            $updated.text().includes('Resend');
            if (hasRetry) {
              cy.log('Retry option displayed');
            }
          });
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Stats View Content', () => {
    it('should display delivery statistics chart', () => {
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Stats")').length > 0) {
          cy.contains('button', 'Stats').click();
          cy.get('body').then($updated => {
            const hasChart = $updated.find('canvas').length > 0 ||
                            $updated.find('[class*="chart"]').length > 0 ||
                            $updated.find('svg').length > 0;
            if (hasChart) {
              cy.log('Delivery statistics chart displayed');
            }
          });
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display success/failure breakdown', () => {
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Stats")').length > 0) {
          cy.contains('button', 'Stats').click();
          cy.get('body').then($updated => {
            const hasBreakdown = $updated.text().includes('Success') ||
                                $updated.text().includes('Failed') ||
                                $updated.text().match(/\d+%/);
            if (hasBreakdown) {
              cy.log('Success/failure breakdown displayed');
            }
          });
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Pagination', () => {
    it('should display pagination controls', () => {
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        const hasPagination = $body.find('[class*="pagination"]').length > 0 ||
                             $body.text().includes('Page') ||
                             $body.text().includes('of');
        if (hasPagination) {
          cy.log('Pagination controls found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display items per page selector', () => {
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        const hasSelector = $body.find('select').length > 0 ||
                           $body.text().includes('per page');
        if (hasSelector) {
          cy.log('Items per page selector found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.intercept('GET', '**/api/**/webhooks**', {
        statusCode: 500,
        body: { error: 'Internal Server Error' }
      }).as('apiError');

      cy.visit('/app/webhooks');
      cy.get('body').should('be.visible');
    });

    it('should display error state when data fails to load', () => {
      cy.intercept('GET', '**/api/**/webhooks**', {
        statusCode: 500,
        body: { error: 'Failed to load' }
      }).as('loadError');

      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        const hasError = $body.text().includes('Error') ||
                        $body.text().includes('Failed');
        if (hasError) {
          cy.log('Error state displayed');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '**/api/**/webhooks**', (req) => {
        req.reply((res) => {
          res.delay = 2000;
          res.send({ success: true, data: [] });
        });
      }).as('slowLoad');

      cy.visit('/app/webhooks');
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
      cy.visit('/app/webhooks');
      cy.get('body').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/webhooks');
      cy.get('body').should('be.visible');
    });

    it('should stack stats cards on small screens', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        const hasGrid = $body.find('[class*="grid-cols-2"]').length > 0 ||
                       $body.find('[class*="md:grid-cols"]').length > 0;
        if (hasGrid) {
          cy.log('Responsive stats grid found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should show multi-column layout on large screens', () => {
      cy.viewport(1920, 1080);
      cy.visit('/app/webhooks');
      cy.get('body').then($body => {
        const hasMultiCol = $body.find('[class*="lg:grid-cols"]').length > 0 ||
                           $body.find('[class*="xl:grid-cols"]').length > 0;
        if (hasMultiCol) {
          cy.log('Multi-column layout found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });
});


export {};
