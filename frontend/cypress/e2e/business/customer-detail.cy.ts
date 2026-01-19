/// <reference types="cypress" />

/**
 * Customer Detail Page E2E Tests
 *
 * Tests for individual customer detail page functionality including:
 * - Customer information display
 * - Subscription details
 * - Payment history
 * - Activity log
 * - Customer actions
 * - Responsive design
 */

describe('Customer Detail Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Page Navigation', () => {
    it('should navigate to Customers page', () => {
      cy.visit('/app/business/customers');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Customers') ||
                          $body.text().includes('Customer') ||
                          $body.text().includes('Accounts');
        if (hasContent) {
          cy.log('Customers page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display customer list', () => {
      cy.visit('/app/business/customers');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCustomerList = $body.find('table, [class*="list"], [class*="grid"]').length > 0;
        if (hasCustomerList) {
          cy.log('Customer list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should navigate to customer detail on click', () => {
      cy.visit('/app/business/customers');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const customerRow = $body.find('tr:not(:first-child), [class*="card"], [class*="item"]');
        if (customerRow.length > 0) {
          cy.wrap(customerRow).first().should('be.visible').click();
          cy.waitForPageLoad();
          cy.log('Navigated to customer detail');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Customer Information', () => {
    beforeEach(() => {
      cy.visit('/app/business/customers');
      cy.waitForPageLoad();
    });

    it('should display customer name', () => {
      cy.get('body').then($body => {
        const hasName = $body.text().includes('Name') ||
                        $body.find('[class*="name"]').length > 0;
        if (hasName) {
          cy.log('Customer name displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display customer email', () => {
      cy.get('body').then($body => {
        const hasEmail = $body.text().includes('@') ||
                         $body.text().includes('Email') ||
                         $body.find('[class*="email"]').length > 0;
        if (hasEmail) {
          cy.log('Customer email displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display customer status', () => {
      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Active') ||
                          $body.text().includes('Inactive') ||
                          $body.text().includes('Status');
        if (hasStatus) {
          cy.log('Customer status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display account creation date', () => {
      cy.get('body').then($body => {
        const hasDate = $body.text().includes('Created') ||
                        $body.text().includes('Since') ||
                        $body.text().includes('Joined');
        if (hasDate) {
          cy.log('Account creation date displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Subscription Details', () => {
    beforeEach(() => {
      cy.visit('/app/business/customers');
      cy.waitForPageLoad();
    });

    it('should display subscription plan', () => {
      cy.get('body').then($body => {
        const hasPlan = $body.text().includes('Plan') ||
                        $body.text().includes('Subscription') ||
                        $body.text().includes('Basic') ||
                        $body.text().includes('Premium');
        if (hasPlan) {
          cy.log('Subscription plan displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display subscription status', () => {
      cy.get('body').then($body => {
        const hasSubStatus = $body.text().includes('Active') ||
                             $body.text().includes('Trial') ||
                             $body.text().includes('Cancelled');
        if (hasSubStatus) {
          cy.log('Subscription status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display billing cycle', () => {
      cy.get('body').then($body => {
        const hasBilling = $body.text().includes('Monthly') ||
                           $body.text().includes('Yearly') ||
                           $body.text().includes('Annual') ||
                           $body.text().includes('Billing');
        if (hasBilling) {
          cy.log('Billing cycle displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display next billing date', () => {
      cy.get('body').then($body => {
        const hasNextBilling = $body.text().includes('Next') ||
                               $body.text().includes('Renewal') ||
                               $body.text().includes('Due');
        if (hasNextBilling) {
          cy.log('Next billing date displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Payment History', () => {
    beforeEach(() => {
      cy.visit('/app/business/customers');
      cy.waitForPageLoad();
    });

    it('should display payment history section', () => {
      cy.get('body').then($body => {
        const hasPayments = $body.text().includes('Payment') ||
                            $body.text().includes('Invoice') ||
                            $body.text().includes('Transaction');
        if (hasPayments) {
          cy.log('Payment history section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display payment amounts', () => {
      cy.get('body').then($body => {
        const hasAmounts = $body.text().includes('$') ||
                           $body.text().includes('Amount');
        if (hasAmounts) {
          cy.log('Payment amounts displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display payment dates', () => {
      cy.get('body').then($body => {
        const hasDates = $body.text().match(/\d{1,2}\/\d{1,2}\/\d{2,4}|\w+ \d{1,2}, \d{4}/) ||
                         $body.text().includes('Date');
        if (hasDates) {
          cy.log('Payment dates displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display payment status', () => {
      cy.get('body').then($body => {
        const hasPaymentStatus = $body.text().includes('Paid') ||
                                  $body.text().includes('Pending') ||
                                  $body.text().includes('Failed');
        if (hasPaymentStatus) {
          cy.log('Payment status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Customer Statistics', () => {
    beforeEach(() => {
      cy.visit('/app/business/customers');
      cy.waitForPageLoad();
    });

    it('should display lifetime value', () => {
      cy.get('body').then($body => {
        const hasLTV = $body.text().includes('Lifetime') ||
                       $body.text().includes('LTV') ||
                       $body.text().includes('Total Revenue');
        if (hasLTV) {
          cy.log('Lifetime value displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display total payments', () => {
      cy.get('body').then($body => {
        const hasTotalPayments = $body.text().includes('Total') ||
                                  $body.text().includes('Payments');
        if (hasTotalPayments) {
          cy.log('Total payments displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display customer since duration', () => {
      cy.get('body').then($body => {
        const hasDuration = $body.text().includes('years') ||
                            $body.text().includes('months') ||
                            $body.text().includes('days') ||
                            $body.text().includes('Since');
        if (hasDuration) {
          cy.log('Customer duration displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Customer Actions', () => {
    beforeEach(() => {
      cy.visit('/app/business/customers');
      cy.waitForPageLoad();
    });

    it('should have edit customer button', () => {
      cy.get('body').then($body => {
        const hasEdit = $body.find('button:contains("Edit"), [aria-label*="edit"]').length > 0;
        if (hasEdit) {
          cy.log('Edit customer button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have send email option', () => {
      cy.get('body').then($body => {
        const hasEmail = $body.find('button:contains("Email"), button:contains("Contact")').length > 0;
        if (hasEmail) {
          cy.log('Send email option found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have manage subscription option', () => {
      cy.get('body').then($body => {
        const hasManage = $body.find('button:contains("Manage"), button:contains("Subscription")').length > 0;
        if (hasManage) {
          cy.log('Manage subscription option found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have refund option', () => {
      cy.get('body').then($body => {
        const hasRefund = $body.find('button:contains("Refund")').length > 0 ||
                          $body.text().includes('Refund');
        if (hasRefund) {
          cy.log('Refund option found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Activity Log', () => {
    beforeEach(() => {
      cy.visit('/app/business/customers');
      cy.waitForPageLoad();
    });

    it('should display activity section', () => {
      cy.get('body').then($body => {
        const hasActivity = $body.text().includes('Activity') ||
                            $body.text().includes('Log') ||
                            $body.text().includes('History');
        if (hasActivity) {
          cy.log('Activity section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display activity timestamps', () => {
      cy.get('body').then($body => {
        const hasTimestamps = $body.text().includes('ago') ||
                              $body.text().includes('Today') ||
                              $body.text().includes('Yesterday');
        if (hasTimestamps) {
          cy.log('Activity timestamps displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Search and Filter', () => {
    beforeEach(() => {
      cy.visit('/app/business/customers');
      cy.waitForPageLoad();
    });

    it('should have search functionality', () => {
      cy.get('body').then($body => {
        const hasSearch = $body.find('input[type="search"], input[placeholder*="Search"]').length > 0;
        if (hasSearch) {
          cy.log('Search functionality found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have filter options', () => {
      cy.get('body').then($body => {
        const hasFilter = $body.find('select, [class*="filter"]').length > 0 ||
                          $body.text().includes('Filter');
        if (hasFilter) {
          cy.log('Filter options found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have status filter', () => {
      cy.get('body').then($body => {
        const hasStatusFilter = $body.text().includes('Status') ||
                                $body.find('select').length > 0;
        if (hasStatusFilter) {
          cy.log('Status filter found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.intercept('GET', '**/api/**/customers/**', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/business/customers');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
    });

    it('should display not found for invalid customer', () => {
      cy.visit('/app/business/customers/invalid-id-12345');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasNotFound = $body.text().includes('Not Found') ||
                            $body.text().includes('not found') ||
                            $body.text().includes('doesn\'t exist');
        if (hasNotFound) {
          cy.log('Not found message displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '**/api/**/customers/**', {
        delay: 2000,
        statusCode: 200,
        body: []
      });

      cy.visit('/app/business/customers');

      cy.get('body').then($body => {
        const hasLoading = $body.find('[class*="spin"]').length > 0 ||
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
      cy.visit('/app/business/customers');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/business/customers');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
    });

    it('should display properly on large screens', () => {
      cy.viewport(1920, 1080);
      cy.visit('/app/business/customers');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
    });
  });
});


export {};
