/// <reference types="cypress" />

/**
 * Template Composer Save Flow E2E
 *
 * Golden Eclipse plan M-FE-1 — Visual Template Composer.
 * Verifies the operator-driven flow:
 *   1. Visit /app/system/templates/compose
 *   2. Module catalog renders with at least one module
 *   3. Adding a module updates the composition canvas + footprint
 *   4. Save modal opens, accepts a template name, persists via the
 *      compose_preview / create_template / assign_module_to_template
 *      back-end chain
 *   5. New template appears in the list at /app/system/templates
 *
 * The test relies on existing seed data: the test account must have at
 * least one NodeModule. If the seed is empty, the test logs and skips
 * (operator-environment specs are optional, not required for CI gate).
 */

describe('Template Composer save flow', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  it('navigates to the composer and renders the page chrome', () => {
    cy.visit('/app/system/templates/compose');
    cy.waitForPageLoad();
    cy.assertContainsAny(['Template Composer', 'Module Catalog', 'Composition']);
  });

  it('shows the Save button disabled when no modules are selected', () => {
    cy.visit('/app/system/templates/compose');
    cy.waitForPageLoad();
    cy.contains('button', 'Save as Template').should('be.disabled');
  });

  it('shows compose preview update when a module is added', () => {
    cy.visit('/app/system/templates/compose');
    cy.waitForPageLoad();

    // Module catalog list — pick the first row's "Add" button.
    cy.get('body').then(($body) => {
      if ($body.find('button:contains("Add")').length === 0) {
        cy.log('No modules in catalog — skipping compose interaction');
        return;
      }
      cy.contains('button', 'Add').first().click();
      // After add, the canvas should now show 1 module(s)
      cy.contains('1 module(s)').should('exist');
      // Save button should be enabled (assuming no conflicts)
      cy.contains('button', 'Save as Template').should('not.be.disabled');
    });
  });

  it('opens the SaveTemplateModal when Save is clicked', () => {
    cy.visit('/app/system/templates/compose');
    cy.waitForPageLoad();

    cy.get('body').then(($body) => {
      if ($body.find('button:contains("Add")').length === 0) {
        cy.log('No modules in catalog — skipping save flow');
        return;
      }
      cy.contains('button', 'Add').first().click();
      cy.contains('button', 'Save as Template').click();
      cy.assertContainsAny(['Save as Template', 'Name']);
    });
  });

  it('persists a new template through the save flow', () => {
    const templateName = `e2e-template-${Date.now()}`;
    cy.visit('/app/system/templates/compose');
    cy.waitForPageLoad();

    cy.get('body').then(($body) => {
      if ($body.find('button:contains("Add")').length === 0) {
        cy.log('No modules in catalog — skipping persistence');
        return;
      }
      cy.contains('button', 'Add').first().click();
      cy.contains('button', 'Save as Template').click();
      cy.get('input[placeholder*="web-tier"]').type(templateName);
      cy.contains('button', 'Save Template').click();

      // Composer should reset (no modules selected) and show success notification.
      cy.contains(templateName, { timeout: 10000 }).should('exist');

      // Visit the templates list and verify the template is there.
      cy.visit('/app/system/templates');
      cy.waitForPageLoad();
      cy.contains(templateName).should('exist');
    });
  });
});
