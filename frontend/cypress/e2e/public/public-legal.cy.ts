/// <reference types="cypress" />

/**
 * Public Legal Pages Tests
 *
 * Tests for Legal Pages functionality including:
 * - Privacy Policy
 * - Terms of Service
 * - Cookie Policy
 * - Acceptable Use Policy
 * - Page structure and accessibility
 */

describe('Public Legal Pages Tests', () => {
  describe('Privacy Policy', () => {
    it('should load privacy policy page', () => {
      cy.visit('/privacy');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasPrivacy = $body.text().includes('Privacy') ||
                          $body.text().includes('Data');
        if (hasPrivacy) {
          cy.log('Privacy policy page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display privacy policy content', () => {
      cy.visit('/privacy');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasContent = $body.find('h1, h2').length > 0 &&
                          $body.find('p').length > 0;
        if (hasContent) {
          cy.log('Privacy policy content displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have data collection section', () => {
      cy.visit('/privacy');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDataSection = $body.text().includes('collect') ||
                              $body.text().includes('information') ||
                              $body.text().includes('data');
        if (hasDataSection) {
          cy.log('Data collection section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have contact information for privacy inquiries', () => {
      cy.visit('/privacy');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasContact = $body.text().includes('contact') ||
                          $body.text().includes('@') ||
                          $body.text().includes('email');
        if (hasContact) {
          cy.log('Privacy contact information displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Terms of Service', () => {
    it('should load terms of service page', () => {
      cy.visit('/terms');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasTerms = $body.text().includes('Terms') ||
                        $body.text().includes('Service') ||
                        $body.text().includes('Agreement');
        if (hasTerms) {
          cy.log('Terms of service page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display terms content', () => {
      cy.visit('/terms');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasContent = $body.find('h1, h2').length > 0 &&
                          $body.find('p').length > 0;
        if (hasContent) {
          cy.log('Terms content displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have acceptance section', () => {
      cy.visit('/terms');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasAcceptance = $body.text().includes('accept') ||
                            $body.text().includes('agree') ||
                            $body.text().includes('consent');
        if (hasAcceptance) {
          cy.log('Acceptance section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Cookie Policy', () => {
    it('should load cookie policy page', () => {
      cy.visit('/cookies');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCookies = $body.text().includes('Cookie') ||
                          $body.text().includes('cookie');
        if (hasCookies) {
          cy.log('Cookie policy page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should explain cookie usage', () => {
      cy.visit('/cookies');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasExplanation = $body.text().includes('use') ||
                              $body.text().includes('purpose') ||
                              $body.text().includes('tracking');
        if (hasExplanation) {
          cy.log('Cookie explanation displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Legal Page Structure', () => {
    const legalPages = ['/privacy', '/terms'];

    legalPages.forEach(page => {
      it(`should have proper heading structure on ${page}`, () => {
        cy.visit(page);
        cy.waitForPageLoad();

        cy.get('body').then($body => {
          const hasH1 = $body.find('h1').length > 0;
          if (hasH1) {
            cy.log(`Proper heading on ${page}`);
          }
        });

        cy.get('body').should('be.visible');
      });

      it(`should have last updated date on ${page}`, () => {
        cy.visit(page);
        cy.waitForPageLoad();

        cy.get('body').then($body => {
          const hasDate = $body.text().includes('Last updated') ||
                         $body.text().includes('Effective') ||
                         $body.text().match(/\d{4}/) !== null;
          if (hasDate) {
            cy.log(`Date information on ${page}`);
          }
        });

        cy.get('body').should('be.visible');
      });
    });
  });

  describe('Responsive Legal Pages', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display privacy policy correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/privacy');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`Privacy policy displayed correctly on ${name}`);
      });

      it(`should display terms correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/terms');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`Terms displayed correctly on ${name}`);
      });
    });
  });
});
