/// <reference types="cypress" />

/**
 * Form Commands
 *
 * Standardized commands for form filling, submission, and validation.
 * Replaces duplicated form interaction patterns across test files.
 */

export interface FormFieldConfig {
  /** Field name or data-testid */
  name: string;
  /** Value to enter */
  value: string;
  /** Field type (default: text) */
  type?: 'text' | 'email' | 'password' | 'select' | 'checkbox' | 'radio' | 'textarea';
}

declare global {
  namespace Cypress {
    interface Chainable {
      /**
       * Fill a form with provided data
       * @example cy.fillForm({ email: 'user@example.com', password: 'secret' })
       */
      fillForm(formData: Record<string, string>): Chainable<void>;

      /**
       * Fill form fields with type configuration
       * @example cy.fillFormFields([{ name: 'email', value: 'user@example.com', type: 'email' }])
       */
      fillFormFields(fields: FormFieldConfig[]): Chainable<void>;

      /**
       * Submit a form
       * @example cy.submitForm()
       * @example cy.submitForm('login-form')
       */
      submitForm(formTestIdOrSelector?: string): Chainable<void>;

      /**
       * Clear all form fields
       * @example cy.clearForm()
       * @example cy.clearForm('registration-form')
       */
      clearForm(formSelector?: string): Chainable<void>;

      /**
       * Fill a single input field
       * @example cy.fillField('email', 'user@example.com')
       */
      fillField(fieldName: string, value: string): Chainable<void>;

      /**
       * Select option from a select element
       * @example cy.selectOption('country', 'United States')
       */
      selectOption(fieldName: string, optionText: string): Chainable<void>;

      /**
       * Check/uncheck a checkbox
       * @example cy.toggleCheckbox('terms', true)
       */
      toggleCheckbox(fieldName: string, checked: boolean): Chainable<void>;

      /**
       * Verify form field has error
       * @example cy.verifyFieldError('email', 'Invalid email address')
       */
      verifyFieldError(fieldName: string, errorMessage?: string): Chainable<void>;

      /**
       * Verify form has no errors
       * @example cy.verifyNoFormErrors()
       */
      verifyNoFormErrors(): Chainable<void>;

      /**
       * Wait for form to be ready (all fields enabled)
       * @example cy.waitForFormReady()
       */
      waitForFormReady(): Chainable<void>;

      /**
       * Verify form submission was successful
       * @example cy.verifyFormSuccess('Account created')
       */
      verifyFormSuccess(successMessage?: string): Chainable<void>;
    }
  }
}

// Get field selector based on name
const getFieldSelector = (fieldName: string): string => {
  const normalizedName = fieldName.toLowerCase().replace(/\s+/g, '-');
  return `[data-testid="${normalizedName}-input"], [data-testid="${fieldName}-input"], [name="${fieldName}"], [id="${fieldName}"], input[placeholder*="${fieldName}" i]`;
};

// Fill form with object data
Cypress.Commands.add('fillForm', (formData: Record<string, string>) => {
  Object.entries(formData).forEach(([field, value]) => {
    cy.fillField(field, value);
  });
});

// Fill form with typed field configuration
Cypress.Commands.add('fillFormFields', (fields: FormFieldConfig[]) => {
  fields.forEach(({ name, value, type = 'text' }) => {
    const selector = getFieldSelector(name);

    switch (type) {
      case 'select':
        cy.selectOption(name, value);
        break;
      case 'checkbox':
        cy.toggleCheckbox(name, value === 'true' || value === '1');
        break;
      case 'radio':
        cy.get(`[name="${name}"][value="${value}"]`).check();
        break;
      case 'textarea':
        cy.get(`textarea[name="${name}"], [data-testid="${name}-input"]`)
          .clear()
          .type(value);
        break;
      default:
        cy.get(selector).first().clear().type(value);
    }
  });
});

// Submit form
Cypress.Commands.add('submitForm', (formTestIdOrSelector?: string) => {
  if (formTestIdOrSelector) {
    // Submit specific form
    cy.get(`[data-testid="${formTestIdOrSelector}"], ${formTestIdOrSelector}`)
      .find('button[type="submit"], [data-testid="submit-btn"]')
      .click();
  } else {
    // Submit the visible form
    cy.get('button[type="submit"], [data-testid="submit-btn"]')
      .filter(':visible')
      .first()
      .click();
  }
});

// Clear form fields
Cypress.Commands.add('clearForm', (formSelector?: string) => {
  const selector = formSelector
    ? `${formSelector} input:not([type="hidden"]):not([type="submit"]), ${formSelector} textarea`
    : 'form input:not([type="hidden"]):not([type="submit"]), form textarea';

  cy.get(selector).each(($el) => {
    if ($el.attr('type') === 'checkbox' || $el.attr('type') === 'radio') {
      cy.wrap($el).uncheck({ force: true });
    } else {
      cy.wrap($el).clear();
    }
  });
});

// Fill a single field
Cypress.Commands.add('fillField', (fieldName: string, value: string) => {
  const selector = getFieldSelector(fieldName);

  cy.get('body').then(($body) => {
    // Find the first matching element
    const $field = $body.find(selector).first();

    if ($field.length === 0) {
      throw new Error(`Field not found: "${fieldName}". Tried selector: ${selector}`);
    }

    cy.wrap($field).should('be.visible').clear().type(value);
  });
});

// Select option from dropdown
Cypress.Commands.add('selectOption', (fieldName: string, optionText: string) => {
  const selector = `select[name="${fieldName}"], [data-testid="${fieldName}-select"]`;

  cy.get('body').then(($body) => {
    const $select = $body.find(selector);

    if ($select.is('select')) {
      // Native select element
      cy.get(selector).select(optionText);
    } else {
      // Custom dropdown (Headless UI, Radix, etc.)
      cy.get(selector).click();
      cy.get(`[role="option"]:contains("${optionText}"), [data-value="${optionText}"]`)
        .first()
        .click();
    }
  });
});

// Toggle checkbox
Cypress.Commands.add('toggleCheckbox', (fieldName: string, checked: boolean) => {
  const selector = `input[type="checkbox"][name="${fieldName}"], [data-testid="${fieldName}-checkbox"]`;

  if (checked) {
    cy.get(selector).check({ force: true });
  } else {
    cy.get(selector).uncheck({ force: true });
  }
});

// Verify field has error
Cypress.Commands.add('verifyFieldError', (fieldName: string, errorMessage?: string) => {
  const normalizedName = fieldName.toLowerCase().replace(/\s+/g, '-');
  const errorSelector = `[data-testid="${normalizedName}-error"], [data-testid="${fieldName}-error"], .field-error, [role="alert"]`;

  cy.get(errorSelector).should('be.visible');

  if (errorMessage) {
    cy.get(errorSelector).should('contain.text', errorMessage);
  }
});

// Verify form has no errors
Cypress.Commands.add('verifyNoFormErrors', () => {
  cy.get('[data-testid*="-error"], .field-error, .form-error, [role="alert"].error')
    .should('not.exist');
});

// Wait for form to be ready
Cypress.Commands.add('waitForFormReady', () => {
  // Wait for loading states to clear
  cy.get('[data-loading="true"], .loading').should('not.exist');

  // Ensure submit button is enabled
  cy.get('button[type="submit"]').should('not.be.disabled');
});

// Verify form submission success
Cypress.Commands.add('verifyFormSuccess', (successMessage?: string) => {
  if (successMessage) {
    cy.get('[data-testid="notification-container"], [role="alert"].success, .toast-success')
      .should('be.visible')
      .and('contain.text', successMessage);
  } else {
    // Verify no error state
    cy.get('body')
      .should('not.contain.text', 'Error')
      .and('not.contain.text', 'Failed');
  }
});

export {};
