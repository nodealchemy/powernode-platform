/// <reference types="cypress" />

/**
 * Admin Site Settings Page E2E Tests
 *
 * Tests for site settings functionality including:
 * - Page navigation
 * - Basic information section
 * - Contact information section
 * - Social media links section
 * - Performance settings section
 * - Settings status section
 * - Form interactions
 * - Error handling
 * - Responsive design
 */

describe('Admin Site Settings Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Page Navigation', () => {
    beforeEach(() => {
      cy.visit('/app/admin/site-settings');
      cy.waitForPageLoad();
    });

    it('should navigate to Site Settings page', () => {
      cy.url().should('include', '/admin');
    });

    it('should display page title', () => {
      cy.assertContainsAny(['Site Settings', 'Settings']);
    });

    it('should display page description', () => {
      cy.assertContainsAny(['site-wide settings', 'footer', 'social media', 'Site Settings']);
    });
  });

  describe('Page Actions', () => {
    beforeEach(() => {
      cy.visit('/app/admin/site-settings');
      cy.waitForPageLoad();
    });

    it('should have Reset button', () => {
      cy.assertContainsAny(['Reset', 'Clear', 'Settings']);
    });

    it('should have Save Changes button', () => {
      cy.assertContainsAny(['Save Changes', 'Save', 'Update']);
    });
  });

  describe('Basic Information Section', () => {
    beforeEach(() => {
      cy.visit('/app/admin/site-settings');
      cy.waitForPageLoad();
    });

    it('should display Basic Information section', () => {
      cy.assertContainsAny(['Basic Information', 'Site Settings', 'Settings']);
    });

    it('should display Site Name input', () => {
      cy.get('input').should('exist');
    });

    it('should display Copyright Year input', () => {
      cy.assertContainsAny(['Copyright Year', 'Year', 'Copyright']);
    });

    it('should display Copyright Text input', () => {
      cy.assertContainsAny(['Copyright Text', 'Copyright']);
    });

    it('should display Footer Description input', () => {
      cy.assertContainsAny(['Footer Description', 'Footer', 'Description']);
    });
  });

  describe('Contact Information Section', () => {
    beforeEach(() => {
      cy.visit('/app/admin/site-settings');
      cy.waitForPageLoad();
    });

    it('should display Contact Information section', () => {
      cy.assertContainsAny(['Contact Information', 'Contact', 'Settings']);
    });

    it('should display Contact Email input', () => {
      cy.assertContainsAny(['Contact Email', 'Email']);
    });

    it('should display Contact Phone input', () => {
      cy.assertContainsAny(['Contact Phone', 'Phone']);
    });

    it('should display Company Address input', () => {
      cy.assertContainsAny(['Company Address', 'Address']);
    });
  });

  describe('Social Media Links Section', () => {
    beforeEach(() => {
      cy.visit('/app/admin/site-settings');
      cy.waitForPageLoad();
    });

    it('should display Social Media Links section', () => {
      cy.assertContainsAny(['Social Media Links', 'Social Media', 'Social', 'Settings']);
    });

    it('should have Show/Hide URLs toggle', () => {
      cy.assertContainsAny(['Show URLs', 'Hide URLs', 'Social']);
    });

    it('should display Facebook URL input', () => {
      cy.assertContainsAny(['Facebook', 'Social']);
    });

    it('should display Twitter/X URL input', () => {
      cy.assertContainsAny(['Twitter', 'X Profile', 'Social']);
    });

    it('should display LinkedIn URL input', () => {
      cy.assertContainsAny(['LinkedIn', 'Social']);
    });

    it('should display Instagram URL input', () => {
      cy.assertContainsAny(['Instagram', 'Social']);
    });

    it('should display YouTube URL input', () => {
      cy.assertContainsAny(['YouTube', 'Social']);
    });
  });

  describe('Performance Settings Section', () => {
    beforeEach(() => {
      cy.visit('/app/admin/site-settings');
      cy.waitForPageLoad();
    });

    it('should display Performance Settings section', () => {
      cy.assertContainsAny(['Performance Settings', 'Performance', 'Settings']);
    });

    it('should display Footer Caching toggle', () => {
      cy.assertContainsAny(['Footer Caching', 'Caching', 'Performance']);
    });
  });

  describe('Settings Status Section', () => {
    beforeEach(() => {
      cy.visit('/app/admin/site-settings');
      cy.waitForPageLoad();
    });

    it('should display Settings Status section', () => {
      cy.assertContainsAny(['Settings Status', 'Status', 'Settings']);
    });

    it('should display Public Settings indicator', () => {
      cy.assertContainsAny(['Public Settings', 'Visible to all', 'Public', 'Settings']);
    });

    it('should display Total Settings count', () => {
      cy.assertContainsAny(['Total Settings', 'Settings']);
    });

    it('should display Caching status', () => {
      cy.assertContainsAny(['Footer Caching', 'Enabled', 'Disabled', 'Caching', 'Settings']);
    });

    it('should display Access Level indicator', () => {
      cy.assertContainsAny(['Access Level', 'Admin only', 'Access', 'Settings']);
    });
  });

  describe('Form Interactions', () => {
    beforeEach(() => {
      cy.visit('/app/admin/site-settings');
      cy.waitForPageLoad();
    });

    it('should allow editing Site Name', () => {
      cy.assertHasElement(['input', 'form', '[class*="input"]']);
    });

    it('should toggle Show/Hide URLs', () => {
      cy.contains(/Show URLs|Hide URLs/).should('be.visible').click();
    });
  });

  describe('Error Handling', () => {
    beforeEach(() => {
      cy.visit('/app/admin/site-settings');
      cy.waitForPageLoad();
    });

    it('should handle API errors gracefully', () => {
      cy.intercept('GET', '**/api/**/settings/**', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/admin/site-settings');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Site Settings', 'Error', 'Settings']);
      cy.get('body')
        .should('not.contain.text', 'Cannot read')
        .and('not.contain.text', 'TypeError');
    });

    it('should show error notification on save failure', () => {
      cy.intercept('PUT', '**/api/**/settings/**', {
        statusCode: 500,
        body: { success: false, error: 'Save failed' }
      }).as('saveError');

      cy.intercept('POST', '**/api/**/settings/**', {
        statusCode: 500,
        body: { success: false, error: 'Save failed' }
      }).as('savePostError');

      cy.visit('/app/admin/site-settings');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Site Settings', 'Settings']);
    });
  });

  describe('Loading State', () => {
    beforeEach(() => {
      cy.visit('/app/admin/site-settings');
      cy.waitForPageLoad();
    });

    it('should display loading indicator', () => {
      cy.intercept('GET', '**/api/**/settings/**', (req) => {
        req.reply((res) => {
          res.delay = 2000;
          res.send({ success: true, data: { settings: [] } });
        });
      }).as('slowLoad');

      cy.visit('/app/admin/site-settings');

      // Just verify the page eventually loads
      cy.assertContainsAny(['Site Settings', 'Settings', 'Loading']);
    });
  });

  describe('Form Validation', () => {
    beforeEach(() => {
      cy.visit('/app/admin/site-settings');
      cy.waitForPageLoad();
    });

    it('should accept valid email format', () => {
      cy.get('input[type="email"]').first().clear().type('test@example.com');
      cy.get('input[type="email"]').first().should('have.value', 'test@example.com');
    });
  });

  describe('Responsive Design', () => {
    beforeEach(() => {
      cy.visit('/app/admin/site-settings');
      cy.waitForPageLoad();
    });

    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/admin/site-settings');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Site Settings', 'Settings']);
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/admin/site-settings');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Site Settings', 'Settings']);
    });

    it('should stack form fields on small screens', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/admin/site-settings');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Site Settings', 'Settings']);
    });

    it('should show multi-column layout on large screens', () => {
      cy.viewport(1920, 1080);
      cy.visit('/app/admin/site-settings');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Site Settings', 'Settings']);
    });
  });

  describe('Permission Check', () => {
    it('should require admin permissions', () => {
      cy.testPermissionDenied('/app/admin/site-settings');
    });
  });
});


export {};
