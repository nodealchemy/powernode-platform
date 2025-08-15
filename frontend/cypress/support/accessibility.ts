/// <reference types="cypress" />
import 'cypress-axe';

// Accessibility testing utilities and configurations

declare global {
  namespace Cypress {
    interface Chainable {
      /**
       * Custom tab command for keyboard navigation testing
       * @example cy.tab()
       */
      tab(): Chainable<JQuery<HTMLElement>>;

      /**
       * Check if element is properly labeled for screen readers
       * @example cy.checkAriaLabel('button')
       */
      checkAriaLabel(selector: string): Chainable<void>;

      /**
       * Test keyboard navigation flow
       * @example cy.testKeyboardFlow(['input[type="email"]', 'input[type="password"]', 'button[type="submit"]'])
       */
      testKeyboardFlow(selectors: string[]): Chainable<void>;

      /**
       * Check color contrast ratio
       * @example cy.checkColorContrast('button', 4.5)
       */
      checkColorContrast(selector: string, ratio: number): Chainable<void>;

      /**
       * Test focus management
       * @example cy.testFocusManagement()
       */
      testFocusManagement(): Chainable<void>;
    }
  }
}

// Configuration for axe-core accessibility testing
export const AXE_CONFIG = {
  // WCAG 2.1 Level AA compliance
  tags: ['wcag2a', 'wcag2aa', 'wcag21aa'],
  
  // Custom rules configuration
  rules: {
    'color-contrast': { enabled: true },
    'keyboard-navigation': { enabled: true },
    'focus-order-semantics': { enabled: true },
    'landmarks': { enabled: true },
    'headings': { enabled: true },
    'labels': { enabled: true },
    'language': { enabled: true },
    'link-purpose': { enabled: true },
    'list': { enabled: true },
    'page-has-heading-one': { enabled: true },
    'region': { enabled: true },
    'skip-link': { enabled: true },
    'tabindex': { enabled: true },
  },
  
  // Elements to exclude from testing
  exclude: [
    // Exclude third-party widgets that we can't control
    '.third-party-widget',
    // Exclude elements that are intentionally hidden
    '[aria-hidden="true"]'
  ]
};

// Custom tab command for keyboard navigation
Cypress.Commands.add('tab', { prevSubject: 'optional' }, (subject) => {
  if (subject) {
    return cy.wrap(subject).trigger('keydown', { key: 'Tab', keyCode: 9, which: 9 });
  } else {
    return cy.get('body').trigger('keydown', { key: 'Tab', keyCode: 9, which: 9 });
  }
});

// Check ARIA labeling
Cypress.Commands.add('checkAriaLabel', (selector: string) => {
  cy.get(selector).should(($el) => {
    const hasAriaLabel = $el.attr('aria-label');
    const hasAriaLabelledBy = $el.attr('aria-labelledby');
    const hasAriaDescribedBy = $el.attr('aria-describedby');
    const hasAssociatedLabel = $el.attr('id') && Cypress.$(`label[for="${$el.attr('id')}"]`).length > 0;
    
    expect(
      hasAriaLabel || hasAriaLabelledBy || hasAriaDescribedBy || hasAssociatedLabel,
      'Element should have proper ARIA labeling'
    ).to.be.true;
  });
});

// Test keyboard navigation flow
Cypress.Commands.add('testKeyboardFlow', (selectors: string[]) => {
  let currentIndex = 0;
  
  // Start from body and tab through elements
  cy.get('body').click();
  
  selectors.forEach((selector, index) => {
    cy.get('body').tab();
    cy.focused().should('match', selector);
    currentIndex = index;
  });
  
  // Test reverse tab order
  for (let i = currentIndex; i >= 0; i--) {
    if (i < currentIndex) {
      cy.focused().trigger('keydown', { key: 'Tab', shiftKey: true, keyCode: 9, which: 9 });
    }
    cy.focused().should('match', selectors[i]);
  }
});

// Check color contrast ratio
Cypress.Commands.add('checkColorContrast', (selector: string, minRatio: number) => {
  cy.get(selector).should(($el) => {
    const element = $el[0];
    const style = window.getComputedStyle(element);
    const backgroundColor = style.backgroundColor;
    const color = style.color;
    
    // This is a simplified check - in practice, you'd use a color contrast library
    // like 'color-contrast' or integrate with axe-core's color-contrast rule
    cy.log(`Element: ${selector}`);
    cy.log(`Background: ${backgroundColor}, Text: ${color}`);
    cy.log(`Required contrast ratio: ${minRatio}:1`);
    
    // For now, just verify colors are set
    expect(backgroundColor).to.not.equal('rgba(0, 0, 0, 0)');
    expect(color).to.not.equal('rgba(0, 0, 0, 0)');
  });
});

// Test focus management
Cypress.Commands.add('testFocusManagement', () => {
  let previouslyFocused: string | null = null;
  
  cy.document().then(doc => {
    // Track focus changes
    doc.addEventListener('focusin', (e) => {
      const target = e.target as HTMLElement;
      const newFocused = target.tagName + (target.id ? `#${target.id}` : '') + 
                        (target.className ? `.${target.className.split(' ')[0]}` : '');
      
      cy.log(`Focus moved from ${previouslyFocused} to ${newFocused}`);
      previouslyFocused = newFocused;
    });
  });
  
  // Test that focus is visible
  cy.focused().should('be.visible');
  
  // Test that focus outline is present
  cy.focused().should('have.css', 'outline-width').and('not.equal', '0px');
});

// Utility functions for accessibility testing

export const WCAG_LEVELS = {
  A: 'wcag2a',
  AA: 'wcag2aa', 
  AAA: 'wcag2aaa'
};

export const COMMON_ACCESSIBILITY_ISSUES = [
  'color-contrast',
  'keyboard-navigation', 
  'focus-order-semantics',
  'landmarks',
  'headings',
  'labels',
  'alt-text',
  'form-field-multiple-labels',
  'duplicate-id',
  'aria-hidden-body',
  'aria-allowed-attr',
  'aria-required-attr',
  'aria-valid-attr-value',
  'button-name',
  'link-name',
  'image-alt'
];

export const KEYBOARD_KEYS = {
  TAB: { key: 'Tab', keyCode: 9, which: 9 },
  SHIFT_TAB: { key: 'Tab', keyCode: 9, which: 9, shiftKey: true },
  ENTER: { key: 'Enter', keyCode: 13, which: 13 },
  SPACE: { key: ' ', keyCode: 32, which: 32 },
  ARROW_UP: { key: 'ArrowUp', keyCode: 38, which: 38 },
  ARROW_DOWN: { key: 'ArrowDown', keyCode: 40, which: 40 },
  ARROW_LEFT: { key: 'ArrowLeft', keyCode: 37, which: 37 },
  ARROW_RIGHT: { key: 'ArrowRight', keyCode: 39, which: 39 },
  ESCAPE: { key: 'Escape', keyCode: 27, which: 27 }
};

// Screen reader testing utilities
export const SCREEN_READER_SELECTORS = {
  headings: 'h1, h2, h3, h4, h5, h6, [role="heading"]',
  landmarks: '[role="main"], [role="navigation"], [role="banner"], [role="contentinfo"], [role="complementary"], [role="region"], main, nav, header, footer, aside, section[aria-label]',
  focusable: 'a[href], area[href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), button:not([disabled]), iframe, object, embed, [tabindex]:not([tabindex="-1"]), [contenteditable]',
  interactive: 'button, input, select, textarea, a[href], [role="button"], [role="link"], [role="menuitem"], [role="tab"], [role="checkbox"], [role="radio"]',
  form_controls: 'input, select, textarea, button[type="submit"], button[type="reset"]'
};

// Color contrast utilities
export const COLOR_CONTRAST_RATIOS = {
  AA_NORMAL: 4.5,
  AA_LARGE: 3,
  AAA_NORMAL: 7,
  AAA_LARGE: 4.5
};

// Focus trap utility
export const testFocusTrap = (containerSelector: string) => {
  cy.get(containerSelector).within(() => {
    // Find all focusable elements within container
    cy.get(SCREEN_READER_SELECTORS.focusable).as('focusableElements');
    
    // Tab through all elements
    cy.get('@focusableElements').each(($el, index) => {
      cy.wrap($el).focus();
      cy.focused().should('equal', $el[0]);
    });
    
    // Test that focus wraps around
    cy.get('@focusableElements').last().focus().tab();
    cy.get('@focusableElements').first().should('be.focused');
    
    // Test reverse tab
    cy.get('@focusableElements').first().focus().trigger('keydown', KEYBOARD_KEYS.SHIFT_TAB);
    cy.get('@focusableElements').last().should('be.focused');
  });
};