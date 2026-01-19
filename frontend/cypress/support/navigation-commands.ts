/// <reference types="cypress" />

/**
 * Navigation Commands
 *
 * Standardized commands for page navigation, tab switching, and button clicking.
 * Replaces duplicated navigation patterns across test files.
 */

declare global {
  namespace Cypress {
    interface Chainable {
      /**
       * Verify page title is displayed
       * @example cy.verifyPageTitle('Dashboard')
       */
      verifyPageTitle(title: string): Chainable<void>;

      /**
       * Verify page has specific content
       * @example cy.verifyPageContent('Welcome to your account')
       */
      verifyPageContent(content: string): Chainable<void>;

      /**
       * Click a tab by its name
       * @example cy.clickTab('Invoices')
       */
      clickTab(tabName: string): Chainable<void>;

      /**
       * Click a button by label or test ID
       * @example cy.clickButton('Create Invoice')
       * @example cy.clickButton('submit-btn')
       */
      clickButton(labelOrTestId: string): Chainable<void>;

      /**
       * Navigate to a page and wait for it to load
       * @example cy.navigateTo('/app/business/billing')
       */
      navigateTo(path: string): Chainable<void>;

      /**
       * Navigate to page via sidebar/nav link
       * @example cy.navigateViaMenu('Business', 'Billing')
       */
      navigateViaMenu(section: string, item?: string): Chainable<void>;

      /**
       * Verify breadcrumbs contain expected items
       * @example cy.verifyBreadcrumbs(['Dashboard', 'Business', 'Billing'])
       */
      verifyBreadcrumbs(items: string[]): Chainable<void>;

      /**
       * Open a dropdown menu
       * @example cy.openDropdown('[data-testid="user-menu"]')
       */
      openDropdown(selector: string): Chainable<void>;

      /**
       * Select option from dropdown
       * @example cy.selectDropdownOption('user-menu', 'Settings')
       */
      selectDropdownOption(dropdownTestId: string, optionText: string): Chainable<void>;

      /**
       * Verify page loaded successfully (no errors)
       * @example cy.verifyPageLoaded()
       */
      verifyPageLoaded(): Chainable<void>;

      /**
       * Verify an element exists on the page
       * @example cy.verifyElementExists('[data-testid="user-table"]')
       */
      verifyElementExists(selector: string): Chainable<JQuery<HTMLElement>>;

      /**
       * Verify text content exists on page (case-insensitive)
       * @example cy.verifyTextExists('Create Invoice')
       */
      verifyTextExists(text: string): Chainable<void>;
    }
  }
}

// Verify page title
Cypress.Commands.add('verifyPageTitle', (title: string) => {
  cy.get('[data-testid="page-title"], h1, [data-testid="page-header"] h1', { timeout: 10000 })
    .should('be.visible')
    .and('contain.text', title);
});

// Verify page has specific content
Cypress.Commands.add('verifyPageContent', (content: string) => {
  cy.get('body', { timeout: 10000 }).should('contain.text', content);
});

// Click tab by name
Cypress.Commands.add('clickTab', (tabName: string) => {
  const normalizedName = tabName.toLowerCase().replace(/\s+/g, '-');

  // Try multiple selector strategies in order of preference
  cy.get('body').then(($body) => {
    const dataTestId = `[data-testid="tab-${normalizedName}"]`;
    const roleTab = `[role="tab"]:contains("${tabName}")`;
    const buttonTab = `button[data-state]:contains("${tabName}")`;
    const genericButton = `button:contains("${tabName}")`;

    if ($body.find(dataTestId).length) {
      cy.get(dataTestId).click();
    } else if ($body.find(roleTab).length) {
      cy.get(roleTab).first().click();
    } else if ($body.find(buttonTab).length) {
      cy.get(buttonTab).first().click();
    } else {
      cy.get(genericButton).first().click();
    }
  });

  cy.waitForStableDOM();
});

// Click button by label or test ID
Cypress.Commands.add('clickButton', (labelOrTestId: string) => {
  const normalizedId = labelOrTestId.toLowerCase().replace(/\s+/g, '-');

  cy.get('body').then(($body) => {
    // Priority 1: data-testid with -btn suffix
    const testIdBtn = `[data-testid="${normalizedId}-btn"]`;
    // Priority 2: data-testid exact match
    const testIdExact = `[data-testid="${labelOrTestId}"]`;
    // Priority 3: data-testid contains
    const testIdContains = `[data-testid*="${normalizedId}"]`;
    // Priority 4: button with exact text
    const buttonText = `button:contains("${labelOrTestId}")`;
    // Priority 5: any clickable with text
    const anyClickable = `a:contains("${labelOrTestId}"), [role="button"]:contains("${labelOrTestId}")`;

    if ($body.find(testIdBtn).length) {
      cy.get(testIdBtn).first().should('be.visible').click();
    } else if ($body.find(testIdExact).length) {
      cy.get(testIdExact).first().should('be.visible').click();
    } else if ($body.find(testIdContains).length) {
      cy.get(testIdContains).first().should('be.visible').click();
    } else if ($body.find(buttonText).length) {
      cy.get(buttonText).first().should('be.visible').click();
    } else if ($body.find(anyClickable).length) {
      cy.get(anyClickable).first().should('be.visible').click();
    } else {
      // Fallback: fail with helpful message
      throw new Error(`Button not found: "${labelOrTestId}". Tried selectors: ${testIdBtn}, ${testIdExact}, ${buttonText}`);
    }
  });
});

// Navigate to page and wait for load
Cypress.Commands.add('navigateTo', (path: string) => {
  cy.visit(path);
  cy.waitForPageLoad();
  cy.verifyPageLoaded();
});

// Navigate via sidebar menu
Cypress.Commands.add('navigateViaMenu', (section: string, item?: string) => {
  // Click section in sidebar
  cy.get(`[data-testid="nav-${section.toLowerCase()}"], a:contains("${section}")`)
    .first()
    .click();

  // If sub-item specified, click it too
  if (item) {
    cy.get(`[data-testid="nav-${item.toLowerCase()}"], a:contains("${item}")`)
      .first()
      .click();
  }

  cy.waitForPageLoad();
});

// Verify breadcrumbs
Cypress.Commands.add('verifyBreadcrumbs', (items: string[]) => {
  cy.get('[data-testid="breadcrumbs"], nav[aria-label="Breadcrumb"], .breadcrumbs', { timeout: 5000 })
    .should('be.visible')
    .within(() => {
      items.forEach((item) => {
        cy.contains(item).should('exist');
      });
    });
});

// Open dropdown
Cypress.Commands.add('openDropdown', (selector: string) => {
  cy.get(selector, { timeout: 5000 }).should('be.visible').click();
  // Wait for dropdown to animate open
  cy.wait(100);
});

// Select dropdown option
Cypress.Commands.add('selectDropdownOption', (dropdownTestId: string, optionText: string) => {
  cy.get(`[data-testid="${dropdownTestId}"]`).click();
  cy.get(`[role="option"]:contains("${optionText}"), [role="menuitem"]:contains("${optionText}")`)
    .first()
    .click();
});

// Verify page loaded successfully
Cypress.Commands.add('verifyPageLoaded', () => {
  // Ensure no JavaScript errors displayed
  cy.get('body')
    .should('be.visible')
    .and('not.contain.text', 'TypeError')
    .and('not.contain.text', 'Cannot read')
    .and('not.contain.text', 'undefined is not')
    .and('not.contain.text', 'Script error');
});

// Verify element exists
Cypress.Commands.add('verifyElementExists', (selector: string) => {
  return cy.get(selector, { timeout: 10000 }).should('exist');
});

// Verify text exists (case-insensitive)
Cypress.Commands.add('verifyTextExists', (text: string) => {
  cy.get('body').should('contain.text', text);
});

export {};
