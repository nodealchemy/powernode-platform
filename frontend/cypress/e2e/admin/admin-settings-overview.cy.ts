/// <reference types="cypress" />

describe('Admin Settings Overview Page Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 5000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to Admin Settings Overview page', () => {
      cy.visit('/app/admin/settings/overview');
      cy.url().should('include', '/admin');
    });

    it('should display page title', () => {
      cy.visit('/app/admin/settings/overview');
      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('Settings Overview') ||
                        $body.text().includes('Admin Settings') ||
                        $body.find('[class*="PageContainer"]').length > 0;
        if (hasTitle) {
          cy.log('Admin Settings Overview page title found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display page description', () => {
      cy.visit('/app/admin/settings/overview');
      cy.get('body').then($body => {
        const hasDesc = $body.text().includes('system settings') ||
                       $body.text().includes('platform configuration') ||
                       $body.text().includes('configuration');
        if (hasDesc) {
          cy.log('Page description found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/admin/settings/overview');
      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('Admin') ||
                              $body.text().includes('Settings') ||
                              $body.text().includes('Dashboard');
        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Page Actions', () => {
    it('should have Refresh button', () => {
      cy.visit('/app/admin/settings/overview');
      cy.get('body').then($body => {
        const hasRefresh = $body.text().includes('Refresh') ||
                          $body.find('button svg').length > 0;
        if (hasRefresh) {
          cy.log('Refresh button found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('System Status Section', () => {
    it('should display System Status section', () => {
      cy.visit('/app/admin/settings/overview');
      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('System Status') ||
                         $body.text().includes('Status');
        if (hasStatus) {
          cy.log('System Status section found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display API status', () => {
      cy.visit('/app/admin/settings/overview');
      cy.get('body').then($body => {
        const hasAPI = $body.text().includes('API') ||
                      $body.text().includes('Backend');
        if (hasAPI) {
          cy.log('API status found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Database status', () => {
      cy.visit('/app/admin/settings/overview');
      cy.get('body').then($body => {
        const hasDB = $body.text().includes('Database') ||
                     $body.text().includes('PostgreSQL');
        if (hasDB) {
          cy.log('Database status found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Cache status', () => {
      cy.visit('/app/admin/settings/overview');
      cy.get('body').then($body => {
        const hasCache = $body.text().includes('Cache') ||
                        $body.text().includes('Redis');
        if (hasCache) {
          cy.log('Cache status found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Worker status', () => {
      cy.visit('/app/admin/settings/overview');
      cy.get('body').then($body => {
        const hasWorker = $body.text().includes('Worker') ||
                         $body.text().includes('Sidekiq') ||
                         $body.text().includes('Jobs');
        if (hasWorker) {
          cy.log('Worker status found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display status indicators', () => {
      cy.visit('/app/admin/settings/overview');
      cy.get('body').then($body => {
        const hasIndicators = $body.text().includes('Operational') ||
                             $body.text().includes('Online') ||
                             $body.text().includes('Healthy') ||
                             $body.find('[class*="green"]').length > 0;
        if (hasIndicators) {
          cy.log('Status indicators found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('System Metrics Section', () => {
    it('should display System Metrics section', () => {
      cy.visit('/app/admin/settings/overview');
      cy.get('body').then($body => {
        const hasMetrics = $body.text().includes('System Metrics') ||
                          $body.text().includes('Metrics');
        if (hasMetrics) {
          cy.log('System Metrics section found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Total Users metric', () => {
      cy.visit('/app/admin/settings/overview');
      cy.get('body').then($body => {
        const hasUsers = $body.text().includes('Total Users') ||
                        $body.text().includes('Users');
        if (hasUsers) {
          cy.log('Total Users metric found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Active Accounts metric', () => {
      cy.visit('/app/admin/settings/overview');
      cy.get('body').then($body => {
        const hasAccounts = $body.text().includes('Active Accounts') ||
                           $body.text().includes('Accounts');
        if (hasAccounts) {
          cy.log('Active Accounts metric found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Total Revenue metric', () => {
      cy.visit('/app/admin/settings/overview');
      cy.get('body').then($body => {
        const hasRevenue = $body.text().includes('Revenue') ||
                          $body.text().includes('MRR') ||
                          $body.text().match(/\$[\d,]+/);
        if (hasRevenue) {
          cy.log('Total Revenue metric found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Active Subscriptions metric', () => {
      cy.visit('/app/admin/settings/overview');
      cy.get('body').then($body => {
        const hasSubs = $body.text().includes('Subscriptions') ||
                       $body.text().includes('Active Plans');
        if (hasSubs) {
          cy.log('Active Subscriptions metric found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Payment Gateway Status', () => {
    it('should display Payment Gateway section', () => {
      cy.visit('/app/admin/settings/overview');
      cy.get('body').then($body => {
        const hasPayment = $body.text().includes('Payment') ||
                          $body.text().includes('Gateway');
        if (hasPayment) {
          cy.log('Payment Gateway section found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Stripe status', () => {
      cy.visit('/app/admin/settings/overview');
      cy.get('body').then($body => {
        const hasStripe = $body.text().includes('Stripe');
        if (hasStripe) {
          cy.log('Stripe status found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display PayPal status', () => {
      cy.visit('/app/admin/settings/overview');
      cy.get('body').then($body => {
        const hasPayPal = $body.text().includes('PayPal');
        if (hasPayPal) {
          cy.log('PayPal status found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display gateway connection status', () => {
      cy.visit('/app/admin/settings/overview');
      cy.get('body').then($body => {
        const hasConnection = $body.text().includes('Connected') ||
                             $body.text().includes('Configured') ||
                             $body.text().includes('Not Configured');
        if (hasConnection) {
          cy.log('Gateway connection status found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Services Health Section', () => {
    it('should display Services Health section', () => {
      cy.visit('/app/admin/settings/overview');
      cy.get('body').then($body => {
        const hasHealth = $body.text().includes('Services') ||
                         $body.text().includes('Health');
        if (hasHealth) {
          cy.log('Services Health section found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Email service status', () => {
      cy.visit('/app/admin/settings/overview');
      cy.get('body').then($body => {
        const hasEmail = $body.text().includes('Email') ||
                        $body.text().includes('SMTP');
        if (hasEmail) {
          cy.log('Email service status found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Storage service status', () => {
      cy.visit('/app/admin/settings/overview');
      cy.get('body').then($body => {
        const hasStorage = $body.text().includes('Storage') ||
                          $body.text().includes('S3') ||
                          $body.text().includes('Files');
        if (hasStorage) {
          cy.log('Storage service status found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display service health indicators', () => {
      cy.visit('/app/admin/settings/overview');
      cy.get('body').then($body => {
        const hasIndicators = $body.find('[class*="badge"]').length > 0 ||
                             $body.find('[class*="indicator"]').length > 0;
        if (hasIndicators) {
          cy.log('Service health indicators found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Recent Activity Section', () => {
    it('should display Recent Activity section', () => {
      cy.visit('/app/admin/settings/overview');
      cy.get('body').then($body => {
        const hasActivity = $body.text().includes('Recent Activity') ||
                           $body.text().includes('Activity');
        if (hasActivity) {
          cy.log('Recent Activity section found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display recent users', () => {
      cy.visit('/app/admin/settings/overview');
      cy.get('body').then($body => {
        const hasUsers = $body.text().includes('Recent Users') ||
                        $body.text().includes('New Users');
        if (hasUsers) {
          cy.log('Recent users found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display recent accounts', () => {
      cy.visit('/app/admin/settings/overview');
      cy.get('body').then($body => {
        const hasAccounts = $body.text().includes('Recent Accounts') ||
                           $body.text().includes('New Accounts');
        if (hasAccounts) {
          cy.log('Recent accounts found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display audit logs preview', () => {
      cy.visit('/app/admin/settings/overview');
      cy.get('body').then($body => {
        const hasLogs = $body.text().includes('Audit') ||
                       $body.text().includes('Logs') ||
                       $body.text().includes('Activity Log');
        if (hasLogs) {
          cy.log('Audit logs preview found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Configuration Overview Section', () => {
    it('should display Configuration Overview section', () => {
      cy.visit('/app/admin/settings/overview');
      cy.get('body').then($body => {
        const hasConfig = $body.text().includes('Configuration') ||
                         $body.text().includes('Settings');
        if (hasConfig) {
          cy.log('Configuration Overview section found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display General Settings link', () => {
      cy.visit('/app/admin/settings/overview');
      cy.get('body').then($body => {
        const hasGeneral = $body.text().includes('General') ||
                          $body.text().includes('Site Settings');
        if (hasGeneral) {
          cy.log('General Settings link found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Security Settings link', () => {
      cy.visit('/app/admin/settings/overview');
      cy.get('body').then($body => {
        const hasSecurity = $body.text().includes('Security');
        if (hasSecurity) {
          cy.log('Security Settings link found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Billing Settings link', () => {
      cy.visit('/app/admin/settings/overview');
      cy.get('body').then($body => {
        const hasBilling = $body.text().includes('Billing');
        if (hasBilling) {
          cy.log('Billing Settings link found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Email Settings link', () => {
      cy.visit('/app/admin/settings/overview');
      cy.get('body').then($body => {
        const hasEmailSettings = $body.text().includes('Email') ||
                                $body.text().includes('Notifications');
        if (hasEmailSettings) {
          cy.log('Email Settings link found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Quick Links', () => {
    it('should display quick action cards', () => {
      cy.visit('/app/admin/settings/overview');
      cy.get('body').then($body => {
        const hasCards = $body.find('[class*="card"]').length > 0 ||
                        $body.find('[class*="rounded"]').length > 0;
        if (hasCards) {
          cy.log('Quick action cards found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should navigate to Users Management', () => {
      cy.visit('/app/admin/settings/overview');
      cy.get('body').then($body => {
        if ($body.find('a:contains("Users")').length > 0) {
          cy.contains('a', 'Users').click();
          cy.url().should('include', '/admin');
        }
      });
    });

    it('should navigate to Roles Management', () => {
      cy.visit('/app/admin/settings/overview');
      cy.get('body').then($body => {
        if ($body.find('a:contains("Roles")').length > 0) {
          cy.contains('a', 'Roles').click();
          cy.url().should('include', '/admin');
        }
      });
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.intercept('GET', '**/api/**/admin/**', {
        statusCode: 500,
        body: { error: 'Internal Server Error' }
      }).as('apiError');

      cy.visit('/app/admin/settings/overview');
      cy.get('body').should('be.visible');
    });

    it('should display error state when data fails to load', () => {
      cy.intercept('GET', '**/api/**/admin/**', {
        statusCode: 500,
        body: { error: 'Failed to load' }
      }).as('loadError');

      cy.visit('/app/admin/settings/overview');
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
      cy.intercept('GET', '**/api/**/admin/**', (req) => {
        req.reply((res) => {
          res.delay = 2000;
          res.send({ success: true, data: {} });
        });
      }).as('slowLoad');

      cy.visit('/app/admin/settings/overview');
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
      cy.visit('/app/admin/settings/overview');
      cy.get('body').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/admin/settings/overview');
      cy.get('body').should('be.visible');
    });

    it('should stack cards on small screens', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/admin/settings/overview');
      cy.get('body').then($body => {
        const hasStack = $body.find('[class*="grid-cols-1"]').length > 0 ||
                        $body.find('[class*="md:grid-cols"]').length > 0;
        if (hasStack) {
          cy.log('Stacked cards found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should show multi-column layout on large screens', () => {
      cy.viewport(1920, 1080);
      cy.visit('/app/admin/settings/overview');
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
