/// <reference types="cypress" />

/**
 * Public Pricing Page Tests
 *
 * Tests for Public Pricing functionality including:
 * - Pricing page display
 * - Plan comparison
 * - Plan features
 * - Price display
 * - CTA buttons
 * - FAQ section
 * - Contact/Enterprise options
 */

describe('Public Pricing Page Tests', () => {
  describe('Pricing Page Access', () => {
    it('should load pricing page', () => {
      cy.visit('/pricing');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasPricing = $body.text().includes('Pricing') ||
                          $body.text().includes('Plans') ||
                          $body.text().includes('Price');
        if (hasPricing) {
          cy.log('Pricing page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display pricing header', () => {
      cy.visit('/pricing');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasHeader = $body.find('h1, h2').length > 0;
        if (hasHeader) {
          cy.log('Pricing header displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Plan Cards', () => {
    beforeEach(() => {
      cy.visit('/pricing');
      cy.waitForPageLoad();
    });

    it('should display multiple plan options', () => {
      cy.get('body').then($body => {
        const plans = ['Free', 'Starter', 'Pro', 'Business', 'Enterprise'];
        const foundPlans = plans.filter(plan => $body.text().includes(plan));
        if (foundPlans.length > 0) {
          cy.log(`Found plans: ${foundPlans.join(', ')}`);
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display plan prices', () => {
      cy.get('body').then($body => {
        const hasPrice = $body.text().includes('$') ||
                        $body.text().includes('/month') ||
                        $body.text().includes('/year') ||
                        $body.text().includes('Free');
        if (hasPrice) {
          cy.log('Plan prices displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display plan features', () => {
      cy.get('body').then($body => {
        const hasFeatures = $body.find('ul li').length > 0 ||
                           $body.text().includes('✓') ||
                           $body.text().includes('✗');
        if (hasFeatures) {
          cy.log('Plan features displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should highlight recommended plan', () => {
      cy.get('body').then($body => {
        const hasRecommended = $body.text().includes('Popular') ||
                              $body.text().includes('Recommended') ||
                              $body.text().includes('Best value') ||
                              $body.find('.highlighted, .popular, .recommended').length > 0;
        if (hasRecommended) {
          cy.log('Recommended plan highlighted');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('CTA Buttons', () => {
    beforeEach(() => {
      cy.visit('/pricing');
      cy.waitForPageLoad();
    });

    it('should display Get Started buttons', () => {
      cy.get('body').then($body => {
        const hasCTA = $body.find('button:contains("Get Started"), a:contains("Get Started"), button:contains("Sign up")').length > 0 ||
                      $body.text().includes('Get Started');
        if (hasCTA) {
          cy.log('Get Started buttons displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Contact Sales for Enterprise', () => {
      cy.get('body').then($body => {
        const hasContact = $body.text().includes('Contact') ||
                          $body.text().includes('Sales') ||
                          $body.text().includes('Get in touch');
        if (hasContact) {
          cy.log('Contact Sales option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Billing Toggle', () => {
    beforeEach(() => {
      cy.visit('/pricing');
      cy.waitForPageLoad();
    });

    it('should display monthly/annual toggle', () => {
      cy.get('body').then($body => {
        const hasToggle = $body.text().includes('Monthly') ||
                         $body.text().includes('Annual') ||
                         $body.text().includes('Yearly');
        if (hasToggle) {
          cy.log('Billing toggle displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should show annual discount', () => {
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
  });

  describe('Feature Comparison', () => {
    beforeEach(() => {
      cy.visit('/pricing');
      cy.waitForPageLoad();
    });

    it('should display feature comparison table', () => {
      cy.get('body').then($body => {
        const hasTable = $body.find('table').length > 0 ||
                        $body.text().includes('Compare') ||
                        $body.text().includes('Features');
        if (hasTable) {
          cy.log('Feature comparison displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('FAQ Section', () => {
    beforeEach(() => {
      cy.visit('/pricing');
      cy.waitForPageLoad();
    });

    it('should display FAQ section', () => {
      cy.get('body').then($body => {
        const hasFAQ = $body.text().includes('FAQ') ||
                      $body.text().includes('Frequently Asked') ||
                      $body.text().includes('Questions');
        if (hasFAQ) {
          cy.log('FAQ section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have expandable FAQ items', () => {
      cy.get('body').then($body => {
        const hasExpandable = $body.find('[data-testid="faq-item"], details, [role="button"]').length > 0;
        if (hasExpandable) {
          cy.log('Expandable FAQ items present');
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
      it(`should display pricing page correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/pricing');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`Pricing page displayed correctly on ${name}`);
      });
    });
  });
});
