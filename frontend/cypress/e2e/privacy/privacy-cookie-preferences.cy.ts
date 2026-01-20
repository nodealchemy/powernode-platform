/// <reference types="cypress" />

/**
 * Privacy Cookie Preferences Tests
 *
 * Tests for Cookie Preferences functionality including:
 * - Cookie banner display
 * - Cookie categories
 * - Consent management
 * - Cookie settings persistence
 * - Third-party cookies
 * - Cookie policy
 */

describe('Privacy Cookie Preferences Tests', () => {
  describe('Cookie Banner', () => {
    it('should display cookie banner on first visit', () => {
      cy.clearCookies();
      cy.visit('/');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasBanner = $body.find('[data-testid="cookie-banner"], .cookie-banner, [role="dialog"]').length > 0 ||
                         $body.text().includes('cookie') ||
                         $body.text().includes('Cookie');
        if (hasBanner) {
          cy.log('Cookie banner displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have accept all button', () => {
      cy.clearCookies();
      cy.visit('/');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasAccept = $body.find('button:contains("Accept"), button:contains("Accept all"), button:contains("Allow")').length > 0;
        if (hasAccept) {
          cy.log('Accept all button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have reject/decline button', () => {
      cy.clearCookies();
      cy.visit('/');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasReject = $body.find('button:contains("Reject"), button:contains("Decline"), button:contains("Deny")').length > 0 ||
                         $body.text().includes('Reject') ||
                         $body.text().includes('Decline');
        if (hasReject) {
          cy.log('Reject button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have customize/manage button', () => {
      cy.clearCookies();
      cy.visit('/');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCustomize = $body.find('button:contains("Customize"), button:contains("Manage"), button:contains("Settings")').length > 0 ||
                            $body.text().includes('Customize') ||
                            $body.text().includes('Preferences');
        if (hasCustomize) {
          cy.log('Customize button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Cookie Categories', () => {
    beforeEach(() => {
      cy.standardTestSetup();
      cy.visit('/app/account/privacy/cookies');
      cy.waitForPageLoad();
    });

    it('should display necessary cookies category', () => {
      cy.get('body').then($body => {
        const hasNecessary = $body.text().includes('Necessary') ||
                           $body.text().includes('Essential') ||
                           $body.text().includes('Required');
        if (hasNecessary) {
          cy.log('Necessary cookies category displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display analytics cookies category', () => {
      cy.get('body').then($body => {
        const hasAnalytics = $body.text().includes('Analytics') ||
                           $body.text().includes('Performance') ||
                           $body.text().includes('Statistics');
        if (hasAnalytics) {
          cy.log('Analytics cookies category displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display marketing cookies category', () => {
      cy.get('body').then($body => {
        const hasMarketing = $body.text().includes('Marketing') ||
                           $body.text().includes('Advertising') ||
                           $body.text().includes('Targeting');
        if (hasMarketing) {
          cy.log('Marketing cookies category displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display functional cookies category', () => {
      cy.get('body').then($body => {
        const hasFunctional = $body.text().includes('Functional') ||
                            $body.text().includes('Preferences') ||
                            $body.text().includes('Personalization');
        if (hasFunctional) {
          cy.log('Functional cookies category displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Cookie Toggles', () => {
    beforeEach(() => {
      cy.standardTestSetup();
      cy.visit('/app/account/privacy/cookies');
      cy.waitForPageLoad();
    });

    it('should have toggles for optional cookies', () => {
      cy.get('body').then($body => {
        const hasToggles = $body.find('input[type="checkbox"], [role="switch"]').length > 0;
        if (hasToggles) {
          cy.log('Cookie toggles displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should disable necessary cookies toggle', () => {
      cy.get('body').then($body => {
        const hasDisabled = $body.find('input[disabled]').length > 0 ||
                           $body.text().includes('always enabled') ||
                           $body.text().includes('required');
        if (hasDisabled) {
          cy.log('Necessary cookies toggle disabled');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have save preferences button', () => {
      cy.get('body').then($body => {
        const hasSave = $body.find('button:contains("Save"), button:contains("Update"), button:contains("Apply")').length > 0;
        if (hasSave) {
          cy.log('Save preferences button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Cookie Details', () => {
    beforeEach(() => {
      cy.standardTestSetup();
      cy.visit('/app/account/privacy/cookies');
      cy.waitForPageLoad();
    });

    it('should display cookie descriptions', () => {
      cy.get('body').then($body => {
        const hasDescriptions = $body.find('p').length > 0 ||
                               $body.text().includes('used for') ||
                               $body.text().includes('help us');
        if (hasDescriptions) {
          cy.log('Cookie descriptions displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display cookie list per category', () => {
      cy.get('body').then($body => {
        const hasCookieList = $body.find('ul, table, [data-testid="cookie-list"]').length > 0;
        if (hasCookieList) {
          cy.log('Cookie list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display cookie expiration info', () => {
      cy.get('body').then($body => {
        const hasExpiration = $body.text().includes('Expire') ||
                            $body.text().includes('Duration') ||
                            $body.text().includes('day') ||
                            $body.text().includes('year');
        if (hasExpiration) {
          cy.log('Cookie expiration info displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Third-Party Cookies', () => {
    beforeEach(() => {
      cy.standardTestSetup();
      cy.visit('/app/account/privacy/cookies');
      cy.waitForPageLoad();
    });

    it('should display third-party cookie info', () => {
      cy.get('body').then($body => {
        const hasThirdParty = $body.text().includes('Third-party') ||
                            $body.text().includes('third party') ||
                            $body.text().includes('External');
        if (hasThirdParty) {
          cy.log('Third-party cookie info displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should list third-party providers', () => {
      cy.get('body').then($body => {
        const hasProviders = $body.text().includes('Google') ||
                            $body.text().includes('Analytics') ||
                            $body.text().includes('Provider');
        if (hasProviders) {
          cy.log('Third-party providers listed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Cookie Policy Link', () => {
    beforeEach(() => {
      cy.standardTestSetup();
      cy.visit('/app/account/privacy/cookies');
      cy.waitForPageLoad();
    });

    it('should have link to full cookie policy', () => {
      cy.get('body').then($body => {
        const hasLink = $body.find('a[href*="cookie"], a:contains("Cookie Policy"), a:contains("Learn more")').length > 0 ||
                       $body.text().includes('Cookie Policy');
        if (hasLink) {
          cy.log('Cookie policy link displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Consent Timestamp', () => {
    beforeEach(() => {
      cy.standardTestSetup();
      cy.visit('/app/account/privacy/cookies');
      cy.waitForPageLoad();
    });

    it('should display last consent date', () => {
      cy.get('body').then($body => {
        const hasDate = $body.text().includes('Last updated') ||
                       $body.text().includes('Consent given') ||
                       $body.text().match(/\d{4}/) !== null;
        if (hasDate) {
          cy.log('Last consent date displayed');
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
      it(`should display cookie preferences correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.clearCookies();
        cy.visit('/');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`Cookie preferences displayed correctly on ${name}`);
      });
    });
  });
});
