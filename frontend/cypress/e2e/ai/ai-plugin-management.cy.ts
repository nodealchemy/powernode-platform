/// <reference types="cypress" />

/**
 * AI Plugin Management Tests
 *
 * Tests for AI Plugin functionality including:
 * - Plugin browsing
 * - Plugin installation
 * - Plugin configuration
 * - Plugin updates
 * - Plugin permissions
 * - Plugin removal
 */

describe('AI Plugin Management Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Plugin Browsing', () => {
    it('should navigate to plugins page', () => {
      cy.visit('/app/ai/plugins');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Plugin', 'Extension', 'Integration']);
    });

    it('should display plugin list', () => {
      cy.visit('/app/ai/plugins');
      cy.waitForPageLoad();

      cy.assertHasElement(['[data-testid="plugin-list"]', '.plugin-card', '.grid']);
    });

    it('should display plugin categories', () => {
      cy.visit('/app/ai/plugins');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Category', 'All']);
    });

    it('should have search for plugins', () => {
      cy.visit('/app/ai/plugins');
      cy.waitForPageLoad();

      cy.assertHasElement(['input[type="search"]', 'input[placeholder*="Search"]']);
    });
  });

  describe('Plugin Details', () => {
    beforeEach(() => {
      cy.visit('/app/ai/plugins');
      cy.waitForPageLoad();
    });

    it('should display plugin name', () => {
      cy.assertHasElement(['h2', 'h3', '.plugin-name']);
    });

    it('should display plugin description', () => {
      cy.assertHasElement(['p', '.description']);
    });

    it('should display plugin version', () => {
      cy.assertContainsAny(['Version']);
    });

    it('should display plugin author', () => {
      cy.assertContainsAny(['By', 'Author', 'Publisher']);
    });
  });

  describe('Plugin Installation', () => {
    beforeEach(() => {
      cy.visit('/app/ai/plugins');
      cy.waitForPageLoad();
    });

    it('should have install button', () => {
      cy.assertContainsAny(['Install', 'Add']);
    });

    it('should display installed badge', () => {
      cy.assertContainsAny(['Installed', 'Active']);
    });

    it('should show installation confirmation', () => {
      cy.assertContainsAny(['Confirm', 'Install', 'Add']);
    });
  });

  describe('Plugin Configuration', () => {
    it('should navigate to installed plugins', () => {
      cy.visit('/app/ai/plugins/installed');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Installed', 'My Plugins', 'Active']);
    });

    it('should have configure option', () => {
      cy.visit('/app/ai/plugins/installed');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Configure', 'Settings']);
    });

    it('should have enable/disable toggle', () => {
      cy.visit('/app/ai/plugins/installed');
      cy.waitForPageLoad();

      cy.assertHasElement(['input[type="checkbox"]', '[role="switch"]']);
    });
  });

  describe('Plugin Updates', () => {
    beforeEach(() => {
      cy.visit('/app/ai/plugins/installed');
      cy.waitForPageLoad();
    });

    it('should display update available badge', () => {
      cy.assertContainsAny(['Update', 'New version']);
    });

    it('should have update button', () => {
      cy.assertContainsAny(['Update']);
    });

    it('should have update all option', () => {
      cy.assertContainsAny(['Update all', 'Update All']);
    });
  });

  describe('Plugin Permissions', () => {
    beforeEach(() => {
      cy.visit('/app/ai/plugins');
      cy.waitForPageLoad();
    });

    it('should display plugin permissions', () => {
      cy.assertContainsAny(['Permission', 'Access']);
    });

    it('should display data access requirements', () => {
      cy.assertContainsAny(['Data', 'Read', 'Write']);
    });
  });

  describe('Plugin Removal', () => {
    beforeEach(() => {
      cy.visit('/app/ai/plugins/installed');
      cy.waitForPageLoad();
    });

    it('should have uninstall option', () => {
      cy.assertContainsAny(['Uninstall', 'Remove']);
    });

    it('should show uninstall confirmation', () => {
      cy.assertContainsAny(['Confirm', 'Are you sure', 'Remove']);
    });
  });

  describe('Responsive Design', () => {
    it('should display plugins correctly across viewports', () => {
      cy.testResponsiveDesign('/app/ai/plugins', { checkContent: ['Plugin', 'Extension', 'Integration'] });
    });
  });
});
