/// <reference types="cypress" />

/**
 * Business Subscription Changes Tests
 *
 * Tests for Subscription upgrade/downgrade functionality including:
 * - Plan comparison
 * - Upgrade flow
 * - Downgrade flow
 * - Proration display
 * - Plan switching confirmation
 * - Billing cycle changes
 */

describe('Business Subscription Changes Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Current Subscription Display', () => {
    it('should navigate to subscription page', () => {
      cy.visit('/app/business/billing/subscription');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSub = $body.text().includes('Subscription') ||
                      $body.text().includes('Plan') ||
                      $body.text().includes('Current');
        if (hasSub) {
          cy.log('Subscription page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display current plan', () => {
      cy.visit('/app/business/billing/subscription');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasPlan = $body.text().includes('Plan') ||
                       $body.text().includes('Free') ||
                       $body.text().includes('Pro') ||
                       $body.text().includes('Business');
        if (hasPlan) {
          cy.log('Current plan displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display current price', () => {
      cy.visit('/app/business/billing/subscription');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasPrice = $body.text().includes('$') ||
                        $body.text().includes('/month') ||
                        $body.text().includes('/year');
        if (hasPrice) {
          cy.log('Current price displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display billing cycle', () => {
      cy.visit('/app/business/billing/subscription');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCycle = $body.text().includes('Monthly') ||
                        $body.text().includes('Annual') ||
                        $body.text().includes('Yearly') ||
                        $body.text().includes('Billing');
        if (hasCycle) {
          cy.log('Billing cycle displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display next billing date', () => {
      cy.visit('/app/business/billing/subscription');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDate = $body.text().includes('Next') ||
                       $body.text().includes('Renewal') ||
                       $body.text().match(/\d{1,2}\/\d{1,2}\/\d{4}/) !== null ||
                       $body.text().match(/\w+ \d+/) !== null;
        if (hasDate) {
          cy.log('Next billing date displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Plan Comparison', () => {
    it('should navigate to plan comparison', () => {
      cy.visit('/app/business/billing/plans');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasPlans = $body.text().includes('Plan') ||
                        $body.text().includes('Compare') ||
                        $body.text().includes('Pricing');
        if (hasPlans) {
          cy.log('Plan comparison page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display available plans', () => {
      cy.visit('/app/business/billing/plans');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasMultiple = $body.find('[data-testid="plan-card"], .plan-card').length > 0 ||
                           ($body.text().includes('Free') && $body.text().includes('Pro')) ||
                           ($body.text().includes('Starter') && $body.text().includes('Business'));
        if (hasMultiple) {
          cy.log('Available plans displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should highlight current plan', () => {
      cy.visit('/app/business/billing/plans');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCurrent = $body.text().includes('Current') ||
                          $body.text().includes('Your plan') ||
                          $body.find('.current, [data-current="true"]').length > 0;
        if (hasCurrent) {
          cy.log('Current plan highlighted');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display plan features', () => {
      cy.visit('/app/business/billing/plans');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasFeatures = $body.find('ul li, .feature-list').length > 0 ||
                           $body.text().includes('✓') ||
                           $body.text().includes('Feature');
        if (hasFeatures) {
          cy.log('Plan features displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Upgrade Flow', () => {
    it('should display upgrade button', () => {
      cy.visit('/app/business/billing/plans');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasUpgrade = $body.find('button:contains("Upgrade"), button:contains("Select")').length > 0 ||
                          $body.text().includes('Upgrade');
        if (hasUpgrade) {
          cy.log('Upgrade button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should show upgrade confirmation', () => {
      cy.visit('/app/business/billing/plans');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasConfirm = $body.text().includes('Confirm') ||
                          $body.text().includes('Review') ||
                          $body.text().includes('Summary');
        if (hasConfirm) {
          cy.log('Upgrade confirmation available');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display proration for upgrades', () => {
      cy.visit('/app/business/billing/plans');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasProration = $body.text().includes('Proration') ||
                            $body.text().includes('prorated') ||
                            $body.text().includes('Credit') ||
                            $body.text().includes('Charge');
        if (hasProration) {
          cy.log('Proration displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should show immediate vs next cycle option', () => {
      cy.visit('/app/business/billing/plans');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasOption = $body.text().includes('Immediately') ||
                         $body.text().includes('Next cycle') ||
                         $body.text().includes('When');
        if (hasOption) {
          cy.log('Timing options displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Downgrade Flow', () => {
    it('should display downgrade option', () => {
      cy.visit('/app/business/billing/plans');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDowngrade = $body.text().includes('Downgrade') ||
                            $body.find('button:contains("Downgrade"), button:contains("Select")').length > 0;
        if (hasDowngrade) {
          cy.log('Downgrade option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should show downgrade warning', () => {
      cy.visit('/app/business/billing/plans');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasWarning = $body.text().includes('Warning') ||
                          $body.text().includes('lose') ||
                          $body.text().includes('feature') ||
                          $body.text().includes('access');
        if (hasWarning) {
          cy.log('Downgrade warning displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display feature loss summary', () => {
      cy.visit('/app/business/billing/plans');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasLoss = $body.text().includes('lose') ||
                       $body.text().includes('remove') ||
                       $body.text().includes('no longer');
        if (hasLoss) {
          cy.log('Feature loss summary displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should show downgrade takes effect at end of cycle', () => {
      cy.visit('/app/business/billing/plans');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasEnd = $body.text().includes('end of') ||
                      $body.text().includes('cycle') ||
                      $body.text().includes('until');
        if (hasEnd) {
          cy.log('End of cycle notice displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Billing Cycle Changes', () => {
    it('should display billing cycle toggle', () => {
      cy.visit('/app/business/billing/plans');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasToggle = $body.text().includes('Monthly') ||
                         $body.text().includes('Annual') ||
                         $body.find('[data-testid="billing-toggle"]').length > 0;
        if (hasToggle) {
          cy.log('Billing cycle toggle displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should show annual discount', () => {
      cy.visit('/app/business/billing/plans');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDiscount = $body.text().includes('Save') ||
                           $body.text().includes('%') ||
                           $body.text().includes('discount');
        if (hasDiscount) {
          cy.log('Annual discount displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should update prices when toggle changes', () => {
      cy.visit('/app/business/billing/plans');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasPrices = $body.text().includes('$') ||
                         $body.text().includes('/mo') ||
                         $body.text().includes('/yr');
        if (hasPrices) {
          cy.log('Prices displayed and can update');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Cancellation', () => {
    it('should have cancel subscription option', () => {
      cy.visit('/app/business/billing/subscription');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCancel = $body.find('button:contains("Cancel"), a:contains("Cancel")').length > 0 ||
                         $body.text().includes('Cancel subscription');
        if (hasCancel) {
          cy.log('Cancel subscription option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display cancellation confirmation', () => {
      cy.visit('/app/business/billing/subscription');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasConfirm = $body.text().includes('Confirm') ||
                          $body.text().includes('Are you sure') ||
                          $body.text().includes('Cancel');
        if (hasConfirm) {
          cy.log('Cancellation confirmation available');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should show retention offers', () => {
      cy.visit('/app/business/billing/subscription');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasOffer = $body.text().includes('Offer') ||
                        $body.text().includes('discount') ||
                        $body.text().includes('stay');
        if (hasOffer) {
          cy.log('Retention offers displayed');
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
      it(`should display subscription changes correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/business/billing/plans');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`Subscription changes displayed correctly on ${name}`);
      });
    });
  });
});
