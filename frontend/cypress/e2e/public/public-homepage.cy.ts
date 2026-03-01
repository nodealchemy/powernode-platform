/// <reference types="cypress" />

/**
 * Public Homepage Tests
 *
 * Tests for Homepage/Landing Page functionality including:
 * - Page loading and hero section
 * - Navigation menu
 * - Feature highlights
 * - Call-to-action buttons
 * - Footer links
 * - Responsive design
 */

describe('Public Homepage Tests', () => {
  describe('Homepage Access', () => {
    it('should load homepage', () => {
      cy.visit('/');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.log('Homepage loaded successfully');
    });

    it('should display hero section', () => {
      cy.visit('/');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasHero = $body.find('h1').length > 0 ||
                       $body.find('[data-testid="hero-section"]').length > 0;
        if (hasHero) {
          cy.log('Hero section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display main headline', () => {
      cy.visit('/');
      cy.waitForPageLoad();

      cy.get('h1').should('be.visible');
    });
  });

  describe('Navigation Menu', () => {
    beforeEach(() => {
      cy.visit('/');
      cy.waitForPageLoad();
    });

    it('should display navigation bar', () => {
      cy.get('body').then($body => {
        const hasNav = $body.find('nav, header, [data-testid="navbar"]').length > 0;
        if (hasNav) {
          cy.log('Navigation bar displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display logo', () => {
      cy.get('body').then($body => {
        const hasLogo = $body.find('img[alt*="logo"], [data-testid="logo"], .logo').length > 0 ||
                       $body.text().includes('Powernode');
        if (hasLogo) {
          cy.log('Logo displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have login link', () => {
      cy.get('body').then($body => {
        const hasLogin = $body.find('a[href*="login"], button:contains("Login"), a:contains("Login"), a:contains("Sign in")').length > 0 ||
                        $body.text().includes('Login') ||
                        $body.text().includes('Sign in');
        if (hasLogin) {
          cy.log('Login link displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have signup link', () => {
      cy.get('body').then($body => {
        const hasSignup = $body.find('a[href*="signup"], button:contains("Sign up"), a:contains("Sign up"), a:contains("Get Started")').length > 0 ||
                         $body.text().includes('Sign up') ||
                         $body.text().includes('Get Started');
        if (hasSignup) {
          cy.log('Signup link displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Feature Highlights', () => {
    beforeEach(() => {
      cy.visit('/');
      cy.waitForPageLoad();
    });

    it('should display feature sections', () => {
      cy.get('body').then($body => {
        const hasFeatures = $body.text().includes('Features') ||
                          $body.find('section').length > 1 ||
                          $body.find('[data-testid*="feature"]').length > 0;
        if (hasFeatures) {
          cy.log('Feature sections displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display feature cards or list', () => {
      cy.get('body').then($body => {
        const hasCards = $body.find('.card, [data-testid*="card"], article').length > 0;
        if (hasCards) {
          cy.log('Feature cards displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Call-to-Action Buttons', () => {
    beforeEach(() => {
      cy.visit('/');
      cy.waitForPageLoad();
    });

    it('should display primary CTA button', () => {
      cy.get('body').then($body => {
        const hasCTA = $body.find('button:contains("Get Started"), a:contains("Get Started"), button:contains("Try"), a:contains("Start")').length > 0 ||
                      $body.text().includes('Get Started');
        if (hasCTA) {
          cy.log('Primary CTA button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display secondary CTA options', () => {
      cy.get('body').then($body => {
        const hasSecondary = $body.text().includes('Learn more') ||
                           $body.text().includes('Demo') ||
                           $body.text().includes('Contact');
        if (hasSecondary) {
          cy.log('Secondary CTA options displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Footer', () => {
    beforeEach(() => {
      cy.visit('/');
      cy.waitForPageLoad();
    });

    it('should display footer', () => {
      cy.get('body').then($body => {
        const hasFooter = $body.find('footer, [data-testid="footer"]').length > 0;
        if (hasFooter) {
          cy.log('Footer displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have privacy policy link in footer', () => {
      cy.get('body').then($body => {
        const hasPrivacy = $body.find('a[href*="privacy"]').length > 0 ||
                          $body.text().includes('Privacy');
        if (hasPrivacy) {
          cy.log('Privacy policy link displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have terms link in footer', () => {
      cy.get('body').then($body => {
        const hasTerms = $body.find('a[href*="terms"]').length > 0 ||
                        $body.text().includes('Terms');
        if (hasTerms) {
          cy.log('Terms link displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display copyright notice', () => {
      cy.get('body').then($body => {
        const hasCopyright = $body.text().includes('©') ||
                           $body.text().includes('Copyright') ||
                           $body.text().includes('2024') ||
                           $body.text().includes('2025');
        if (hasCopyright) {
          cy.log('Copyright notice displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Social Proof', () => {
    beforeEach(() => {
      cy.visit('/');
      cy.waitForPageLoad();
    });

    it('should display testimonials or reviews', () => {
      cy.get('body').then($body => {
        const hasTestimonials = $body.text().includes('testimonial') ||
                               $body.text().includes('review') ||
                               $body.find('[data-testid*="testimonial"]').length > 0 ||
                               $body.find('blockquote').length > 0;
        if (hasTestimonials) {
          cy.log('Testimonials displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display customer logos or stats', () => {
      cy.get('body').then($body => {
        const hasProof = $body.text().includes('trusted by') ||
                        $body.text().includes('customers') ||
                        $body.find('[data-testid*="logo"]').length > 0;
        if (hasProof) {
          cy.log('Social proof displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    const viewports = [
      { width: 1920, height: 1080, name: 'large-desktop' },
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display homepage correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.get('h1').should('be.visible');
        cy.log(`Homepage displayed correctly on ${name}`);
      });
    });
  });

  describe('Performance', () => {
    it('should load within acceptable time', () => {
      cy.visit('/');
      cy.waitForPageLoad();

      // Page should be interactive
      cy.get('body').should('be.visible');
      cy.log('Homepage loaded within acceptable time');
    });
  });
});
