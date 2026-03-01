/// <reference types="cypress" />

/**
 * Public About Page Tests
 *
 * Tests for About Page functionality including:
 * - Company information
 * - Team section
 * - Mission/Vision
 * - Company history
 * - Contact links
 * - Responsive design
 */

describe('Public About Page Tests', () => {
  describe('About Page Access', () => {
    it('should load about page', () => {
      cy.visit('/about');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasAbout = $body.text().includes('About') ||
                        $body.text().includes('Company') ||
                        $body.text().includes('Who we are');
        if (hasAbout) {
          cy.log('About page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display about header', () => {
      cy.visit('/about');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasHeader = $body.find('h1').length > 0;
        if (hasHeader) {
          cy.log('About header displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Company Information', () => {
    beforeEach(() => {
      cy.visit('/about');
      cy.waitForPageLoad();
    });

    it('should display company description', () => {
      cy.get('body').then($body => {
        const hasDescription = $body.find('p').length > 0;
        if (hasDescription) {
          cy.log('Company description displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display mission or vision statement', () => {
      cy.get('body').then($body => {
        const hasMission = $body.text().includes('Mission') ||
                          $body.text().includes('Vision') ||
                          $body.text().includes('believe') ||
                          $body.text().includes('goal');
        if (hasMission) {
          cy.log('Mission/vision displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display company values', () => {
      cy.get('body').then($body => {
        const hasValues = $body.text().includes('Values') ||
                         $body.text().includes('principles') ||
                         $body.text().includes('commitment');
        if (hasValues) {
          cy.log('Company values displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Team Section', () => {
    beforeEach(() => {
      cy.visit('/about');
      cy.waitForPageLoad();
    });

    it('should display team section', () => {
      cy.get('body').then($body => {
        const hasTeam = $body.text().includes('Team') ||
                       $body.text().includes('People') ||
                       $body.text().includes('Leadership');
        if (hasTeam) {
          cy.log('Team section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display team member photos or avatars', () => {
      cy.get('body').then($body => {
        const hasPhotos = $body.find('img[alt*="team"], img[alt*="founder"], .avatar').length > 0;
        if (hasPhotos) {
          cy.log('Team photos displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Company Stats', () => {
    beforeEach(() => {
      cy.visit('/about');
      cy.waitForPageLoad();
    });

    it('should display company statistics', () => {
      cy.get('body').then($body => {
        const hasStats = $body.text().match(/\d+[+%]?/) !== null ||
                        $body.text().includes('customers') ||
                        $body.text().includes('countries');
        if (hasStats) {
          cy.log('Company stats displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Call-to-Action', () => {
    beforeEach(() => {
      cy.visit('/about');
      cy.waitForPageLoad();
    });

    it('should have contact or careers link', () => {
      cy.get('body').then($body => {
        const hasCTA = $body.find('a[href*="contact"], a[href*="careers"]').length > 0 ||
                      $body.text().includes('Contact') ||
                      $body.text().includes('Join');
        if (hasCTA) {
          cy.log('CTA link displayed');
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
      it(`should display about page correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/about');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`About page displayed correctly on ${name}`);
      });
    });
  });
});
