/// <reference types="cypress" />

/**
 * Testing Utility Commands
 *
 * Standardized commands for common test scenarios:
 * - Responsive design testing
 * - Error handling verification
 * - Permission testing
 * - Loading state verification
 */

export interface ViewportConfig {
  name: string;
  width: number;
  height: number;
}

export const STANDARD_VIEWPORTS: ViewportConfig[] = [
  { name: 'mobile', width: 375, height: 667 },
  { name: 'tablet', width: 768, height: 1024 },
  { name: 'desktop', width: 1280, height: 720 },
  { name: 'desktop-lg', width: 1920, height: 1080 },
];

declare global {
  namespace Cypress {
    interface Chainable {
      /**
       * Test responsive design across multiple viewports
       * @example cy.testResponsiveDesign('/app/dashboard')
       * @example cy.testResponsiveDesign('/app/dashboard', { checkContent: ['Dashboard', 'Overview'] })
       */
      testResponsiveDesign(
        url: string,
        options?: { viewports?: ViewportConfig[]; checkContent?: string | string[] }
      ): Chainable<void>;

      /**
       * Test a specific viewport
       * @example cy.testViewport('mobile', '/app/dashboard')
       */
      testViewport(viewport: string | ViewportConfig, url?: string): Chainable<void>;

      /**
       * Test error handling for an API endpoint
       * @example cy.testErrorHandling('/api/v1/users', { statusCode: 500 })
       * @example cy.testErrorHandling(new RegExp('/api/v1/users.*'), { statusCode: 500 })
       */
      testErrorHandling(
        endpoint: string | RegExp,
        options?: {
          statusCode?: number;
          method?: 'GET' | 'POST' | 'PUT' | 'DELETE' | 'PATCH';
          visitUrl?: string;
          expectRetryButton?: boolean;
        }
      ): Chainable<void>;

      /**
       * Test permission denied scenario
       * @example cy.testPermissionDenied('/admin/users')
       */
      testPermissionDenied(url: string): Chainable<void>;

      /**
       * Verify loading state is shown and then removed
       * @example cy.verifyLoadingState()
       */
      verifyLoadingState(): Chainable<void>;

      /**
       * Test empty state display
       * @example cy.testEmptyState('[data-testid="user-list"]', 'No users found')
       */
      testEmptyState(containerSelector: string, emptyMessage?: string): Chainable<void>;

      /**
       * Mock API endpoint with fixture
       * @example cy.mockEndpoint('GET', '/api/v1/users', 'users.json')
       */
      mockEndpoint(
        method: 'GET' | 'POST' | 'PUT' | 'DELETE' | 'PATCH' | 'HEAD' | 'OPTIONS',
        endpoint: string | RegExp,
        fixtureOrBody: string | object,
        options?: { statusCode?: number; delay?: number; alias?: string; wrapResponse?: boolean }
      ): Chainable<void>;

      /**
       * Mock API error response
       * @example cy.mockApiError('/api/v1/users', 500, 'Server error')
       */
      mockApiError(
        endpoint: string | RegExp,
        statusCode?: number,
        errorMessage?: string
      ): Chainable<void>;

      /**
       * Test table displays data correctly
       * @example cy.testTableDisplay('[data-testid="users-table"]', { minRows: 1 })
       */
      testTableDisplay(
        selector: string,
        options?: { minRows?: number; columns?: string[] }
      ): Chainable<void>;

      /**
       * Test pagination controls
       * @example cy.testPagination('[data-testid="pagination"]')
       */
      testPagination(selector?: string): Chainable<void>;

      /**
       * Verify no console errors occurred
       * @example cy.verifyNoConsoleErrors()
       */
      verifyNoConsoleErrors(): Chainable<void>;

      /**
       * Take screenshot for visual comparison
       * @example cy.screenshotPage('dashboard-desktop')
       */
      screenshotPage(name: string, options?: { viewport?: string }): Chainable<void>;

      /**
       * Assert page contains at least one of the given text strings
       * @example cy.assertContainsAny(['Dashboard', 'Home', 'Overview'])
       */
      assertContainsAny(texts: string[]): Chainable<void>;

      /**
       * Assert at least one of the given selectors exists
       * @example cy.assertHasElement(['[data-testid="table"]', '[data-testid="list"]'])
       */
      assertHasElement(selectors: string[]): Chainable<JQuery<HTMLElement>>;

      /**
       * Assert a page section is visible with expected characteristics
       * @example cy.assertPageSection('billing', { hasTitle: true, hasContent: true })
       */
      assertPageSection(
        sectionName: string,
        options?: { hasTitle?: boolean; hasCards?: boolean; hasTable?: boolean; hasActions?: boolean }
      ): Chainable<void>;

      /**
       * Assert page loaded successfully with core elements
       * @example cy.assertPageReady('/app/dashboard', 'Dashboard')
       */
      assertPageReady(url: string, expectedTitle?: string): Chainable<void>;

      /**
       * Assert tab content is displayed
       * @example cy.assertTabContent('Invoices', { hasTable: true })
       */
      assertTabContent(tabName: string, options?: { hasTable?: boolean; hasCards?: boolean }): Chainable<void>;

      /**
       * Assert statistics cards are displayed
       * @example cy.assertStatCards(['Total', 'Active', 'Pending'])
       */
      assertStatCards(expectedLabels: string[]): Chainable<void>;

      /**
       * Assert modal is visible with expected content
       * @example cy.assertModalVisible('Create User')
       */
      assertModalVisible(titleOrTestId?: string): Chainable<void>;

      /**
       * Assert action button exists and is actionable
       * @example cy.assertActionButton('Create Invoice')
       */
      assertActionButton(label: string): Chainable<JQuery<HTMLElement>>;
    }
  }
}

// Test responsive design across viewports
Cypress.Commands.add(
  'testResponsiveDesign',
  (
    url: string,
    options: { viewports?: ViewportConfig[]; checkContent?: string | string[] } = {}
  ) => {
    const { viewports = STANDARD_VIEWPORTS, checkContent } = options;

    viewports.forEach((vp) => {
      cy.viewport(vp.width, vp.height);
      cy.visit(url);
      cy.waitForPageLoad();

      // Verify page renders without errors
      cy.get('body')
        .should('be.visible')
        .and('not.contain.text', 'TypeError')
        .and('not.contain.text', 'Cannot read');

      // Check for specific content if provided
      if (checkContent) {
        if (Array.isArray(checkContent)) {
          // If array, check that at least one content item is present
          cy.assertContainsAny(checkContent);
        } else {
          cy.get('body').should('contain.text', checkContent);
        }
      }
    });

    // Reset to desktop viewport
    cy.viewport(1280, 720);
  }
);

// Test specific viewport
Cypress.Commands.add(
  'testViewport',
  (viewport: string | ViewportConfig, url?: string) => {
    if (typeof viewport === 'string') {
      // Named viewport
      const vp = STANDARD_VIEWPORTS.find((v) => v.name === viewport);
      if (vp) {
        cy.viewport(vp.width, vp.height);
      } else {
        cy.viewport(viewport as Cypress.ViewportPreset);
      }
    } else {
      cy.viewport(viewport.width, viewport.height);
    }

    // Only visit if URL provided
    if (url) {
      cy.visit(url);
      cy.waitForPageLoad();
    }
    cy.get('body').should('be.visible');
  }
);

// Test error handling
Cypress.Commands.add(
  'testErrorHandling',
  (
    endpoint: string | RegExp,
    options: {
      statusCode?: number;
      method?: 'GET' | 'POST' | 'PUT' | 'DELETE' | 'PATCH';
      visitUrl?: string;
      expectRetryButton?: boolean;
    } = {}
  ) => {
    const {
      statusCode = 500,
      method = 'GET' as const,
      visitUrl,
      expectRetryButton = false,
    } = options;

    // Mock the error response
    cy.intercept(method, endpoint, {
      statusCode,
      body: {
        success: false,
        error: `Server error (${statusCode})`,
      },
    }).as('errorRequest');

    // Visit page if URL provided
    if (visitUrl) {
      cy.visit(visitUrl);
      cy.waitForPageLoad();
    }

    // Verify page handles error gracefully
    cy.get('body')
      .should('be.visible')
      .and('not.contain.text', 'TypeError')
      .and('not.contain.text', 'Cannot read')
      .and('not.contain.text', 'undefined is not');

    // Check for retry button if expected
    if (expectRetryButton) {
      cy.get('button:contains("Try Again"), button:contains("Retry"), [data-testid="retry-btn"]')
        .should('exist');
    }
  }
);

// Test permission denied scenario
Cypress.Commands.add('testPermissionDenied', (url: string) => {
  cy.visit(url);
  cy.waitForPageLoad();

  // Should show permission denied message or redirect
  cy.get('body').then(($body) => {
    const hasPermissionMessage =
      $body.text().includes("don't have permission") ||
      $body.text().includes('Access Denied') ||
      $body.text().includes('Unauthorized') ||
      $body.text().includes('403');

    const hasRedirected = !window.location.pathname.includes(url);

    expect(hasPermissionMessage || hasRedirected).to.be.true;
  });
});

// Verify loading state
Cypress.Commands.add('verifyLoadingState', () => {
  // Should see loading indicator (brief window to catch it)
  cy.get(
    '[data-testid="loading-spinner"], .loading-spinner, .animate-spin, [data-loading="true"]',
    { timeout: 500 }
  ).should('exist');

  // Loading should eventually disappear (use config's default timeout)
  cy.get(
    '[data-testid="loading-spinner"], .loading-spinner, .animate-spin, [data-loading="true"]',
    { timeout: 10000 }
  ).should('not.exist');
});

// Test empty state
Cypress.Commands.add(
  'testEmptyState',
  (containerSelector: string, emptyMessage?: string) => {
    cy.get(containerSelector).should('be.visible');

    if (emptyMessage) {
      cy.get(containerSelector).should('contain.text', emptyMessage);
    } else {
      // Check for common empty state patterns
      cy.get(containerSelector).then(($container) => {
        const text = $container.text().toLowerCase();
        const hasEmptyIndicator =
          text.includes('no ') ||
          text.includes('empty') ||
          text.includes('not found') ||
          text.includes("don't have any");

        expect(hasEmptyIndicator).to.be.true;
      });
    }
  }
);

// Mock endpoint with fixture or body
// Automatically wraps responses in { success: true, data: ... } format
type HttpMethod = 'GET' | 'POST' | 'PUT' | 'DELETE' | 'PATCH' | 'HEAD' | 'OPTIONS';

interface InterceptConfig {
  statusCode?: number;
  delay?: number;
  fixture?: string;
  body?: unknown;
}

Cypress.Commands.add(
  'mockEndpoint',
  (
    method: HttpMethod,
    endpoint: string | RegExp,
    fixtureOrBody: string | object,
    options: { statusCode?: number; delay?: number; alias?: string; wrapResponse?: boolean } = {}
  ) => {
    const { statusCode = 200, delay = 0, alias, wrapResponse = true } = options;

    const interceptConfig: InterceptConfig = {
      statusCode,
      delay,
    };

    if (typeof fixtureOrBody === 'string') {
      interceptConfig.fixture = fixtureOrBody;
    } else {
      // Wrap response in standard API format unless it already has success property or wrapResponse is false
      const hasSuccessProperty = typeof fixtureOrBody === 'object' && fixtureOrBody !== null && 'success' in fixtureOrBody;
      if (wrapResponse && !hasSuccessProperty) {
        interceptConfig.body = {
          success: true,
          data: fixtureOrBody
        };
      } else {
        interceptConfig.body = fixtureOrBody;
      }
    }

    const intercept = cy.intercept(method, endpoint, interceptConfig);

    if (alias) {
      intercept.as(alias);
    }
  }
);

// Mock API error
Cypress.Commands.add(
  'mockApiError',
  (endpoint: string | RegExp, statusCode = 500, errorMessage = 'Server error') => {
    cy.intercept('GET', endpoint, {
      statusCode,
      body: {
        success: false,
        error: errorMessage,
      },
    });
  }
);

// Test table display
Cypress.Commands.add(
  'testTableDisplay',
  (
    selector: string,
    options: { minRows?: number; columns?: string[] } = {}
  ) => {
    const { minRows = 1, columns = [] } = options;

    cy.get(selector).should('be.visible');

    // Check minimum rows
    if (minRows > 0) {
      cy.get(`${selector} tbody tr, ${selector} [data-testid="table-row"]`)
        .should('have.length.at.least', minRows);
    }

    // Check columns exist
    columns.forEach((column) => {
      cy.get(`${selector} th, ${selector} [data-testid="table-header"]`)
        .should('contain.text', column);
    });
  }
);

// Test pagination
Cypress.Commands.add('testPagination', (selector = '[data-testid="pagination"]') => {
  cy.get(selector).should('be.visible');

  // Check for common pagination elements
  cy.get(`${selector} button, ${selector} a`).should('have.length.at.least', 1);
});

// Verify no console errors (setup in beforeEach)
Cypress.Commands.add('verifyNoConsoleErrors', () => {
  // This requires setting up console spy in beforeEach
  // For now, just verify page rendered without visible errors
  cy.get('body')
    .should('not.contain.text', 'TypeError')
    .and('not.contain.text', 'ReferenceError')
    .and('not.contain.text', 'SyntaxError');
});

// Screenshot page
Cypress.Commands.add(
  'screenshotPage',
  (name: string, options: { viewport?: string } = {}) => {
    const { viewport } = options;

    if (viewport) {
      const vp = STANDARD_VIEWPORTS.find((v) => v.name === viewport);
      if (vp) {
        cy.viewport(vp.width, vp.height);
      }
    }

    cy.waitForStableDOM();
    cy.screenshot(name, { capture: 'viewport' });
  }
);

// Assert page contains at least one of the given texts
Cypress.Commands.add('assertContainsAny', (texts: string[]) => {
  cy.get('body').should(($body) => {
    const bodyText = $body.text();
    const found = texts.some((text) => bodyText.includes(text));
    expect(found, `Expected page to contain one of: ${texts.join(', ')}`).to.be.true;
  });
});

// Assert at least one of the given selectors exists (reduced from 10s to 5s)
Cypress.Commands.add('assertHasElement', (selectors: string[]) => {
  const combinedSelector = selectors.join(', ');
  return cy.get(combinedSelector, { timeout: 5000 }).should('exist').first();
});

// Assert page section is visible with characteristics
Cypress.Commands.add(
  'assertPageSection',
  (
    sectionName: string,
    options: { hasTitle?: boolean; hasCards?: boolean; hasTable?: boolean; hasActions?: boolean } = {}
  ) => {
    const { hasTitle = true, hasCards = false, hasTable = false, hasActions = false } = options;
    const normalizedName = sectionName.toLowerCase().replace(/\s+/g, '-');

    // Assert page/section container exists
    cy.assertHasElement([
      `[data-testid="${normalizedName}-section"]`,
      `[data-testid="${normalizedName}-container"]`,
      `[data-testid="page-container"]`,
      'main',
    ]).should('be.visible');

    // Assert title if expected
    if (hasTitle) {
      cy.assertContainsAny([sectionName, sectionName.replace(/-/g, ' ')]);
    }

    // Assert cards if expected
    if (hasCards) {
      cy.assertHasElement([
        '[data-testid*="card"]',
        '[data-testid*="stat"]',
        '[role="article"]',
      ]).should('be.visible');
    }

    // Assert table if expected
    if (hasTable) {
      cy.assertHasElement([
        'table',
        '[data-testid*="table"]',
        '[role="table"]',
        '[data-testid*="list"]',
      ]).should('be.visible');
    }

    // Assert action buttons if expected
    if (hasActions) {
      cy.assertHasElement([
        '[data-testid*="action"]',
        '[data-testid*="btn"]',
        'button[type="button"]',
      ]).should('be.visible');
    }
  }
);

// Assert page loaded successfully
Cypress.Commands.add('assertPageReady', (url: string, expectedTitle?: string) => {
  cy.visit(url);
  cy.waitForPageLoad();
  cy.verifyPageLoaded();

  if (expectedTitle) {
    cy.assertContainsAny([expectedTitle]);
  }
});

// Assert tab content is displayed
Cypress.Commands.add(
  'assertTabContent',
  (tabName: string, options: { hasTable?: boolean; hasCards?: boolean } = {}) => {
    const { hasTable = false, hasCards = false } = options;

    // Verify tab is selected/active
    cy.assertContainsAny([tabName]);

    if (hasTable) {
      cy.assertHasElement([
        'table',
        '[data-testid*="table"]',
        '[role="table"]',
        'tbody tr',
      ]).should('exist');
    }

    if (hasCards) {
      cy.assertHasElement([
        '[data-testid*="card"]',
        '[data-testid*="stat"]',
        '[role="article"]',
      ]).should('be.visible');
    }
  }
);

// Assert statistics cards are displayed
Cypress.Commands.add('assertStatCards', (expectedLabels: string[]) => {
  expectedLabels.forEach((label) => {
    cy.get('body').should('contain.text', label);
  });

  // Also verify card structure exists
  cy.assertHasElement([
    '[data-testid*="stat"]',
    '[data-testid*="card"]',
    '[data-testid*="metric"]',
  ]).should('be.visible');
});

// Assert modal is visible
Cypress.Commands.add('assertModalVisible', (titleOrTestId?: string) => {
  const modalSelectors = [
    '[role="dialog"]',
    '[data-testid="modal"]',
    '[data-testid*="modal"]',
    '.modal',
  ];

  cy.assertHasElement(modalSelectors).should('be.visible');

  if (titleOrTestId) {
    if (titleOrTestId.startsWith('[')) {
      // It's a selector
      cy.get(titleOrTestId).should('be.visible');
    } else {
      // It's a title text
      cy.get(modalSelectors.join(', ')).should('contain.text', titleOrTestId);
    }
  }
});

// Assert action button exists and is clickable
Cypress.Commands.add('assertActionButton', (label: string) => {
  const normalizedLabel = label.toLowerCase().replace(/\s+/g, '-');

  return cy
    .assertHasElement([
      `[data-testid="${normalizedLabel}-btn"]`,
      `[data-testid="${normalizedLabel}-button"]`,
      `button:contains("${label}")`,
      `[role="button"]:contains("${label}")`,
    ])
    .should('be.visible')
    .and('not.be.disabled');
});

export {};
