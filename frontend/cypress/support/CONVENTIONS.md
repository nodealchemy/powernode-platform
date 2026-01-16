# Cypress Test Conventions

This document outlines the standardized conventions for writing Cypress E2E tests in the Powernode platform.

## Table of Contents

1. [Test Setup](#test-setup)
2. [Selector Priority](#selector-priority)
3. [Wait Strategies](#wait-strategies)
4. [Custom Commands Reference](#custom-commands-reference)
5. [Test Organization](#test-organization)
6. [Assertion Patterns](#assertion-patterns)
7. [Anti-Patterns to Avoid](#anti-patterns-to-avoid)

---

## Test Setup

### Standard Test Setup

Always use the `cy.standardTestSetup()` command in your `beforeEach` block:

```typescript
describe('Feature Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  it('should do something', () => {
    // Test implementation
  });
});
```

### With Feature-Specific Intercepts

For tests that need feature-specific API intercepts:

```typescript
// AI tests
beforeEach(() => {
  cy.standardTestSetup({ intercepts: ['ai'] });
});

// Admin tests
beforeEach(() => {
  cy.standardTestSetup({ intercepts: ['admin'] });
});

// DevOps tests
beforeEach(() => {
  cy.standardTestSetup({ intercepts: ['devops'] });
});

// Available intercept types:
// 'ai', 'admin', 'devops', 'system', 'marketplace', 'content', 'privacy'
```

### Login As Different Roles

```typescript
// Login as admin
beforeEach(() => {
  cy.standardTestSetup({ role: 'admin' });
});

// Login as billing manager
beforeEach(() => {
  cy.standardTestSetup({ role: 'billing.manager' });
});
```

---

## Selector Priority

**MANDATORY ORDER** - Use selectors in this priority:

### 1. `data-testid` (REQUIRED for testable elements)
```typescript
// ✅ BEST - Most stable, explicit for testing
cy.get('[data-testid="email-input"]')
cy.get('[data-testid="submit-btn"]')
cy.get('[data-testid="user-table"]')
```

### 2. ARIA Roles
```typescript
// ✅ GOOD - Semantic and accessible
cy.get('[role="dialog"]')
cy.get('[role="tab"]')
cy.get('[role="button"]')
```

### 3. ARIA Labels
```typescript
// ✅ GOOD - Accessible
cy.get('[aria-label="Close"]')
cy.get('[aria-label="Settings menu"]')
```

### 4. Semantic HTML Attributes
```typescript
// ✅ ACCEPTABLE - Semantic meaning
cy.get('button[type="submit"]')
cy.get('input[type="email"]')
```

### 5. NEVER Use These
```typescript
// ❌ NEVER - Fragile and maintenance nightmare
cy.get('[class*="modal"]')
cy.get('.btn-primary')
cy.contains('button', 'Submit')  // Text changes break tests
```

---

## Wait Strategies

### Use Intercepts for API Calls

```typescript
// ✅ CORRECT - Wait for specific API call
cy.intercept('GET', '/api/v1/users*').as('getUsers');
cy.visit('/app/admin/users');
cy.wait('@getUsers');
cy.get('[data-testid="user-table"]').should('be.visible');
```

### Use Page Load Utilities

```typescript
// ✅ CORRECT - Wait for page to be ready
cy.navigateTo('/app/dashboard');  // Includes waitForPageLoad

// Or explicitly
cy.visit('/app/dashboard');
cy.waitForPageLoad();
```

### Use DOM Stabilization

```typescript
// ✅ CORRECT - Wait for React to settle
cy.clickTab('Settings');
cy.waitForStableDOM();
```

### Avoid Arbitrary Waits

```typescript
// ❌ NEVER - Arbitrary waits are unreliable
cy.wait(1000);
cy.wait(5000);

// ❌ NEVER - Hardcoded timeouts without context
cy.get('[data-testid="element"]', { timeout: 10000 });
```

---

## Custom Commands Reference

### Login Commands

| Command | Description | Example |
|---------|-------------|---------|
| `cy.loginAsDemo()` | Login as demo user with session caching | `cy.loginAsDemo()` |
| `cy.loginAsRole(role)` | Login as specific role | `cy.loginAsRole('admin')` |
| `cy.loginViaAPI(email, password)` | Fast API-based login | `cy.loginViaAPI('user@example.com', 'pass')` |
| `cy.standardTestSetup(options)` | Complete test setup | `cy.standardTestSetup({ intercepts: ['ai'] })` |

### Navigation Commands

| Command | Description | Example |
|---------|-------------|---------|
| `cy.navigateTo(path)` | Navigate and wait for load | `cy.navigateTo('/app/dashboard')` |
| `cy.verifyPageTitle(title)` | Verify page title | `cy.verifyPageTitle('Dashboard')` |
| `cy.clickTab(name)` | Click a tab | `cy.clickTab('Settings')` |
| `cy.clickButton(label)` | Click a button | `cy.clickButton('Save')` |
| `cy.verifyPageLoaded()` | Verify page loaded without errors | `cy.verifyPageLoaded()` |

### Form Commands

| Command | Description | Example |
|---------|-------------|---------|
| `cy.fillForm(data)` | Fill form fields | `cy.fillForm({ email: 'user@example.com' })` |
| `cy.fillField(name, value)` | Fill single field | `cy.fillField('email', 'user@example.com')` |
| `cy.submitForm()` | Submit the form | `cy.submitForm()` |
| `cy.verifyFieldError(name, msg)` | Verify field has error | `cy.verifyFieldError('email', 'Required')` |

### Testing Utilities

| Command | Description | Example |
|---------|-------------|---------|
| `cy.testResponsiveDesign(url, options)` | Test across viewports | `cy.testResponsiveDesign('/app/dashboard', { checkContent: 'Dashboard' })` |
| `cy.testErrorHandling(endpoint, options)` | Test API error handling | `cy.testErrorHandling('/api/v1/users', { statusCode: 500, visitUrl: '/app/users' })` |
| `cy.mockEndpoint(method, endpoint, body, options)` | Mock API response | `cy.mockEndpoint('GET', '/api/v1/users', { data: [] }, { delay: 1000 })` |
| `cy.mockApiError(endpoint, statusCode, message)` | Mock API error | `cy.mockApiError('/api/v1/users*', 500, 'Server error')` |
| `cy.verifyLoadingState()` | Verify loading indicator appears | `cy.verifyLoadingState()` |

### Assertion Commands

| Command | Description | Example |
|---------|-------------|---------|
| `cy.assertContainsAny(texts)` | Assert page contains at least one text | `cy.assertContainsAny(['Dashboard', 'Home', 'Overview'])` |
| `cy.assertHasElement(selectors)` | Assert any matching element exists | `cy.assertHasElement(['[data-testid="table"]', 'table'])` |
| `cy.assertPageReady(url, title?)` | Navigate and verify page loads | `cy.assertPageReady('/app/billing', 'Billing')` |
| `cy.assertTabContent(name, options)` | Assert tab content is visible | `cy.assertTabContent('Invoices', { hasTable: true })` |
| `cy.assertStatCards(labels)` | Assert statistics cards display | `cy.assertStatCards(['Total', 'Active', 'Revenue'])` |
| `cy.assertModalVisible(title?)` | Assert modal dialog is visible | `cy.assertModalVisible('Create Invoice')` |
| `cy.assertActionButton(label)` | Assert action button exists | `cy.assertActionButton('Create Invoice')` |
| `cy.assertPageSection(name)` | Assert named section exists | `cy.assertPageSection('Overview')` |

### Wait Utilities

| Command | Description | Example |
|---------|-------------|---------|
| `cy.waitForPageLoad()` | Wait for loading spinner to disappear | `cy.waitForPageLoad()` |
| `cy.waitForModal()` | Wait for modal to appear | `cy.waitForModal()` |
| `cy.waitForModalClose()` | Wait for modal to close | `cy.waitForModalClose()` |
| `cy.waitForStableDOM()` | Wait for React reconciliation | `cy.waitForStableDOM()` |

---

## Test Organization

### File Structure

```
cypress/
├── e2e/
│   ├── auth/           # Authentication tests
│   ├── admin/          # Admin panel tests
│   ├── ai/             # AI features tests
│   ├── business/       # Business features tests
│   └── ...
├── fixtures/           # Test data files
└── support/            # Commands and utilities
```

### Test File Pattern

```typescript
/// <reference types="cypress" />

/**
 * Feature Name Tests
 *
 * Brief description of what this file tests
 */

describe('Feature Name Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Sub-feature', () => {
    it('should do specific thing', () => {
      // Arrange
      cy.navigateTo('/app/feature');

      // Act
      cy.clickButton('Action');

      // Assert
      cy.get('[data-testid="result"]').should('be.visible');
    });
  });
});

export {};
```

---

## Assertion Patterns

### Using Assertion Helper Commands

```typescript
// ✅ BEST - Page ready assertion (combines navigation + title check)
it('should navigate to billing page', () => {
  cy.assertPageReady('/app/business/billing', 'Billing');
});

// ✅ BEST - Check for any of multiple valid texts
it('should display page content', () => {
  cy.navigateTo('/app/dashboard');
  cy.assertContainsAny(['Dashboard', 'Overview', 'Welcome']);
});

// ✅ BEST - Check for element with fallback selectors
it('should display table', () => {
  cy.navigateTo('/app/users');
  cy.assertHasElement(['[data-testid="users-table"]', 'table', '[class*="table"]']);
});

// ✅ BEST - Statistics cards assertion
it('should display billing statistics', () => {
  cy.navigateTo('/app/billing');
  cy.assertStatCards(['Outstanding', 'This Month', 'Collected', 'Success Rate']);
});

// ✅ BEST - Tab content assertion
it('should switch to Invoices tab', () => {
  cy.navigateTo('/app/billing');
  cy.clickTab('Invoices');
  cy.assertTabContent('Invoices', { hasTable: true });
});

// ✅ BEST - Modal assertion
it('should open create modal', () => {
  cy.navigateTo('/app/billing');
  cy.clickButton('Create Invoice');
  cy.assertModalVisible('Create Invoice');
});

// ✅ BEST - Action button assertion
it('should have action button', () => {
  cy.navigateTo('/app/billing');
  cy.assertActionButton('Create Invoice');
});
```

### Direct Assertions

```typescript
// ✅ Verify specific element exists
cy.get('[data-testid="user-table"]').should('be.visible');

// ✅ Verify specific content
cy.get('[data-testid="page-title"]').should('contain.text', 'Dashboard');

// ✅ Verify element state
cy.get('[data-testid="submit-btn"]').should('not.be.disabled');

// ✅ Verify multiple conditions
cy.get('[data-testid="user-row"]')
  .should('have.length', 5)
  .first()
  .should('contain.text', 'John Doe');
```

### Bad Assertions (Anti-Patterns)

```typescript
// ❌ NEVER - Meaningless assertion
cy.get('body').should('be.visible');

// ❌ NEVER - Text-based checks on body with conditional logging
cy.get('body').then($body => {
  if ($body.text().includes('Dashboard')) {
    cy.log('Dashboard loaded');  // Logs but doesn't fail!
  }
});
cy.get('body').should('be.visible');  // Fallback that always passes

// ❌ NEVER - Class-based selectors
cy.get('[class*="success"]').should('exist');

// ❌ NEVER - Conditional element checks that don't fail
cy.get('body').then($body => {
  const button = $body.find('button:contains("Save")');
  if (button.length > 0) {
    cy.wrap(button).click();
    cy.log('Button clicked');  // Only logs, test passes regardless
  }
});
```

---

## Anti-Patterns to Avoid

### ❌ Defensive Non-Assertions

```typescript
// BAD - This never fails, just logs
cy.get('body').then($body => {
  const hasContent = $body.text().includes('Profile');
  if (hasContent) {
    cy.log('Profile loaded');  // This doesn't assert anything!
  }
});
cy.get('body').should('be.visible');  // Fallback is meaningless
```

**Fix:**
```typescript
// GOOD - This will fail if element doesn't exist
cy.get('[data-testid="profile-container"]').should('be.visible');
cy.get('[data-testid="profile-name"]').should('contain.text', expectedName);
```

### ❌ Hardcoded Credentials in Tests

```typescript
// BAD - Credentials scattered across files
cy.get('[data-testid="email-input"]').type('demo@democompany.com');
cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
```

**Fix:**
```typescript
// GOOD - Use standardized login
cy.standardTestSetup();
// or
cy.loginAsDemo();
```

### ❌ Arbitrary Wait Times

```typescript
// BAD - Unreliable timing
cy.wait(2000);
cy.get('[data-testid="content"]');
```

**Fix:**
```typescript
// GOOD - Wait for specific condition
cy.intercept('GET', '/api/v1/content*').as('getContent');
cy.visit('/app/content');
cy.wait('@getContent');
cy.get('[data-testid="content"]').should('be.visible');
```

### ❌ Class-Based Selectors

```typescript
// BAD - Classes change frequently
cy.get('.btn-primary.large').click();
cy.get('[class*="modal"]').should('exist');
```

**Fix:**
```typescript
// GOOD - Stable test selectors
cy.get('[data-testid="submit-btn"]').click();
cy.get('[role="dialog"]').should('be.visible');
```

---

## Credentials

Test credentials are configured in `cypress.env.json`:

- **Demo User**: Used by default with `cy.standardTestSetup()` and `cy.loginAsDemo()`
- **Admin**: Use `cy.loginAsRole('admin')`
- **Billing Manager**: Use `cy.loginAsRole('billing.manager')`
- **Account Member**: Use `cy.loginAsRole('account.member')`

**NEVER** hardcode credentials in test files.

---

## Quick Reference

### Minimal Test Template

```typescript
/// <reference types="cypress" />

describe('Feature Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  it('should load page correctly', () => {
    cy.navigateTo('/app/feature');
    cy.get('[data-testid="feature-container"]').should('be.visible');
  });
});

export {};
```

### With API Mocking

```typescript
describe('Feature with API Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['ai'] });
  });

  it('should handle API error', () => {
    cy.mockApiError('/api/v1/feature', 500, 'Server error');
    cy.navigateTo('/app/feature');
    cy.verifyPageLoaded();
  });
});
```

---

## Migration Guide

### Login Migration

**Before:**
```typescript
beforeEach(() => {
  cy.clearAppData();
  cy.setupApiIntercepts();
  cy.visit('/login');
  cy.get('[data-testid="email-input"]').type('demo@democompany.com');
  cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
  cy.get('[data-testid="login-submit-btn"]').click();
  cy.url().should('match', /\/(app|dashboard)/);
});
```

**After:**
```typescript
beforeEach(() => {
  cy.standardTestSetup();
});
```

### Page Navigation Migration

**Before (190 lines):**
```typescript
describe('Page Tests', () => {
  beforeEach(() => { /* login code */ });

  it('should navigate to page', () => {
    cy.visit('/app/billing');
    cy.url().should('include', '/billing');
    cy.get('body').should('be.visible');
  });

  it('should display content', () => {
    cy.visit('/app/billing');
    cy.get('body').then($body => {
      const hasContent = $body.text().includes('Billing');
      if (hasContent) {
        cy.log('Content displayed');
      }
    });
    cy.get('body').should('be.visible');
  });

  it('should display table', () => {
    cy.visit('/app/billing');
    cy.get('body').then($body => {
      const hasTable = $body.find('table').length > 0;
      if (hasTable) {
        cy.log('Table found');
      }
    });
    cy.get('body').should('be.visible');
  });
});
```

**After (40 lines):**
```typescript
describe('Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  it('should navigate to page', () => {
    cy.assertPageReady('/app/billing', 'Billing');
  });

  it('should display content', () => {
    cy.navigateTo('/app/billing');
    cy.assertContainsAny(['Billing', 'Invoices', 'Payments']);
  });

  it('should display table', () => {
    cy.navigateTo('/app/billing');
    cy.assertHasElement(['table', '[data-testid="billing-table"]']);
  });
});
```

### Complete Test File Migration Example

**Before (full file ~600 lines):**
```typescript
describe('Business Billing', () => {
  beforeEach(() => {
    cy.clearAppData();
    // ... 10 lines of login code
  });

  it('should navigate to billing', () => {
    cy.visit('/app/business/billing');
    cy.get('body').then($body => {
      if ($body.text().includes('Billing')) {
        cy.log('Billing page loaded');
      }
    });
    cy.get('body').should('be.visible');
  });

  it('should display statistics', () => {
    cy.visit('/app/business/billing');
    cy.get('body').then($body => {
      const hasStats = $body.text().includes('Outstanding') ||
                       $body.text().includes('Collected');
      if (hasStats) {
        cy.log('Stats displayed');
      }
    });
    cy.get('body').should('be.visible');
  });

  // ... 50+ similar tests
});
```

**After (full file ~180 lines):**
```typescript
describe('Business Billing Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Page Navigation', () => {
    it('should navigate to Billing page', () => {
      cy.assertPageReady('/app/business/billing', 'Billing');
    });

    it('should display breadcrumbs', () => {
      cy.navigateTo('/app/business/billing');
      cy.assertContainsAny(['Dashboard', 'Business', 'Billing']);
    });
  });

  describe('Statistics Cards', () => {
    it('should display billing statistics', () => {
      cy.navigateTo('/app/business/billing');
      cy.assertStatCards(['Outstanding', 'This Month', 'Collected', 'Success Rate']);
    });
  });

  describe('Tab Navigation', () => {
    it('should switch to Invoices tab', () => {
      cy.navigateTo('/app/business/billing');
      cy.clickTab('Invoices');
      cy.assertTabContent('Invoices', { hasTable: true });
    });
  });

  describe('Responsive Design', () => {
    it('should display properly across viewports', () => {
      cy.testResponsiveDesign('/app/business/billing', { checkContent: 'Billing' });
    });
  });
});

export {};
```
