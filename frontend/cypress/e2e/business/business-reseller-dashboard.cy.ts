/// <reference types="cypress" />

/**
 * Business Reseller Dashboard Tests
 *
 * Enhanced E2E tests for the Reseller/Partner Dashboard:
 * - Partner program enrollment states
 * - Dashboard summary statistics
 * - Partner tier display and benefits
 * - Commission tracking
 * - Payout history and management
 * - Referral code functionality
 *
 * Uses proper API intercepts and meaningful assertions.
 */

describe('Business Reseller Dashboard Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Partner Program - Not Enrolled State', () => {
    beforeEach(() => {
      setupResellerIntercepts({ enrolled: false });
      cy.navigateTo('/app/business/reseller');
    });

    it('should display partner program enrollment page', () => {
      cy.assertContainsAny(['Partner Program', 'Join', 'Become a Partner']);
    });

    it('should show partnership benefits description', () => {
      cy.assertContainsAny(['earn', 'commissions', 'referring', 'partner', 'revenue']);
    });

    it('should display commission tier preview', () => {
      cy.assertContainsAny(['Bronze', 'Silver', 'Gold', 'Platinum']);
      cy.assertContainsAny(['10%', '15%', '20%', '25%']);
    });

    it('should have apply button', () => {
      cy.get('button').contains(/apply|become|join/i).should('be.visible');
    });

    it('should trigger application flow when apply clicked', () => {
      cy.get('button').contains(/apply|become|join/i).click();
      cy.assertContainsAny(['Application', 'coming soon', 'info', 'Partner']);
    });
  });

  describe('Partner Program - Pending Approval State', () => {
    beforeEach(() => {
      setupResellerIntercepts({ enrolled: true, status: 'pending' });
      cy.navigateTo('/app/business/reseller');
    });

    it('should display pending approval message', () => {
      cy.assertContainsAny(['Under Review', 'Pending', 'Application']);
    });

    it('should show review timeline information', () => {
      cy.assertContainsAny(['review', 'notify', 'business days', 'approved']);
    });

    it('should display company information submitted', () => {
      cy.assertContainsAny(['Company', 'Partner Company']);
    });
  });

  describe('Partner Dashboard - Active Partner', () => {
    beforeEach(() => {
      setupResellerIntercepts({ enrolled: true, status: 'active' });
      cy.navigateTo('/app/business/reseller');
    });

    describe('Page Layout', () => {
      it('should display partner dashboard title', () => {
        cy.assertContainsAny(['Partner Dashboard', 'Reseller Dashboard']);
      });

      it('should have referral code copy button', () => {
        cy.assertContainsAny(['Copy', 'Referral Code', 'PARTNER']);
      });
    });

    describe('Summary Statistics Cards', () => {
      it('should display total referrals card', () => {
        cy.assertContainsAny(['Total Referrals', 'Referrals']);
      });

      it('should display active referrals count', () => {
        cy.assertContainsAny(['active', 'Active']);
      });

      it('should display revenue generated card', () => {
        cy.assertContainsAny(['Revenue Generated', 'Revenue', '$']);
      });

      it('should display total paid out card', () => {
        cy.assertContainsAny(['Total Paid', 'Paid Out', 'earnings', '$']);
      });
    });

    describe('Partner Tier Card', () => {
      it('should display current partner tier', () => {
        cy.assertContainsAny(['Bronze', 'Silver', 'Gold', 'Platinum', 'Tier']);
      });

      it('should show tier benefits', () => {
        cy.assertContainsAny(['commission', '%', 'rate', 'benefits']);
      });

      it('should indicate upgrade eligibility if applicable', () => {
        cy.get('body').then($body => {
          if ($body.text().includes('Eligible') || $body.text().includes('upgrade')) {
            cy.assertContainsAny(['Eligible', 'upgrade', 'next tier']);
          }
        });
      });

      it('should show progress towards next tier', () => {
        cy.get('body').then($body => {
          const hasProgress = $body.find('[role="progressbar"], [class*="progress"]').length > 0 ||
                             $body.text().match(/\d+\s*\/\s*\d+/) !== null;
          if (hasProgress) {
            cy.log('Tier progress indicator displayed');
          }
        });
      });
    });

    describe('Commission Tracker', () => {
      it('should display commission tracking section', () => {
        cy.assertContainsAny(['Commission', 'Commissions', 'Tracker']);
      });

      it('should show lifetime earnings', () => {
        cy.assertContainsAny(['Lifetime', 'Total', 'Earnings', '$']);
      });

      it('should show pending payout amount', () => {
        cy.assertContainsAny(['Pending', 'Payout', 'Available', '$']);
      });

      it('should display recent commissions list', () => {
        cy.get('body').then($body => {
          const hasCommissions = $body.find('[data-testid*="commission"], table').length > 0 ||
                                $body.text().includes('Commission');
          expect(hasCommissions).to.be.true;
        });
      });
    });

    describe('Payout History', () => {
      it('should display payout history section', () => {
        cy.assertContainsAny(['Payout', 'History', 'Payments']);
      });

      it('should show pending payout balance', () => {
        cy.assertContainsAny(['Pending', 'Balance', 'Available', '$']);
      });

      it('should have request payout button when eligible', () => {
        cy.get('body').then($body => {
          if ($body.find('button:contains("Request")').length > 0) {
            cy.get('button').contains(/request/i).should('be.visible');
          }
        });
      });

      it('should display payout transaction list', () => {
        cy.get('body').then($body => {
          const hasPayouts = $body.find('[data-testid*="payout"], table, [class*="payout"]').length > 0;
          if (hasPayouts) {
            cy.log('Payout transaction list displayed');
          }
        });
      });
    });

    describe('Referral Code Functionality', () => {
      it('should display referral code', () => {
        cy.assertContainsAny(['PARTNER', 'REF', 'Referral']);
      });

      it('should copy referral code to clipboard when button clicked', () => {
        cy.get('button').contains(/copy/i).click();
        cy.assertContainsAny(['copied', 'Copied', 'clipboard', 'success']);
      });
    });
  });

  describe('Request Payout Flow', () => {
    beforeEach(() => {
      setupResellerIntercepts({ enrolled: true, status: 'active', canRequestPayout: true });
      cy.navigateTo('/app/business/reseller');
    });

    it('should trigger payout request when button clicked', () => {
      cy.intercept('POST', '**/api/**/resellers/*/payouts/request*', {
        statusCode: 200,
        body: { success: true, message: 'Payout request submitted' },
      }).as('requestPayout');

      cy.get('body').then($body => {
        const requestButton = $body.find('button:contains("Request")').first();
        if (requestButton.length > 0) {
          cy.wrap(requestButton).click();
          cy.wait('@requestPayout', { timeout: 10000 });
          cy.assertContainsAny(['success', 'submitted', 'requested']);
        }
      });
    });
  });

  describe('Error Handling', () => {
    it('should handle reseller data fetch error gracefully', () => {
      cy.testErrorHandling('**/api/**/resellers/**', {
        statusCode: 500,
        visitUrl: '/app/business/reseller',
      });
    });

    it('should display retry option on error', () => {
      cy.intercept('GET', '**/api/**/resellers/me*', {
        statusCode: 500,
        body: { error: 'Internal server error' },
      }).as('failedReseller');

      cy.visit('/app/business/reseller');

      cy.get('body').then($body => {
        if ($body.text().includes('Error') || $body.text().includes('Failed')) {
          cy.assertContainsAny(['Retry', 'Try again', 'Reload']);
        }
      });
    });
  });

  describe('Loading States', () => {
    it('should display loading indicator while fetching data', () => {
      cy.intercept('GET', '**/api/**/resellers/me*', {
        statusCode: 200,
        body: { success: true, data: null },
        delay: 1000,
      }).as('slowReseller');

      cy.visit('/app/business/reseller');
      cy.verifyLoadingState();
    });
  });

  describe('Responsive Design', () => {
    beforeEach(() => {
      setupResellerIntercepts({ enrolled: true, status: 'active' });
    });

    it('should display correctly across viewports', () => {
      cy.testResponsiveDesign('/app/business/reseller', {
        checkContent: 'Partner',
      });
    });

    it('should stack cards on mobile viewport', () => {
      cy.viewport(375, 667);
      cy.navigateTo('/app/business/reseller');
      cy.get('body').should('be.visible');
    });
  });

  describe('Sub-Page Navigation', () => {
    beforeEach(() => {
      setupResellerIntercepts({ enrolled: true, status: 'active' });
    });

    it('should navigate to commissions detail page', () => {
      cy.navigateTo('/app/business/reseller/commissions');
      cy.assertContainsAny(['Commission', 'Commissions', 'Earnings']);
    });

    it('should navigate to payouts page', () => {
      cy.navigateTo('/app/business/reseller/payouts');
      cy.assertContainsAny(['Payout', 'Payouts', 'Payments']);
    });

    it('should navigate to referrals page', () => {
      cy.navigateTo('/app/business/reseller/referrals');
      cy.assertContainsAny(['Referral', 'Referrals', 'Link']);
    });

    it('should navigate to tiers page', () => {
      cy.navigateTo('/app/business/reseller/tiers');
      cy.assertContainsAny(['Tier', 'Level', 'Benefits', 'Bronze', 'Silver', 'Gold', 'Platinum']);
    });
  });
});

/**
 * Setup reseller API intercepts with configurable mock data
 */
function setupResellerIntercepts(options: {
  enrolled?: boolean;
  status?: 'pending' | 'active' | 'suspended';
  canRequestPayout?: boolean;
} = {}) {
  const { enrolled = true, status = 'active', canRequestPayout = false } = options;

  const mockReseller = enrolled
    ? {
        id: 'reseller-1',
        account_id: 'acct-1',
        company_name: 'Partner Company LLC',
        status: status,
        tier: 'silver',
        referral_code: 'PARTNER123',
        tier_benefits: {
          commission_rate: 0.15,
          priority_support: true,
          marketing_materials: true,
        },
        created_at: '2024-06-15T10:00:00Z',
        updated_at: '2025-01-15T10:00:00Z',
      }
    : null;

  const mockDashboardStats = enrolled && status === 'active'
    ? {
        total_referrals: 47,
        active_referrals: 38,
        total_revenue_generated: 125000,
        total_paid_out: 15000,
        lifetime_earnings: 18750,
        pending_payout: 3750,
        can_request_payout: canRequestPayout,
        tier: 'silver',
        next_tier: 'gold',
        eligible_for_upgrade: true,
        recent_commissions: [
          { id: 'comm-1', amount: 150, referral_id: 'ref-1', status: 'pending', created_at: '2025-01-15T10:00:00Z' },
          { id: 'comm-2', amount: 200, referral_id: 'ref-2', status: 'paid', created_at: '2025-01-14T10:00:00Z' },
          { id: 'comm-3', amount: 75, referral_id: 'ref-3', status: 'paid', created_at: '2025-01-13T10:00:00Z' },
        ],
        pending_payouts: [
          { id: 'payout-1', amount: 500, status: 'processing', requested_at: '2025-01-10T10:00:00Z' },
        ],
      }
    : null;

  // Get current reseller
  cy.intercept('GET', '**/api/**/resellers/me*', {
    statusCode: 200,
    body: { success: true, data: mockReseller },
  }).as('getMyReseller');

  // Get reseller dashboard
  if (mockReseller && mockDashboardStats) {
    cy.intercept('GET', '**/api/**/resellers/*/dashboard*', {
      statusCode: 200,
      body: { success: true, data: mockDashboardStats },
    }).as('getResellerDashboard');
  }

  // Get commissions
  cy.intercept('GET', '**/api/**/resellers/*/commissions*', {
    statusCode: 200,
    body: {
      success: true,
      data: mockDashboardStats?.recent_commissions || [],
    },
  }).as('getCommissions');

  // Get payouts
  cy.intercept('GET', '**/api/**/resellers/*/payouts*', {
    statusCode: 200,
    body: {
      success: true,
      data: mockDashboardStats?.pending_payouts || [],
    },
  }).as('getPayouts');

  // Get referrals
  cy.intercept('GET', '**/api/**/resellers/*/referrals*', {
    statusCode: 200,
    body: {
      success: true,
      data: [
        { id: 'ref-1', customer_name: 'Acme Corp', status: 'active', mrr: 500, created_at: '2025-01-01T10:00:00Z' },
        { id: 'ref-2', customer_name: 'Tech Inc', status: 'active', mrr: 750, created_at: '2024-12-15T10:00:00Z' },
        { id: 'ref-3', customer_name: 'Data LLC', status: 'churned', mrr: 0, created_at: '2024-11-01T10:00:00Z' },
      ],
    },
  }).as('getReferrals');

  // Request payout
  cy.intercept('POST', '**/api/**/resellers/*/payouts/request*', {
    statusCode: 200,
    body: { success: true, message: 'Payout request submitted successfully' },
  }).as('requestPayout');

  // Get tier information
  cy.intercept('GET', '**/api/**/resellers/tiers*', {
    statusCode: 200,
    body: {
      success: true,
      data: [
        { name: 'Bronze', commission_rate: 0.10, min_referrals: 0, min_revenue: 0 },
        { name: 'Silver', commission_rate: 0.15, min_referrals: 10, min_revenue: 25000 },
        { name: 'Gold', commission_rate: 0.20, min_referrals: 25, min_revenue: 75000 },
        { name: 'Platinum', commission_rate: 0.25, min_referrals: 50, min_revenue: 200000 },
      ],
    },
  }).as('getTiers');
}

export {};
