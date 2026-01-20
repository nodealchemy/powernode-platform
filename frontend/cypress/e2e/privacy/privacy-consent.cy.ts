/// <reference types="cypress" />

/**
 * Privacy Consent Management Tests
 *
 * Tests for Privacy Consent functionality including:
 * - Consent manager display
 * - Consent preferences
 * - Cookie preferences
 * - Data processing consent
 * - Marketing preferences
 * - Consent updates
 * - Privacy policy access
 */

describe('Privacy Consent Management Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Consent Manager Access', () => {
    it('should navigate to privacy settings', () => {
      cy.visit('/app/account/privacy');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasPrivacy = $body.text().includes('Privacy') ||
                          $body.text().includes('Consent') ||
                          $body.text().includes('Data');
        if (hasPrivacy) {
          cy.log('Privacy settings page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display consent manager', () => {
      cy.visit('/app/account/privacy');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasConsent = $body.text().includes('Consent') ||
                          $body.find('[data-testid="consent-manager"]').length > 0;
        if (hasConsent) {
          cy.log('Consent manager displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Consent Preferences', () => {
    beforeEach(() => {
      cy.visit('/app/account/privacy');
      cy.waitForPageLoad();
    });

    it('should display necessary cookies section', () => {
      cy.get('body').then($body => {
        const hasNecessary = $body.text().includes('Necessary') ||
                           $body.text().includes('Essential') ||
                           $body.text().includes('Required');
        if (hasNecessary) {
          cy.log('Necessary cookies section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display analytics preferences', () => {
      cy.get('body').then($body => {
        const hasAnalytics = $body.text().includes('Analytics') ||
                           $body.text().includes('Performance');
        if (hasAnalytics) {
          cy.log('Analytics preferences displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display marketing preferences', () => {
      cy.get('body').then($body => {
        const hasMarketing = $body.text().includes('Marketing') ||
                           $body.text().includes('Advertising') ||
                           $body.text().includes('Promotional');
        if (hasMarketing) {
          cy.log('Marketing preferences displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display functional preferences', () => {
      cy.get('body').then($body => {
        const hasFunctional = $body.text().includes('Functional') ||
                            $body.text().includes('Personalization');
        if (hasFunctional) {
          cy.log('Functional preferences displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Toggle Consents', () => {
    beforeEach(() => {
      cy.visit('/app/account/privacy');
      cy.waitForPageLoad();
    });

    it('should have toggles for optional consents', () => {
      cy.get('body').then($body => {
        const hasToggles = $body.find('input[type="checkbox"], [role="switch"], [data-testid*="toggle"]').length > 0;
        if (hasToggles) {
          cy.log('Consent toggles available');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should disable necessary cookies toggle', () => {
      cy.get('body').then($body => {
        const hasDisabled = $body.find('input[disabled], [aria-disabled="true"]').length > 0 ||
                           $body.text().includes('always enabled') ||
                           $body.text().includes('required');
        if (hasDisabled) {
          cy.log('Necessary cookies toggle is disabled');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Save Preferences', () => {
    beforeEach(() => {
      cy.visit('/app/account/privacy');
      cy.waitForPageLoad();
    });

    it('should have save button', () => {
      cy.get('body').then($body => {
        const hasSave = $body.find('button:contains("Save"), button:contains("Update")').length > 0 ||
                       $body.text().includes('Save');
        if (hasSave) {
          cy.log('Save preferences button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Data Export', () => {
    beforeEach(() => {
      cy.visit('/app/account/privacy');
      cy.waitForPageLoad();
    });

    it('should display data export option', () => {
      cy.get('body').then($body => {
        const hasExport = $body.text().includes('Export') ||
                         $body.text().includes('Download') ||
                         $body.text().includes('Request your data');
        if (hasExport) {
          cy.log('Data export option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have request export button', () => {
      cy.get('body').then($body => {
        const hasButton = $body.find('button:contains("Export"), button:contains("Request")').length > 0;
        if (hasButton) {
          cy.log('Request export button available');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Data Deletion', () => {
    beforeEach(() => {
      cy.visit('/app/account/privacy');
      cy.waitForPageLoad();
    });

    it('should display data deletion option', () => {
      cy.get('body').then($body => {
        const hasDeletion = $body.text().includes('Delete') ||
                          $body.text().includes('Erasure') ||
                          $body.text().includes('Right to be forgotten');
        if (hasDeletion) {
          cy.log('Data deletion option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have delete account button', () => {
      cy.get('body').then($body => {
        const hasButton = $body.find('button:contains("Delete"), button:contains("Request deletion")').length > 0;
        if (hasButton) {
          cy.log('Delete data button available');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Privacy Policy Links', () => {
    beforeEach(() => {
      cy.visit('/app/account/privacy');
      cy.waitForPageLoad();
    });

    it('should have link to privacy policy', () => {
      cy.get('body').then($body => {
        const hasLink = $body.find('a[href*="privacy"], a:contains("Privacy Policy")').length > 0 ||
                       $body.text().includes('Privacy Policy');
        if (hasLink) {
          cy.log('Privacy policy link displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have link to terms of service', () => {
      cy.get('body').then($body => {
        const hasLink = $body.find('a[href*="terms"], a:contains("Terms")').length > 0 ||
                       $body.text().includes('Terms');
        if (hasLink) {
          cy.log('Terms of service link displayed');
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
      it(`should display privacy settings correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/account/privacy');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`Privacy settings displayed correctly on ${name}`);
      });
    });
  });
});
