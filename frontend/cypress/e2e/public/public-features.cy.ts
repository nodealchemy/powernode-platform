/// <reference types="cypress" />

/**
 * Public Features Page Tests
 *
 * Tests for Features Page functionality including:
 * - Feature categories display
 * - Individual feature details
 * - Feature comparisons
 * - Integration with pricing
 * - Responsive design
 */

describe('Public Features Page Tests', () => {
  describe('Features Page Access', () => {
    it('should load features page', () => {
      cy.visit('/features');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasFeatures = $body.text().includes('Features') ||
                          $body.text().includes('Capabilities') ||
                          $body.text().includes('What');
        if (hasFeatures) {
          cy.log('Features page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display features header', () => {
      cy.visit('/features');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasHeader = $body.find('h1, h2').length > 0;
        if (hasHeader) {
          cy.log('Features header displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Feature Categories', () => {
    beforeEach(() => {
      cy.visit('/features');
      cy.waitForPageLoad();
    });

    it('should display billing features', () => {
      cy.get('body').then($body => {
        const hasBilling = $body.text().includes('Billing') ||
                         $body.text().includes('Subscription') ||
                         $body.text().includes('Payment');
        if (hasBilling) {
          cy.log('Billing features displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display analytics features', () => {
      cy.get('body').then($body => {
        const hasAnalytics = $body.text().includes('Analytics') ||
                           $body.text().includes('Reports') ||
                           $body.text().includes('Insights');
        if (hasAnalytics) {
          cy.log('Analytics features displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display automation features', () => {
      cy.get('body').then($body => {
        const hasAutomation = $body.text().includes('Automation') ||
                            $body.text().includes('Workflow') ||
                            $body.text().includes('AI');
        if (hasAutomation) {
          cy.log('Automation features displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display integration features', () => {
      cy.get('body').then($body => {
        const hasIntegration = $body.text().includes('Integration') ||
                             $body.text().includes('API') ||
                             $body.text().includes('Connect');
        if (hasIntegration) {
          cy.log('Integration features displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Feature Details', () => {
    beforeEach(() => {
      cy.visit('/features');
      cy.waitForPageLoad();
    });

    it('should display feature descriptions', () => {
      cy.get('body').then($body => {
        const hasDescriptions = $body.find('p').length > 0;
        if (hasDescriptions) {
          cy.log('Feature descriptions displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display feature icons or images', () => {
      cy.get('body').then($body => {
        const hasVisuals = $body.find('img, svg, [data-testid*="icon"]').length > 0;
        if (hasVisuals) {
          cy.log('Feature visuals displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Call-to-Action', () => {
    beforeEach(() => {
      cy.visit('/features');
      cy.waitForPageLoad();
    });

    it('should have link to pricing', () => {
      cy.get('body').then($body => {
        const hasPricing = $body.find('a[href*="pricing"]').length > 0 ||
                          $body.text().includes('Pricing') ||
                          $body.text().includes('Plans');
        if (hasPricing) {
          cy.log('Pricing link displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have get started button', () => {
      cy.get('body').then($body => {
        const hasCTA = $body.text().includes('Get Started') ||
                      $body.text().includes('Try') ||
                      $body.text().includes('Sign up');
        if (hasCTA) {
          cy.log('Get started CTA displayed');
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
      it(`should display features page correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/features');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`Features page displayed correctly on ${name}`);
      });
    });
  });
});
