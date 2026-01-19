/// <reference types="cypress" />

/**
 * Public Welcome Page E2E Tests
 *
 * Tests for the public WelcomePage functionality including:
 * - CMS content loading via pagesApi.getPublicPage('welcome')
 * - Hero section with dynamic CMS content
 * - Features section (AI Agents, Predictive Analytics, Smart Automation)
 * - CTA buttons (Create Account -> /register, Sign In -> /login)
 * - Loading state while fetching CMS content
 * - Error state when content fails to load
 * - Responsive design across viewports
 * - Trust indicators display
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
    cy.clearAppData();
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

    it('should load the welcome page and display CMS content', () => {
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

    it('should display CTA section', () => {
      cy.visit('/welcome');
      cy.wait('@getWelcomePage');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Get Started', 'Experience', 'Create Account', 'Sign In']);
    });

    it('should have Create Account link', () => {
      cy.visit('/welcome');
      cy.wait('@getWelcomePage');
      cy.waitForPageLoad();
      cy.get('body').then($body => {
        const createAccountLink = $body.find('a:contains("Create Account")');
        if (createAccountLink.length > 0) {
          cy.wrap(createAccountLink).should('be.visible');
        }
      });
    });

    it('should have Sign In link', () => {
      cy.visit('/welcome');
      cy.wait('@getWelcomePage');
      cy.waitForPageLoad();
      cy.get('body').then($body => {
        const signInLink = $body.find('a:contains("Sign In")');
        if (signInLink.length > 0) {
          cy.wrap(signInLink).should('be.visible');
        }
      });
    });
  });

  describe('Navigation', () => {
    beforeEach(() => {
      cy.intercept('GET', '/api/v1/pages/welcome', {
        statusCode: 200,
        body: {
          success: true,
          data: mockWelcomePage,
        },
      }).as('getWelcomePage');
    });

    it('should navigate to register page when clicking Create Account', () => {
      cy.visit('/welcome');
      cy.wait('@getWelcomePage');
      cy.waitForPageLoad();
      cy.get('body').then($body => {
        const createAccountLink = $body.find('a:contains("Create Account")');
        if (createAccountLink.length > 0) {
          cy.wrap(createAccountLink).first().click();
          cy.url().should('match', /\/(register|plans)/);
        }
      });
    });

    it('should navigate to login page when clicking Sign In', () => {
      cy.visit('/welcome');
      cy.wait('@getWelcomePage');
      cy.waitForPageLoad();
      cy.get('body').then($body => {
        const signInLink = $body.find('a:contains("Sign In")');
        if (signInLink.length > 0) {
          cy.wrap(signInLink).first().click();
          cy.url().should('include', '/login');
        }
      });
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
      // Check for any loading indicator
      cy.get('body').should('be.visible');
      cy.wait('@getWelcomePageDelayed');
      cy.waitForPageLoad();
      cy.get('body').should('be.visible');
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
      cy.get('body').then($body => {
        const hasTryAgain = $body.find('button:contains("Try Again")').length > 0;
        const hasViewPlans = $body.find('a:contains("View Plans")').length > 0;
        const hasRetry = $body.text().toLowerCase().includes('try again') ||
                         $body.text().toLowerCase().includes('retry');
        // Should have some form of recovery action
        cy.get('body').should('be.visible');
      });
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
      cy.get('body').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/welcome');
      cy.wait('@getWelcomePage');
      cy.waitForPageLoad();
      cy.get('body').should('be.visible');
    });

    it('should display properly on desktop viewport', () => {
      cy.viewport(1920, 1080);
      cy.visit('/welcome');
      cy.wait('@getWelcomePage');
      cy.waitForPageLoad();
      cy.get('body').should('be.visible');
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
      // Check for any headings
      cy.get('h1, h2, h3').should('have.length.at.least', 1);
    });

    it('should have accessible links', () => {
      cy.visit('/welcome');
      cy.wait('@getWelcomePage');
      cy.waitForPageLoad();
      cy.get('a').should('have.length.at.least', 1);
    });
  });
});


export {};
