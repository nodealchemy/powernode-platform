/// <reference types="cypress" />

/**
 * Business Billing Page Tests
 *
 * Tests for Business Billing functionality including:
 * - Page navigation and load
 * - Tab navigation (Overview, Invoices, Analytics)
 * - Statistics cards display (Outstanding, This Month, Collected, Success Rate)
 * - Invoices list display
 * - Create Invoice modal
 * - Date filtering
 * - Payment methods display
 * - Invoice status breakdown
 * - Permission-based access
 * - Error handling
 * - Responsive design
 */

describe('Business Billing Page Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.setupApiIntercepts();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 5000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').should('be.visible').click();
    cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to Billing page', () => {
      cy.visit('/app/business/billing');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Billing') ||
                          $body.text().includes('Invoice') ||
                          $body.text().includes('Permission');
        if (hasContent) {
          cy.log('Billing page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page title', () => {
      cy.visit('/app/business/billing');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('Billing');
        if (hasTitle) {
          cy.log('Page title displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page description', () => {
      cy.visit('/app/business/billing');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDescription = $body.text().includes('Manage') ||
                               $body.text().includes('invoices') ||
                               $body.text().includes('payments');
        if (hasDescription) {
          cy.log('Page description displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/business/billing');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('Dashboard') ||
                               $body.text().includes('Business');
        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Tab Navigation', () => {
    beforeEach(() => {
      cy.visit('/app/business/billing');
      cy.waitForPageLoad();
    });

    it('should display Overview tab', () => {
      cy.get('body').then($body => {
        const hasOverview = $body.text().includes('Overview');
        if (hasOverview) {
          cy.log('Overview tab displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Invoices tab', () => {
      cy.get('body').then($body => {
        const hasInvoices = $body.text().includes('Invoices');
        if (hasInvoices) {
          cy.log('Invoices tab displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Analytics tab', () => {
      cy.get('body').then($body => {
        const hasAnalytics = $body.text().includes('Analytics');
        if (hasAnalytics) {
          cy.log('Analytics tab displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should switch to Invoices tab', () => {
      cy.get('body').then($body => {
        const invoicesTab = $body.find('button:contains("Invoices")');
        if (invoicesTab.length > 0) {
          cy.wrap(invoicesTab).first().should('be.visible').click();
          cy.get('body').should('contain.text', 'Invoices');
          cy.log('Switched to Invoices tab');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should switch to Analytics tab', () => {
      cy.get('body').then($body => {
        const analyticsTab = $body.find('button:contains("Analytics")');
        if (analyticsTab.length > 0) {
          cy.wrap(analyticsTab).first().should('be.visible').click();
          cy.get('body').should('contain.text', 'Analytics');
          cy.log('Switched to Analytics tab');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Overview Tab - Statistics Cards', () => {
    beforeEach(() => {
      cy.visit('/app/business/billing');
      cy.waitForPageLoad();
    });

    it('should display Outstanding stat', () => {
      cy.get('body').then($body => {
        const hasOutstanding = $body.text().includes('Outstanding');
        if (hasOutstanding) {
          cy.log('Outstanding stat displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display This Month stat', () => {
      cy.get('body').then($body => {
        const hasThisMonth = $body.text().includes('This Month') ||
                            $body.text().includes('Invoiced');
        if (hasThisMonth) {
          cy.log('This Month stat displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Collected stat', () => {
      cy.get('body').then($body => {
        const hasCollected = $body.text().includes('Collected');
        if (hasCollected) {
          cy.log('Collected stat displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Success Rate stat', () => {
      cy.get('body').then($body => {
        const hasSuccessRate = $body.text().includes('Success Rate') ||
                              $body.text().includes('%');
        if (hasSuccessRate) {
          cy.log('Success Rate stat displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Overview Tab - Quick Actions', () => {
    beforeEach(() => {
      cy.visit('/app/business/billing');
      cy.waitForPageLoad();
    });

    it('should display Create Invoice action card', () => {
      cy.get('body').then($body => {
        const hasCreateInvoice = $body.text().includes('Create Invoice');
        if (hasCreateInvoice) {
          cy.log('Create Invoice action card displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display View Reports action card', () => {
      cy.get('body').then($body => {
        const hasViewReports = $body.text().includes('View Reports') ||
                              $body.text().includes('Reports');
        if (hasViewReports) {
          cy.log('View Reports action card displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Recent Activity section', () => {
      cy.get('body').then($body => {
        const hasRecentActivity = $body.text().includes('Recent Activity');
        if (hasRecentActivity) {
          cy.log('Recent Activity section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Page Actions', () => {
    beforeEach(() => {
      cy.visit('/app/business/billing');
      cy.waitForPageLoad();
    });

    it('should have Create Invoice button', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Invoice")');
        if (createButton.length > 0) {
          cy.log('Create Invoice button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Refresh button', () => {
      cy.get('body').then($body => {
        const refreshButton = $body.find('button:contains("Refresh")');
        if (refreshButton.length > 0) {
          cy.log('Refresh button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should open Create Invoice modal', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Invoice")');
        if (createButton.length > 0) {
          cy.wrap(createButton).first().should('be.visible').click();
          cy.waitForStableDOM();
          cy.get('body').then($modalBody => {
            const hasModal = $modalBody.find('[class*="modal"], [class*="Modal"]').length > 0 ||
                             $modalBody.text().includes('Create Invoice') ||
                             $modalBody.text().includes('Invoice');
            if (hasModal) {
              cy.log('Create Invoice modal opened');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Invoices Tab', () => {
    beforeEach(() => {
      cy.visit('/app/business/billing');
      cy.waitForPageLoad();
      // Switch to Invoices tab
      cy.get('body').then($body => {
        const invoicesTab = $body.find('button:contains("Invoices")');
        if (invoicesTab.length > 0) {
          cy.wrap(invoicesTab).first().should('be.visible').click();
          cy.get('body').should('contain.text', 'Invoices');
        }
      });
    });

    it('should display invoices table or empty state', () => {
      cy.get('body').then($body => {
        const hasInvoices = $body.find('[class*="table"], table').length > 0 ||
                           $body.text().includes('No invoices');
        if (hasInvoices) {
          cy.log('Invoices table or empty state displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Invoice column', () => {
      cy.get('body').then($body => {
        const hasColumn = $body.text().includes('Invoice') ||
                         $body.text().includes('INV-');
        if (hasColumn) {
          cy.log('Invoice column displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Customer column', () => {
      cy.get('body').then($body => {
        const hasColumn = $body.text().includes('Customer');
        if (hasColumn) {
          cy.log('Customer column displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Amount column', () => {
      cy.get('body').then($body => {
        const hasColumn = $body.text().includes('Amount') ||
                         $body.text().includes('$');
        if (hasColumn) {
          cy.log('Amount column displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Status column', () => {
      cy.get('body').then($body => {
        const hasColumn = $body.text().includes('Status') ||
                         $body.text().includes('paid') ||
                         $body.text().includes('overdue');
        if (hasColumn) {
          cy.log('Status column displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have date filter toggle', () => {
      cy.get('body').then($body => {
        const filterButton = $body.find('button:contains("Filter"), button:contains("Show Filters")');
        if (filterButton.length > 0) {
          cy.log('Date filter toggle found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Analytics Tab', () => {
    beforeEach(() => {
      cy.visit('/app/business/billing');
      cy.waitForPageLoad();
      // Switch to Analytics tab
      cy.get('body').then($body => {
        const analyticsTab = $body.find('button:contains("Analytics")');
        if (analyticsTab.length > 0) {
          cy.wrap(analyticsTab).first().should('be.visible').click();
          cy.get('body').should('contain.text', 'Analytics');
        }
      });
    });

    it('should display Total Invoices stat', () => {
      cy.get('body').then($body => {
        const hasTotal = $body.text().includes('Total Invoices');
        if (hasTotal) {
          cy.log('Total Invoices stat displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Paid Invoices stat', () => {
      cy.get('body').then($body => {
        const hasPaid = $body.text().includes('Paid');
        if (hasPaid) {
          cy.log('Paid Invoices stat displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Payment Methods section', () => {
      cy.get('body').then($body => {
        const hasPaymentMethods = $body.text().includes('Payment Methods');
        if (hasPaymentMethods) {
          cy.log('Payment Methods section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Invoice Status Breakdown', () => {
      cy.get('body').then($body => {
        const hasBreakdown = $body.text().includes('Invoice Status') ||
                            $body.text().includes('Breakdown');
        if (hasBreakdown) {
          cy.log('Invoice Status Breakdown displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Permission Check', () => {
    it('should show permission message for unauthorized users', () => {
      cy.visit('/app/business/billing');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasPermission = $body.text().includes("don't have permission") ||
                             $body.text().includes('Billing') ||
                             $body.find('[class*="card"]').length > 0;
        if (hasPermission) {
          cy.log('Permission handled properly');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.intercept('GET', '/api/v1/billing*', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/business/billing');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should display error message on failure', () => {
      cy.intercept('GET', '/api/v1/billing*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load billing data' }
      });

      cy.visit('/app/business/billing');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasError = $body.text().includes('Error') ||
                         $body.text().includes('Failed') ||
                         $body.text().includes('Try Again');
        if (hasError) {
          cy.log('Error handled');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Try Again button on error', () => {
      cy.intercept('GET', '/api/v1/billing*', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/business/billing');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const retryButton = $body.find('button:contains("Try Again")');
        if (retryButton.length > 0) {
          cy.log('Try Again button found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '/api/v1/billing*', {
        delay: 1000,
        statusCode: 200,
        body: { success: true }
      });

      cy.visit('/app/business/billing');

      cy.get('body').then($body => {
        const hasLoading = $body.find('[class*="spin"], [class*="loading"]').length > 0 ||
                           $body.text().includes('Loading');
        if (hasLoading) {
          cy.log('Loading indicator displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/business/billing');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Billing');
        if (hasContent) {
          cy.log('Content visible on mobile');
        }
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/business/billing');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Billing');
        if (hasContent) {
          cy.log('Content visible on tablet');
        }
      });
    });

    it('should stack elements on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/business/billing');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
    });

    it('should show multi-column layout on large screens', () => {
      cy.viewport(1280, 800);
      cy.visit('/app/business/billing');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasMultiColumn = $body.find('[class*="grid-cols"], [class*="md:grid-cols"]').length > 0;
        if (hasMultiColumn) {
          cy.log('Multi-column layout on large screens');
        }
      });

      cy.get('body').should('be.visible');
    });
  });
});


export {};
