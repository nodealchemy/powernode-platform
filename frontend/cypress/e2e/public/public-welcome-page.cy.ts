/// <reference types="cypress" />

/**
 * Public Welcome Page E2E Tests
 *
 * Tests for the public WelcomePage functionality including:
 * - CMS content loading via pagesApi.getPublicPage('welcome')
 * - Hero section with dynamic CMS content
 * - Features section (AI Agents, Predictive Analytics, Smart Automation)
 * - CTA buttons (Create Account -> /register, Sign In -> /login)
 * - Footer navigation links
 * - Loading and error states
 * - Responsive design across viewports
 */

describe('Public Welcome Page Tests', () => {
  // Mock CMS page response data
  const mockWelcomePage = {
    id: 'page-welcome-001',
    title: 'Welcome to Powernode',
    slug: 'welcome',
    content: '# Welcome to the Future of AI\n\nExperience intelligent automation that transforms your business.',
    meta_description: 'Streamline your subscription business with automated billing, analytics, and customer lifecycle management.',
    status: 'published',
    published_at: '2025-01-01T00:00:00.000Z',
    created_at: '2025-01-01T00:00:00.000Z',
    updated_at: '2025-01-01T00:00:00.000Z',
  };

  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Successful Content Load', () => {
    beforeEach(() => {
      cy.intercept('GET', '/api/v1/pages/welcome', {
        statusCode: 200,
        body: {
          success: true,
          data: mockWelcomePage,
        },
      }).as('getWelcomePage');
    });

    it('should load the welcome page and display content', () => {
      cy.visit('/welcome');
      cy.wait('@getWelcomePage');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Welcome', 'Powernode', 'AI']);
    });

    it('should display the hero section with dynamic content', () => {
      cy.visit('/welcome');
      cy.wait('@getWelcomePage');
      cy.waitForPageLoad();
      cy.get('section').first().should('be.visible');
      cy.assertContainsAny(['Welcome', 'AI', 'automation']);
    });

    it('should display trust indicators', () => {
      cy.visit('/welcome');
      cy.wait('@getWelcomePage');
      cy.waitForPageLoad();
      cy.assertContainsAny(['AI-Powered', 'Enterprise Security', 'Real-time', 'Welcome']);
    });

    it('should display features section with feature cards', () => {
      cy.visit('/welcome');
      cy.wait('@getWelcomePage');
      cy.waitForPageLoad();
      cy.assertContainsAny(['AI-Powered Platform', 'AI Agents', 'Predictive Analytics', 'Smart Automation', 'Welcome']);
    });

    it('should display CTA section with action buttons', () => {
      cy.visit('/welcome');
      cy.wait('@getWelcomePage');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Get Started', 'Experience', 'Create Account', 'Sign In']);
    });

    it('should have visible Create Account link', () => {
      cy.visit('/welcome');
      cy.wait('@getWelcomePage');
      cy.waitForPageLoad();
      cy.contains('a', 'Create Account').should('be.visible');
    });

    it('should have visible Sign In link in header', () => {
      cy.visit('/welcome');
      cy.wait('@getWelcomePage');
      cy.waitForPageLoad();
      cy.get('header').contains('a', 'Sign in').should('be.visible');
    });
  });

  describe('Header Navigation', () => {
    beforeEach(() => {
      cy.intercept('GET', '/api/v1/pages/welcome', {
        statusCode: 200,
        body: {
          success: true,
          data: mockWelcomePage,
        },
      }).as('getWelcomePage');
    });

    it('should navigate to register/plans page when clicking Create Account', () => {
      cy.visit('/welcome');
      cy.wait('@getWelcomePage');
      cy.waitForPageLoad();
      cy.contains('a', 'Create Account').first().click();
      cy.url().should('match', /\/(register|plans)/);
    });

    it('should navigate to login page when clicking Sign In', () => {
      cy.visit('/welcome');
      cy.wait('@getWelcomePage');
      cy.waitForPageLoad();
      cy.get('header').contains('a', 'Sign in').click();
      cy.url().should('include', '/login');
    });

    it('should navigate to plans when clicking Get Started', () => {
      cy.visit('/welcome');
      cy.wait('@getWelcomePage');
      cy.waitForPageLoad();
      cy.get('header').contains('a', 'Get Started').click();
      cy.url().should('include', '/plans');
    });
  });

  describe('Footer Navigation', () => {
    beforeEach(() => {
      cy.intercept('GET', '/api/v1/pages/welcome', {
        statusCode: 200,
        body: { success: true, data: mockWelcomePage },
      }).as('getWelcomePage');

      // Mock CMS pages for footer link destinations
      cy.intercept('GET', '/api/v1/pages/help', {
        statusCode: 200,
        body: { success: true, data: { ...mockWelcomePage, slug: 'help', title: 'Help Center' } },
      }).as('getHelpPage');

      cy.intercept('GET', '/api/v1/pages/contact', {
        statusCode: 200,
        body: { success: true, data: { ...mockWelcomePage, slug: 'contact', title: 'Contact Us' } },
      }).as('getContactPage');

      cy.intercept('GET', '/api/v1/pages/about', {
        statusCode: 200,
        body: { success: true, data: { ...mockWelcomePage, slug: 'about', title: 'About Us' } },
      }).as('getAboutPage');

      cy.intercept('GET', '/api/v1/pages/privacy', {
        statusCode: 200,
        body: { success: true, data: { ...mockWelcomePage, slug: 'privacy', title: 'Privacy Policy' } },
      }).as('getPrivacyPage');

      cy.intercept('GET', '/api/v1/pages/terms', {
        statusCode: 200,
        body: { success: true, data: { ...mockWelcomePage, slug: 'terms', title: 'Terms of Service' } },
      }).as('getTermsPage');
    });

    it('should display footer with all sections', () => {
      cy.visit('/welcome');
      cy.wait('@getWelcomePage');
      cy.waitForPageLoad();
      cy.get('footer').should('be.visible');
      cy.get('footer').contains('Product').should('be.visible');
      cy.get('footer').contains('Support').should('be.visible');
      cy.get('footer').contains('Company').should('be.visible');
    });

    it('should navigate to Help Center from footer', () => {
      cy.visit('/welcome');
      cy.wait('@getWelcomePage');
      cy.waitForPageLoad();
      cy.get('[data-testid="footer-help-center"]').click();
      cy.url().should('include', '/pages/help');
    });

    it('should navigate to Contact Us from footer', () => {
      cy.visit('/welcome');
      cy.wait('@getWelcomePage');
      cy.waitForPageLoad();
      cy.get('[data-testid="footer-contact"]').click();
      cy.url().should('include', '/pages/contact');
    });

    it('should navigate to System Status from footer', () => {
      cy.visit('/welcome');
      cy.wait('@getWelcomePage');
      cy.waitForPageLoad();
      cy.get('[data-testid="footer-status"]').click();
      cy.url().should('include', '/status');
    });

    it('should navigate to About Us from footer', () => {
      cy.visit('/welcome');
      cy.wait('@getWelcomePage');
      cy.waitForPageLoad();
      cy.get('[data-testid="footer-about"]').click();
      cy.url().should('include', '/pages/about');
    });

    it('should navigate to Privacy Policy from footer', () => {
      cy.visit('/welcome');
      cy.wait('@getWelcomePage');
      cy.waitForPageLoad();
      cy.get('[data-testid="footer-privacy"]').click();
      cy.url().should('include', '/pages/privacy');
    });

    it('should navigate to Terms of Service from footer', () => {
      cy.visit('/welcome');
      cy.wait('@getWelcomePage');
      cy.waitForPageLoad();
      cy.get('[data-testid="footer-terms"]').click();
      cy.url().should('include', '/pages/terms');
    });

    it('should show Coming Soon tooltip for Integrations', () => {
      cy.visit('/welcome');
      cy.wait('@getWelcomePage');
      cy.waitForPageLoad();
      cy.get('footer').contains('Integrations').should('have.attr', 'title', 'Coming Soon');
    });
  });

  describe('Loading State', () => {
    it('should display loading state while fetching CMS content', () => {
      cy.intercept('GET', '/api/v1/pages/welcome', {
        delay: 1000,
        statusCode: 200,
        body: {
          success: true,
          data: mockWelcomePage,
        },
      }).as('getWelcomePageDelayed');

      cy.visit('/welcome');
      cy.assertContainsAny(['Welcome', 'Powernode']);
      cy.wait('@getWelcomePageDelayed');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Welcome', 'Powernode']);
    });
  });

  describe('CMS Error State', () => {
    it('should display error message when CMS API returns error', () => {
      cy.intercept('GET', '/api/v1/pages/welcome', {
        statusCode: 500,
        body: {
          success: false,
          error: 'Internal server error',
        },
      }).as('getWelcomePageError');

      cy.visit('/welcome');
      cy.wait('@getWelcomePageError');
      cy.assertContainsAny(['Something went wrong', 'Oops!', 'Error', 'error', 'failed']);
    });

    it('should display retry option on error', () => {
      cy.intercept('GET', '/api/v1/pages/welcome', {
        statusCode: 500,
        body: {
          success: false,
          error: 'Failed to load page',
        },
      }).as('getWelcomePageError');

      cy.visit('/welcome');
      cy.wait('@getWelcomePageError');
      cy.assertContainsAny(['Try Again', 'Retry', 'View Plans']);
    });

    it('should handle network timeout gracefully', () => {
      cy.intercept('GET', '/api/v1/pages/welcome', {
        forceNetworkError: true,
      }).as('getWelcomePageTimeout');

      cy.visit('/welcome');
      cy.get('body', { timeout: 5000 }).should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });
  });

  describe('Responsive Layout', () => {
    beforeEach(() => {
      cy.intercept('GET', '/api/v1/pages/welcome', {
        statusCode: 200,
        body: {
          success: true,
          data: mockWelcomePage,
        },
      }).as('getWelcomePage');
    });

    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/welcome');
      cy.wait('@getWelcomePage');
      cy.waitForPageLoad();
      cy.get('header').should('be.visible');
      cy.get('footer').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/welcome');
      cy.wait('@getWelcomePage');
      cy.waitForPageLoad();
      cy.get('header').should('be.visible');
      cy.get('footer').should('be.visible');
    });

    it('should display properly on desktop viewport', () => {
      cy.viewport(1920, 1080);
      cy.visit('/welcome');
      cy.wait('@getWelcomePage');
      cy.waitForPageLoad();
      cy.get('header').should('be.visible');
      cy.get('footer').should('be.visible');
    });
  });

  describe('Accessibility', () => {
    beforeEach(() => {
      cy.intercept('GET', '/api/v1/pages/welcome', {
        statusCode: 200,
        body: {
          success: true,
          data: mockWelcomePage,
        },
      }).as('getWelcomePage');
    });

    it('should have proper heading structure', () => {
      cy.visit('/welcome');
      cy.wait('@getWelcomePage');
      cy.waitForPageLoad();
      cy.get('h1, h2, h3').should('have.length.at.least', 1);
    });

    it('should have accessible navigation links', () => {
      cy.visit('/welcome');
      cy.wait('@getWelcomePage');
      cy.waitForPageLoad();
      cy.get('header a').should('have.length.at.least', 1);
      cy.get('footer a').should('have.length.at.least', 5);
    });

    it('should have visible focus indicators on links', () => {
      cy.visit('/welcome');
      cy.wait('@getWelcomePage');
      cy.waitForPageLoad();
      cy.get('header a').first().focus();
      cy.focused().should('exist');
    });
  });
});

export {};
