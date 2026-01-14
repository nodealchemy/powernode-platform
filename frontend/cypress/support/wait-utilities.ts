/// <reference types="cypress" />

/**
 * Shared Cypress Wait Utilities
 *
 * Provides common API intercepts and page load utilities to replace
 * hardcoded cy.wait() calls with proper intercept-based waiting.
 */

declare global {
  namespace Cypress {
    interface Chainable {
      /**
       * Set up common API intercepts for the application
       * @example cy.setupApiIntercepts()
       */
      setupApiIntercepts(): Chainable<void>;

      /**
       * Wait for page to fully load (loading spinner gone, container visible)
       * @example cy.waitForPageLoad()
       */
      waitForPageLoad(): Chainable<void>;

      /**
       * Wait for a table to load with data
       * @example cy.waitForTableLoad()
       */
      waitForTableLoad(): Chainable<void>;

      /**
       * Wait for modal to be visible
       * @example cy.waitForModal()
       */
      waitForModal(): Chainable<void>;

      /**
       * Wait for modal to close
       * @example cy.waitForModalClose()
       */
      waitForModalClose(): Chainable<void>;

      /**
       * Wait for DOM to stabilize (no new elements appearing)
       * @example cy.waitForStableDOM()
       */
      waitForStableDOM(): Chainable<void>;

      /**
       * Set up AI-related API intercepts
       * @example cy.setupAiIntercepts()
       */
      setupAiIntercepts(): Chainable<void>;

      /**
       * Set up admin-related API intercepts
       * @example cy.setupAdminIntercepts()
       */
      setupAdminIntercepts(): Chainable<void>;

      /**
       * Set up devops-related API intercepts
       * @example cy.setupDevopsIntercepts()
       */
      setupDevopsIntercepts(): Chainable<void>;

      /**
       * Set up system-related API intercepts
       * @example cy.setupSystemIntercepts()
       */
      setupSystemIntercepts(): Chainable<void>;

      /**
       * Set up marketplace-related API intercepts
       * @example cy.setupMarketplaceIntercepts()
       */
      setupMarketplaceIntercepts(): Chainable<void>;

      /**
       * Set up content-related API intercepts
       * @example cy.setupContentIntercepts()
       */
      setupContentIntercepts(): Chainable<void>;

      /**
       * Set up privacy-related API intercepts
       * @example cy.setupPrivacyIntercepts()
       */
      setupPrivacyIntercepts(): Chainable<void>;

      /**
       * Wait for element to be actionable (visible and not covered)
       * @example cy.waitForActionable('[data-testid="button"]')
       */
      waitForActionable(selector: string): Chainable<JQuery<HTMLElement>>;
    }
  }
}

// Common API intercepts
Cypress.Commands.add('setupApiIntercepts', () => {
  // User and account endpoints
  cy.intercept('GET', '/api/v1/users*').as('getUsers');
  cy.intercept('GET', '/api/v1/users/me*').as('getCurrentUser');
  cy.intercept('GET', '/api/v1/account*').as('getAccount');
  cy.intercept('GET', '/api/v1/notifications*').as('getNotifications');

  // Permission and role endpoints
  cy.intercept('GET', '/api/v1/permissions*').as('getPermissions');
  cy.intercept('GET', '/api/v1/roles*').as('getRoles');

  // Common CRUD operations
  cy.intercept('POST', '/api/v1/**').as('createResource');
  cy.intercept('PUT', '/api/v1/**').as('updateResource');
  cy.intercept('PATCH', '/api/v1/**').as('patchResource');
  cy.intercept('DELETE', '/api/v1/**').as('deleteResource');
});

// AI-related intercepts
Cypress.Commands.add('setupAiIntercepts', () => {
  cy.intercept('GET', '/api/v1/workflows*').as('getWorkflows');
  cy.intercept('GET', '/api/v1/workflows/*').as('getWorkflow');
  cy.intercept('POST', '/api/v1/workflows*').as('createWorkflow');
  cy.intercept('PUT', '/api/v1/workflows/*').as('updateWorkflow');
  cy.intercept('DELETE', '/api/v1/workflows/*').as('deleteWorkflow');

  cy.intercept('GET', '/api/v1/ai/agents*').as('getAgents');
  cy.intercept('GET', '/api/v1/ai/agents/*').as('getAgent');
  cy.intercept('GET', '/api/v1/ai/conversations*').as('getConversations');
  cy.intercept('GET', '/api/v1/ai/prompts*').as('getPrompts');
  cy.intercept('GET', '/api/v1/ai/providers*').as('getProviders');
  cy.intercept('GET', '/api/v1/ai/contexts*').as('getContexts');
  cy.intercept('GET', '/api/v1/ai/agent-teams*').as('getAgentTeams');

  cy.intercept('POST', '/api/v1/workflows/*/execute*').as('executeWorkflow');
  cy.intercept('GET', '/api/v1/workflows/*/executions*').as('getExecutions');
});

// Admin-related intercepts
Cypress.Commands.add('setupAdminIntercepts', () => {
  cy.intercept('GET', '/api/v1/admin/settings*').as('getAdminSettings');
  cy.intercept('PUT', '/api/v1/admin/settings*').as('updateAdminSettings');
  cy.intercept('GET', '/api/v1/admin/users*').as('getAdminUsers');
  cy.intercept('GET', '/api/v1/admin/roles*').as('getAdminRoles');
  cy.intercept('POST', '/api/v1/admin/roles*').as('createRole');
  cy.intercept('PUT', '/api/v1/admin/roles/*').as('updateRole');
  cy.intercept('DELETE', '/api/v1/admin/roles/*').as('deleteRole');
  cy.intercept('GET', '/api/v1/admin/invitations*').as('getInvitations');
  cy.intercept('GET', '/api/v1/admin/audit-logs*').as('getAuditLogs');
});

// DevOps-related intercepts
Cypress.Commands.add('setupDevopsIntercepts', () => {
  cy.intercept('GET', '/api/v1/webhooks*').as('getWebhooks');
  cy.intercept('GET', '/api/v1/webhooks/*').as('getWebhook');
  cy.intercept('POST', '/api/v1/webhooks*').as('createWebhook');
  cy.intercept('PUT', '/api/v1/webhooks/*').as('updateWebhook');
  cy.intercept('DELETE', '/api/v1/webhooks/*').as('deleteWebhook');

  cy.intercept('GET', '/api/v1/api-keys*').as('getApiKeys');
  cy.intercept('GET', '/api/v1/integrations*').as('getIntegrations');
  cy.intercept('GET', '/api/v1/deployments*').as('getDeployments');
});

// System-related intercepts
Cypress.Commands.add('setupSystemIntercepts', () => {
  cy.intercept('GET', '/api/v1/workers*').as('getWorkers');
  cy.intercept('GET', '/api/v1/workers/*').as('getWorker');
  cy.intercept('POST', '/api/v1/workers/*/restart*').as('restartWorker');
  cy.intercept('GET', '/api/v1/storage*').as('getStorage');
  cy.intercept('GET', '/api/v1/audit-logs*').as('getAuditLogs');
  cy.intercept('GET', '/api/v1/system/health*').as('getSystemHealth');
});

// Marketplace-related intercepts
Cypress.Commands.add('setupMarketplaceIntercepts', () => {
  cy.intercept('GET', '/api/v1/marketplace*').as('getMarketplace');
  cy.intercept('GET', '/api/v1/marketplace/items*').as('getMarketplaceItems');
  cy.intercept('GET', '/api/v1/marketplace/items/*').as('getMarketplaceItem');
  cy.intercept('POST', '/api/v1/marketplace/items/*/install*').as('installItem');
  cy.intercept('DELETE', '/api/v1/marketplace/items/*/uninstall*').as('uninstallItem');
});

// Content-related intercepts
Cypress.Commands.add('setupContentIntercepts', () => {
  cy.intercept('GET', '/api/v1/pages*').as('getPages');
  cy.intercept('GET', '/api/v1/pages/*').as('getPage');
  cy.intercept('POST', '/api/v1/pages*').as('createPage');
  cy.intercept('PUT', '/api/v1/pages/*').as('updatePage');
  cy.intercept('DELETE', '/api/v1/pages/*').as('deletePage');
  cy.intercept('GET', '/api/v1/kb*').as('getKnowledgeBase');
  cy.intercept('GET', '/api/v1/blog*').as('getBlog');
});

// Privacy-related intercepts
Cypress.Commands.add('setupPrivacyIntercepts', () => {
  cy.intercept('GET', '/api/v1/privacy*').as('getPrivacy');
  cy.intercept('GET', '/api/v1/privacy/consents*').as('getConsents');
  cy.intercept('PUT', '/api/v1/privacy/consents*').as('updateConsents');
  cy.intercept('GET', '/api/v1/privacy/data-export*').as('getDataExport');
  cy.intercept('POST', '/api/v1/privacy/data-export*').as('requestDataExport');
  cy.intercept('DELETE', '/api/v1/privacy/data*').as('deleteData');
});

// Wait for page load (loading spinner gone, page container visible)
Cypress.Commands.add('waitForPageLoad', () => {
  // Wait for any loading spinners to disappear
  cy.get('[data-testid="loading-spinner"], .loading-spinner, [data-loading="true"]', { timeout: 100 })
    .should('not.exist')
    .then({ timeout: 100 }, () => {}); // Ignore if not found

  // Wait for page container to be visible
  cy.get('[data-testid="page-container"], [data-testid="page-content"], main', { timeout: 10000 })
    .should('be.visible');
});

// Wait for table to load with data
Cypress.Commands.add('waitForTableLoad', () => {
  // Wait for table to exist and have rows
  cy.get('table tbody tr, [data-testid="table-row"], [role="row"]', { timeout: 10000 })
    .should('exist');

  // Ensure loading states are cleared
  cy.get('[data-testid="table-loading"], [data-loading="true"]', { timeout: 100 })
    .should('not.exist')
    .then({ timeout: 100 }, () => {}); // Ignore if not found
});

// Wait for modal to be visible
Cypress.Commands.add('waitForModal', () => {
  cy.get('[data-testid="modal"], [role="dialog"], .modal', { timeout: 10000 })
    .should('be.visible');
});

// Wait for modal to close
Cypress.Commands.add('waitForModalClose', () => {
  cy.get('[data-testid="modal"], [role="dialog"], .modal', { timeout: 10000 })
    .should('not.exist');
});

// Wait for DOM to stabilize (no rapid changes)
Cypress.Commands.add('waitForStableDOM', () => {
  // Simple approach: wait a brief moment for React to finish rendering
  // then verify the body is visible and stable
  cy.wait(100); // Brief pause for React reconciliation
  cy.get('body').should('be.visible');
  // Ensure no loading spinners are active
  cy.get('[data-testid="loading-spinner"], .loading-spinner, .animate-spin', { timeout: 100 })
    .should('not.exist')
    .then({ timeout: 100 }, () => {}); // Ignore if not found
});

// Wait for element to be actionable (visible and not covered by overlays)
Cypress.Commands.add('waitForActionable', (selector: string) => {
  // First ensure any overlays are gone
  cy.get('[data-testid="modal-overlay"], .modal-backdrop, [data-testid="loading-overlay"]', { timeout: 100 })
    .should('not.exist')
    .then({ timeout: 100 }, () => {}); // Ignore if not found

  // Then wait for element to be visible and return it
  return cy.get(selector, { timeout: 10000 }).should('be.visible');
});

export {};
