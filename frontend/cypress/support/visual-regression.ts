/// <reference types="cypress" />

// Visual regression testing utilities and configuration

declare global {
  namespace Cypress {
    interface Chainable {
      /**
       * Take a baseline screenshot for visual regression testing
       * @example cy.takeBaselineScreenshot('login-page')
       */
      takeBaselineScreenshot(name: string, options?: any): Chainable<void>;

      /**
       * Compare current screen with baseline screenshot
       * @example cy.compareScreenshot('login-page')
       */
      compareScreenshot(name: string, options?: any): Chainable<void>;

      /**
       * Take screenshot with consistent viewport and settings
       * @example cy.screenshotConsistent('test-name')
       */
      screenshotConsistent(name: string, options?: any): Chainable<void>;

      /**
       * Set up visual regression test environment
       * @example cy.setupVisualTesting()
       */
      setupVisualTesting(): Chainable<void>;

      /**
       * Wait for CSS animations and transitions to complete
       * @example cy.waitForAnimations()
       */
      waitForAnimations(): Chainable<void>;
    }
  }
}

// Default screenshot configuration
const DEFAULT_SCREENSHOT_OPTIONS = {
  capture: 'viewport',
  clip: { x: 0, y: 0, width: 1280, height: 720 },
  blackout: [], // Elements to blackout (e.g., timestamps, dynamic content)
  overwrite: false
};

// Viewport presets for consistent testing
export const VIEWPORTS = {
  desktop: { width: 1280, height: 720 },
  tablet: { width: 768, height: 1024 },
  mobile: { width: 375, height: 667 },
  'mobile-small': { width: 320, height: 568 },
  'desktop-xl': { width: 1920, height: 1080 }
};

// Elements that should be blackout due to dynamic content
export const DYNAMIC_ELEMENTS = [
  '[data-testid="timestamp"]',
  '[data-testid="dynamic-id"]',
  '.animate-spin', // Loading spinners
  '.animate-pulse', // Skeleton loaders
];

// Set up visual regression testing environment
Cypress.Commands.add('setupVisualTesting', () => {
  // Set consistent viewport
  cy.viewport(1280, 720);
  
  // Disable animations for consistent screenshots
  cy.window().then(win => {
    const style = win.document.createElement('style');
    style.textContent = `
      *, *::before, *::after {
        animation-duration: 0s !important;
        animation-delay: 0s !important;
        transition-duration: 0s !important;
        transition-delay: 0s !important;
      }
    `;
    win.document.head.appendChild(style);
  });
  
  // Wait for fonts to load
  cy.document().then(doc => {
    return doc.fonts.ready;
  });
});

// Wait for animations and transitions to complete
Cypress.Commands.add('waitForAnimations', () => {
  // Wait for any CSS animations to complete
  cy.get('body').should('be.visible');
  // Small delay to allow transitions to settle
  cy.wait(100);
});

// Take a consistent screenshot
Cypress.Commands.add('screenshotConsistent', (name: string, options = {}) => {
  const screenshotOptions = {
    ...DEFAULT_SCREENSHOT_OPTIONS,
    ...options
  };
  
  // Wait for any pending animations or transitions
  cy.waitForAnimations();
  
  // Blackout dynamic elements
  if (screenshotOptions.blackout && screenshotOptions.blackout.length > 0) {
    screenshotOptions.blackout.forEach((selector: string) => {
      cy.get('body').then($body => {
        if ($body.find(selector).length > 0) {
          cy.get(selector).invoke('css', 'visibility', 'hidden');
        }
      });
    });
  }
  
  // Take screenshot
  cy.screenshot(name, screenshotOptions);
});

// Take baseline screenshot (for initial run)
Cypress.Commands.add('takeBaselineScreenshot', (name: string, options = {}) => {
  cy.setupVisualTesting();
  
  const baselineOptions = {
    ...DEFAULT_SCREENSHOT_OPTIONS,
    ...options,
    overwrite: true // Always overwrite baseline
  };
  
  cy.screenshotConsistent(`baseline-${name}`, baselineOptions);
});

// Compare screenshot with baseline
Cypress.Commands.add('compareScreenshot', (name: string, options = {}) => {
  cy.setupVisualTesting();
  
  // Take current screenshot
  cy.screenshotConsistent(`current-${name}`, options);
  
  // Note: Actual comparison would be done by external tool
  // This is a placeholder for the comparison logic
  cy.log(`Screenshot comparison for: ${name}`);
  cy.log('To implement actual comparison, integrate with tools like:');
  cy.log('- cypress-image-diff-js');
  cy.log('- percy-cypress');
  cy.log('- cypress-visual-regression');
});

// Utility function to hide dynamic content
export const hideDynamicContent = () => {
  DYNAMIC_ELEMENTS.forEach(selector => {
    cy.get('body').then($body => {
      if ($body.find(selector).length > 0) {
        cy.get(selector).invoke('css', 'visibility', 'hidden');
      }
    });
  });
};

// Utility function to test multiple viewports
export const testMultipleViewports = (testFn: (viewport: string) => void) => {
  Object.entries(VIEWPORTS).forEach(([name, { width, height }]) => {
    cy.viewport(width, height);
    testFn(name);
  });
};

// Export configuration for external tools
export const VISUAL_REGRESSION_CONFIG = {
  threshold: 0.1, // 10% difference threshold
  thresholdType: 'percent',
  screenshotOptions: DEFAULT_SCREENSHOT_OPTIONS,
  viewports: VIEWPORTS,
  dynamicElements: DYNAMIC_ELEMENTS
};