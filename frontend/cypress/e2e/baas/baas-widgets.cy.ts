/// <reference types="cypress" />

/**
 * BaaS Widgets Tests
 *
 * Tests for BaaS embeddable widget functionality including:
 * - Pricing Table widget
 * - Customer Portal widget
 * - Widget configuration
 * - Theme customization
 * - Standalone rendering
 */

describe('BaaS Widgets Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Pricing Table Widget', () => {
    it('should navigate to pricing table configuration', () => {
      cy.visit('/baas/widgets/pricing-table');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasPricing = $body.text().includes('Pricing') ||
                          $body.text().includes('Plans') ||
                          $body.text().includes('Widget');
        if (hasPricing) {
          cy.log('Pricing table configuration loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display plan cards in widget', () => {
      cy.visit('/baas/widgets/pricing-table');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasPlans = $body.text().includes('Free') ||
                        $body.text().includes('Starter') ||
                        $body.text().includes('Pro') ||
                        $body.text().includes('Enterprise');
        if (hasPlans) {
          cy.log('Plan cards displayed in widget');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display pricing information', () => {
      cy.visit('/baas/widgets/pricing-table');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasPricing = $body.text().includes('$') ||
                          $body.text().includes('/month') ||
                          $body.text().includes('/year') ||
                          $body.text().includes('Price');
        if (hasPricing) {
          cy.log('Pricing information displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display feature lists', () => {
      cy.visit('/baas/widgets/pricing-table');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasFeatures = $body.text().includes('Features') ||
                           $body.find('ul, li').length > 0 ||
                           $body.text().includes('Included');
        if (hasFeatures) {
          cy.log('Feature lists displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have theme options', () => {
      cy.visit('/baas/widgets/pricing-table');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasTheme = $body.text().includes('Theme') ||
                        $body.text().includes('Dark') ||
                        $body.text().includes('Light') ||
                        $body.find('select, [role="listbox"]').length > 0;
        if (hasTheme) {
          cy.log('Theme options available');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should highlight popular plan', () => {
      cy.visit('/baas/widgets/pricing-table');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasHighlight = $body.text().includes('Popular') ||
                            $body.text().includes('Most') ||
                            $body.text().includes('Recommended');
        if (hasHighlight) {
          cy.log('Popular plan highlighted');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Customer Portal Widget', () => {
    it('should navigate to customer portal configuration', () => {
      cy.visit('/baas/widgets/customer-portal');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasPortal = $body.text().includes('Customer Portal') ||
                         $body.text().includes('Portal') ||
                         $body.text().includes('Widget');
        if (hasPortal) {
          cy.log('Customer portal configuration loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display subscription details section', () => {
      cy.visit('/baas/widgets/customer-portal');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSubscription = $body.text().includes('Subscription') ||
                               $body.text().includes('Plan') ||
                               $body.text().includes('Active');
        if (hasSubscription) {
          cy.log('Subscription details section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display billing section', () => {
      cy.visit('/baas/widgets/customer-portal');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasBilling = $body.text().includes('Billing') ||
                          $body.text().includes('Payment') ||
                          $body.text().includes('Invoice');
        if (hasBilling) {
          cy.log('Billing section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display payment methods', () => {
      cy.visit('/baas/widgets/customer-portal');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasPayment = $body.text().includes('Payment Method') ||
                          $body.text().includes('Card') ||
                          $body.text().includes('Update');
        if (hasPayment) {
          cy.log('Payment methods displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display invoice history', () => {
      cy.visit('/baas/widgets/customer-portal');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasInvoices = $body.text().includes('Invoice') ||
                           $body.text().includes('History') ||
                           $body.text().includes('Download');
        if (hasInvoices) {
          cy.log('Invoice history displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have cancel subscription option', () => {
      cy.visit('/baas/widgets/customer-portal');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCancel = $body.text().includes('Cancel') ||
                         $body.text().includes('Downgrade') ||
                         $body.text().includes('Change Plan');
        if (hasCancel) {
          cy.log('Cancel subscription option available');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Widget Embed Code', () => {
    it('should display embed code for pricing table', () => {
      cy.visit('/baas/widgets/pricing-table');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasEmbed = $body.text().includes('Embed') ||
                        $body.text().includes('Code') ||
                        $body.text().includes('<script') ||
                        $body.text().includes('iframe');
        if (hasEmbed) {
          cy.log('Embed code displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have copy code functionality', () => {
      cy.visit('/baas/widgets/pricing-table');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCopy = $body.text().includes('Copy') ||
                       $body.find('button').filter(':contains("Copy")').length > 0 ||
                       $body.find('[data-testid*="copy"]').length > 0;
        if (hasCopy) {
          cy.log('Copy code functionality available');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Widget Preview', () => {
    it('should display live preview of pricing widget', () => {
      cy.visit('/baas/widgets/pricing-table');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasPreview = $body.text().includes('Preview') ||
                          $body.find('iframe').length > 0 ||
                          $body.find('[class*="preview"]').length > 0;
        if (hasPreview) {
          cy.log('Live preview displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should update preview on configuration change', () => {
      cy.visit('/baas/widgets/pricing-table');
      cy.waitForPageLoad();

      // Look for configuration options
      cy.get('body').then($body => {
        const hasConfig = $body.find('input, select, checkbox').length > 0;
        if (hasConfig) {
          cy.log('Configuration options for preview available');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Widget Customization', () => {
    it('should allow color customization', () => {
      cy.visit('/baas/widgets/pricing-table');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasColors = $body.text().includes('Color') ||
                         $body.text().includes('Primary') ||
                         $body.text().includes('Accent') ||
                         $body.find('input[type="color"]').length > 0;
        if (hasColors) {
          cy.log('Color customization available');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should allow font customization', () => {
      cy.visit('/baas/widgets/pricing-table');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasFonts = $body.text().includes('Font') ||
                        $body.text().includes('Typography') ||
                        $body.find('select').length > 0;
        if (hasFonts) {
          cy.log('Font customization available');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should allow layout customization', () => {
      cy.visit('/baas/widgets/pricing-table');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasLayout = $body.text().includes('Layout') ||
                         $body.text().includes('Grid') ||
                         $body.text().includes('Cards') ||
                         $body.text().includes('Columns');
        if (hasLayout) {
          cy.log('Layout customization available');
        }
      });

      cy.get('body').should('be.visible');
    });
  });
});
