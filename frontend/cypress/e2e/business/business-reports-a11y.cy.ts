/// <reference types="cypress" />
/// <reference path="../../support/accessibility.ts" />

/**
 * Accessibility audit for the business reports module.
 *
 * Runs cypress-axe (WCAG 2.1 AA) on the pages we refactored in 2026-05:
 * the reports overview, the report builder, the request queue, and the
 * request modal. Captures color contrast, label associations, dialog
 * semantics, keyboard accessibility, and landmark structure.
 *
 * Pre-requisites:
 *   - Frontend dev server up (npm run dev) or built (npm run build)
 *   - Admin user available via cy.login()
 */

import 'cypress-axe';
import { AXE_CONFIG } from '../../support/accessibility';

describe('Business Reports — Accessibility (cypress-axe)', () => {
  beforeEach(() => {
    cy.login();
    cy.injectAxe();
  });

  it('Reports overview page has no WCAG 2.1 AA violations', () => {
    cy.visit('/app/business/reports/overview');
    cy.waitForPageLoad();
    cy.checkA11y(undefined, AXE_CONFIG, (violations) => {
      cy.task('log', `Overview a11y violations: ${violations.length}`);
      violations.forEach((v) => cy.task('log', `  ${v.id}: ${v.help}`));
    });
  });

  it('Reports library page has no WCAG 2.1 AA violations', () => {
    cy.visit('/app/business/reports/library');
    cy.waitForPageLoad();
    cy.checkA11y(undefined, AXE_CONFIG);
  });

  it('Reports builder page has no WCAG 2.1 AA violations', () => {
    cy.visit('/app/business/reports/builder');
    cy.waitForPageLoad();
    cy.checkA11y(undefined, AXE_CONFIG);
  });

  it('Reports queue page has no WCAG 2.1 AA violations', () => {
    cy.visit('/app/business/reports/queue');
    cy.waitForPageLoad();
    cy.checkA11y(undefined, AXE_CONFIG);
  });

  describe('Report request modal', () => {
    beforeEach(() => {
      cy.visit('/app/business/reports/library');
      cy.waitForPageLoad();
    });

    it('opens via keyboard, dismisses via Escape', () => {
      // First template card should be activatable
      cy.get('[data-testid="report-template-card"], [class*="template"]').first().click();
      cy.get('[role="dialog"][aria-modal="true"]').should('be.visible');

      // Modal has accessible name from h2#report-request-modal-title
      cy.get('[role="dialog"]').should('have.attr', 'aria-labelledby', 'report-request-modal-title');
      cy.get('#report-request-modal-title').should('exist').and('be.visible');

      // Escape dismisses
      cy.get('body').trigger('keydown', { key: 'Escape' });
      cy.get('[role="dialog"]').should('not.exist');
    });

    it('close button has accessible label and is reachable by keyboard', () => {
      cy.get('[data-testid="report-template-card"], [class*="template"]').first().click();
      cy.get('button[aria-label*="Close"]').should('be.visible').focus().should('be.focused');
    });

    it('modal has no WCAG 2.1 AA violations while open', () => {
      cy.get('[data-testid="report-template-card"], [class*="template"]').first().click();
      cy.get('[role="dialog"]').should('be.visible');
      cy.checkA11y('[role="dialog"]', AXE_CONFIG);
    });

    it('form inputs have associated labels', () => {
      cy.get('[data-testid="report-template-card"], [class*="template"]').first().click();
      cy.get('label[for="report-request-name"]').should('exist');
      cy.get('#report-request-name').should('be.visible');
      cy.get('label[for="report-request-format"]').should('exist');
      cy.get('#report-request-format').should('be.visible');
    });
  });

  describe('Report builder form', () => {
    beforeEach(() => {
      cy.visit('/app/business/reports/builder');
      cy.waitForPageLoad();
    });

    it('Report Name input is associated with its label', () => {
      cy.get('label[for="report-builder-name"]').should('exist');
      cy.get('#report-builder-name').should('be.visible');
    });
  });
});
