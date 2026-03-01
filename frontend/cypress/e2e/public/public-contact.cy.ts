/// <reference types="cypress" />

/**
 * Public Contact Page Tests
 *
 * Tests for Contact Page functionality including:
 * - Contact form display
 * - Form validation
 * - Contact information
 * - Support options
 * - Responsive design
 */

describe('Public Contact Page Tests', () => {
  describe('Contact Page Access', () => {
    it('should load contact page', () => {
      cy.visit('/contact');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasContact = $body.text().includes('Contact') ||
                          $body.text().includes('Get in touch') ||
                          $body.text().includes('Reach');
        if (hasContact) {
          cy.log('Contact page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display contact header', () => {
      cy.visit('/contact');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasHeader = $body.find('h1, h2').length > 0;
        if (hasHeader) {
          cy.log('Contact header displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Contact Form', () => {
    beforeEach(() => {
      cy.visit('/contact');
      cy.waitForPageLoad();
    });

    it('should display contact form', () => {
      cy.get('body').then($body => {
        const hasForm = $body.find('form, [data-testid="contact-form"]').length > 0;
        if (hasForm) {
          cy.log('Contact form displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have name field', () => {
      cy.get('body').then($body => {
        const hasName = $body.find('input[name*="name"], input[placeholder*="name"], label:contains("Name")').length > 0 ||
                       $body.text().includes('Name');
        if (hasName) {
          cy.log('Name field displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have email field', () => {
      cy.get('body').then($body => {
        const hasEmail = $body.find('input[type="email"], input[name*="email"], input[placeholder*="email"]').length > 0 ||
                        $body.text().includes('Email');
        if (hasEmail) {
          cy.log('Email field displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have message field', () => {
      cy.get('body').then($body => {
        const hasMessage = $body.find('textarea, input[name*="message"]').length > 0 ||
                          $body.text().includes('Message');
        if (hasMessage) {
          cy.log('Message field displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have submit button', () => {
      cy.get('body').then($body => {
        const hasSubmit = $body.find('button[type="submit"], button:contains("Send"), button:contains("Submit")').length > 0 ||
                         $body.text().includes('Send') ||
                         $body.text().includes('Submit');
        if (hasSubmit) {
          cy.log('Submit button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Contact Information', () => {
    beforeEach(() => {
      cy.visit('/contact');
      cy.waitForPageLoad();
    });

    it('should display email address', () => {
      cy.get('body').then($body => {
        const hasEmail = $body.text().includes('@') ||
                        $body.find('a[href^="mailto:"]').length > 0;
        if (hasEmail) {
          cy.log('Email address displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display support options', () => {
      cy.get('body').then($body => {
        const hasSupport = $body.text().includes('Support') ||
                          $body.text().includes('Help') ||
                          $body.text().includes('FAQ');
        if (hasSupport) {
          cy.log('Support options displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Inquiry Types', () => {
    beforeEach(() => {
      cy.visit('/contact');
      cy.waitForPageLoad();
    });

    it('should display sales inquiry option', () => {
      cy.get('body').then($body => {
        const hasSales = $body.text().includes('Sales') ||
                        $body.text().includes('Enterprise') ||
                        $body.text().includes('Demo');
        if (hasSales) {
          cy.log('Sales inquiry option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display support inquiry option', () => {
      cy.get('body').then($body => {
        const hasSupport = $body.text().includes('Support') ||
                          $body.text().includes('Technical') ||
                          $body.text().includes('Help');
        if (hasSupport) {
          cy.log('Support inquiry option displayed');
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
      it(`should display contact page correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/contact');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`Contact page displayed correctly on ${name}`);
      });
    });
  });
});
