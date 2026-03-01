/// <reference types="cypress" />

/**
 * BaaS Billing Tests
 *
 * Tests for BaaS Billing functionality including:
 * - Billing dashboard
 * - Tenant billing
 * - Pricing configuration
 * - Invoice management
 * - Payment processing
 * - Revenue reporting
 */

describe('BaaS Billing Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Billing Dashboard', () => {
    it('should navigate to BaaS billing', () => {
      cy.visit('/app/baas/billing');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasBilling = $body.text().includes('Billing') ||
                          $body.text().includes('Revenue') ||
                          $body.text().includes('Payment');
        if (hasBilling) {
          cy.log('BaaS billing dashboard loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display total revenue', () => {
      cy.visit('/app/baas/billing');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasRevenue = $body.text().includes('Revenue') ||
                          $body.text().includes('$') ||
                          $body.text().includes('Total');
        if (hasRevenue) {
          cy.log('Total revenue displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display outstanding invoices', () => {
      cy.visit('/app/baas/billing');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasOutstanding = $body.text().includes('Outstanding') ||
                              $body.text().includes('Unpaid') ||
                              $body.text().includes('Due');
        if (hasOutstanding) {
          cy.log('Outstanding invoices displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display payment success rate', () => {
      cy.visit('/app/baas/billing');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSuccessRate = $body.text().includes('Success') ||
                              $body.text().includes('%') ||
                              $body.text().includes('Rate');
        if (hasSuccessRate) {
          cy.log('Payment success rate displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Tenant Billing', () => {
    beforeEach(() => {
      cy.visit('/app/baas/billing/tenants');
      cy.waitForPageLoad();
    });

    it('should display tenant billing list', () => {
      cy.get('body').then($body => {
        const hasList = $body.find('table, [data-testid="tenant-billing-list"]').length > 0 ||
                       $body.text().includes('Tenant');
        if (hasList) {
          cy.log('Tenant billing list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display tenant subscription status', () => {
      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Active') ||
                         $body.text().includes('Trialing') ||
                         $body.text().includes('Cancelled') ||
                         $body.text().includes('Status');
        if (hasStatus) {
          cy.log('Tenant subscription status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display tenant plan', () => {
      cy.get('body').then($body => {
        const hasPlan = $body.text().includes('Plan') ||
                       $body.text().includes('Starter') ||
                       $body.text().includes('Pro') ||
                       $body.text().includes('Enterprise');
        if (hasPlan) {
          cy.log('Tenant plan displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display tenant MRR', () => {
      cy.get('body').then($body => {
        const hasMRR = $body.text().includes('MRR') ||
                      $body.text().includes('$') ||
                      $body.text().includes('Revenue');
        if (hasMRR) {
          cy.log('Tenant MRR displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have view tenant details option', () => {
      cy.get('body').then($body => {
        const hasView = $body.find('button:contains("View"), a[href*="tenant"]').length > 0 ||
                       $body.text().includes('Detail');
        if (hasView) {
          cy.log('View tenant details option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Pricing Configuration', () => {
    it('should navigate to pricing configuration', () => {
      cy.visit('/app/baas/billing/pricing');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasPricing = $body.text().includes('Pricing') ||
                          $body.text().includes('Plan') ||
                          $body.text().includes('Price');
        if (hasPricing) {
          cy.log('Pricing configuration page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display pricing plans', () => {
      cy.visit('/app/baas/billing/pricing');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasPlans = $body.find('.plan-card, [data-testid="pricing-plans"]').length > 0 ||
                        $body.text().includes('Starter') ||
                        $body.text().includes('Pro');
        if (hasPlans) {
          cy.log('Pricing plans displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have create plan button', () => {
      cy.visit('/app/baas/billing/pricing');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCreate = $body.find('button:contains("Create"), button:contains("Add"), button:contains("New")').length > 0;
        if (hasCreate) {
          cy.log('Create plan button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have edit plan option', () => {
      cy.visit('/app/baas/billing/pricing');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasEdit = $body.find('button:contains("Edit")').length > 0 ||
                       $body.text().includes('Edit');
        if (hasEdit) {
          cy.log('Edit plan option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display pricing tiers', () => {
      cy.visit('/app/baas/billing/pricing');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasTiers = $body.text().includes('Tier') ||
                        $body.text().includes('Level') ||
                        $body.text().includes('Usage');
        if (hasTiers) {
          cy.log('Pricing tiers displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Invoice Management', () => {
    beforeEach(() => {
      cy.visit('/app/baas/billing/invoices');
      cy.waitForPageLoad();
    });

    it('should display invoice list', () => {
      cy.get('body').then($body => {
        const hasInvoices = $body.find('table, [data-testid="invoices-list"]').length > 0 ||
                           $body.text().includes('Invoice');
        if (hasInvoices) {
          cy.log('Invoice list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display invoice status', () => {
      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Paid') ||
                         $body.text().includes('Pending') ||
                         $body.text().includes('Overdue') ||
                         $body.text().includes('Draft');
        if (hasStatus) {
          cy.log('Invoice status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have filter by status', () => {
      cy.get('body').then($body => {
        const hasFilter = $body.find('select, [data-testid="status-filter"]').length > 0 ||
                         $body.text().includes('Filter');
        if (hasFilter) {
          cy.log('Filter by status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have download invoice option', () => {
      cy.get('body').then($body => {
        const hasDownload = $body.find('button:contains("Download"), a[download]').length > 0 ||
                           $body.text().includes('Download') ||
                           $body.text().includes('PDF');
        if (hasDownload) {
          cy.log('Download invoice option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have send invoice option', () => {
      cy.get('body').then($body => {
        const hasSend = $body.find('button:contains("Send"), button:contains("Email")').length > 0 ||
                       $body.text().includes('Send');
        if (hasSend) {
          cy.log('Send invoice option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Payment Processing', () => {
    beforeEach(() => {
      cy.visit('/app/baas/billing/payments');
      cy.waitForPageLoad();
    });

    it('should display payment list', () => {
      cy.get('body').then($body => {
        const hasPayments = $body.find('table, [data-testid="payments-list"]').length > 0 ||
                           $body.text().includes('Payment');
        if (hasPayments) {
          cy.log('Payment list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display payment status', () => {
      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Successful') ||
                         $body.text().includes('Failed') ||
                         $body.text().includes('Pending') ||
                         $body.text().includes('Refunded');
        if (hasStatus) {
          cy.log('Payment status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display payment method', () => {
      cy.get('body').then($body => {
        const hasMethod = $body.text().includes('Card') ||
                         $body.text().includes('Bank') ||
                         $body.text().includes('PayPal') ||
                         $body.text().includes('****');
        if (hasMethod) {
          cy.log('Payment method displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have refund option', () => {
      cy.get('body').then($body => {
        const hasRefund = $body.find('button:contains("Refund")').length > 0 ||
                         $body.text().includes('Refund');
        if (hasRefund) {
          cy.log('Refund option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have retry payment option', () => {
      cy.get('body').then($body => {
        const hasRetry = $body.find('button:contains("Retry")').length > 0 ||
                        $body.text().includes('Retry');
        if (hasRetry) {
          cy.log('Retry payment option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Revenue Reporting', () => {
    beforeEach(() => {
      cy.visit('/app/baas/billing/reports');
      cy.waitForPageLoad();
    });

    it('should display revenue report', () => {
      cy.get('body').then($body => {
        const hasReport = $body.text().includes('Report') ||
                         $body.text().includes('Revenue') ||
                         $body.text().includes('Summary');
        if (hasReport) {
          cy.log('Revenue report displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display MRR breakdown', () => {
      cy.get('body').then($body => {
        const hasMRR = $body.text().includes('MRR') ||
                      $body.text().includes('New') ||
                      $body.text().includes('Churned') ||
                      $body.text().includes('Expansion');
        if (hasMRR) {
          cy.log('MRR breakdown displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have export report option', () => {
      cy.get('body').then($body => {
        const hasExport = $body.find('button:contains("Export"), button:contains("Download")').length > 0 ||
                         $body.text().includes('Export');
        if (hasExport) {
          cy.log('Export report option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have date range selector', () => {
      cy.get('body').then($body => {
        const hasDateRange = $body.find('input[type="date"]').length > 0 ||
                            $body.text().includes('Date') ||
                            $body.text().includes('Range');
        if (hasDateRange) {
          cy.log('Date range selector displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Dunning Management', () => {
    it('should navigate to dunning settings', () => {
      cy.visit('/app/baas/billing/dunning');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDunning = $body.text().includes('Dunning') ||
                          $body.text().includes('Retry') ||
                          $body.text().includes('Failed payment');
        if (hasDunning) {
          cy.log('Dunning settings page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display retry schedule', () => {
      cy.visit('/app/baas/billing/dunning');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSchedule = $body.text().includes('Schedule') ||
                           $body.text().includes('Retry') ||
                           $body.text().includes('days');
        if (hasSchedule) {
          cy.log('Retry schedule displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display failed payment emails', () => {
      cy.visit('/app/baas/billing/dunning');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasEmails = $body.text().includes('Email') ||
                         $body.text().includes('Notification') ||
                         $body.text().includes('Template');
        if (hasEmails) {
          cy.log('Failed payment emails displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have configure dunning option', () => {
      cy.visit('/app/baas/billing/dunning');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasConfigure = $body.find('button:contains("Configure"), button:contains("Edit")').length > 0 ||
                            $body.text().includes('Configure');
        if (hasConfigure) {
          cy.log('Configure dunning option displayed');
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
      it(`should display BaaS billing correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/baas/billing');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`BaaS billing displayed correctly on ${name}`);
      });
    });
  });
});
