/// <reference types="cypress" />

/**
 * AI → Control Page Tests
 *
 * Control replaces the Autonomy dashboard, the Governance page and Approval
 * Chains: a rail of seven leaves ("Control navigation"), each with at most
 * one row of path tabs. These tests visit the Control URLs and assert what
 * ControlPage renders, against intercepts shaped like the real governance
 * endpoints (each list wrapped as { <name>: [...], pagination }).
 */

const RULES = '/app/ai/control/policies/compliance-rules';
const AUDIT_LOG = '/app/ai/control/compliance-audit/audit-log';

describe('AI Control Page Tests', () => {
  beforeEach(() => {
    Cypress.on('uncaught:exception', () => false);
    cy.standardTestSetup({ intercepts: ['ai'] });
    setupGovernanceIntercepts();
  });

  describe('Page and rail', () => {
    it('opens a Control leaf from the bare path', () => {
      cy.assertPageReady('/app/ai/control');
      cy.contains('h1', 'Control');
      cy.location('pathname').should('match', /^\/app\/ai\/control\/[a-z-]+/);
    });

    it('shows the Control rail', () => {
      cy.assertPageReady('/app/ai/control');
      cy.get('nav[aria-label="Control navigation"]').should('exist');
    });
  });

  describe('Policies → Compliance rules', () => {
    beforeEach(() => {
      cy.assertPageReady(RULES);
    });

    it('lists the compliance policies', () => {
      cy.get('section[aria-label="Compliance policies"]').within(() => {
        cy.contains('PII Data Protection');
        cy.contains('Cost Limit Policy');
      });
    });

    it('lists violations with their policy', () => {
      cy.get('section[aria-label="Violations"]').within(() => {
        cy.contains('PII detected in workflow output');
        cy.contains('PII Data Protection');
      });
    });

    it('lists security events', () => {
      cy.get('section[aria-label="Security events"]').within(() => {
        cy.contains('login_failed');
      });
    });

    it('offers only the risk levels the server accepts', () => {
      cy.get('[role="group"][aria-label="Risk filter"] button')
        .then(($buttons) => [...$buttons].map((b) => b.textContent?.trim()))
        .should('deep.equal', ['All', 'critical', 'high', 'medium', 'low']);
    });

    it('sends the chosen risk level to the server', () => {
      // The first request is the unfiltered page load; the filter drives the second.
      cy.wait('@getSecurityEvents');
      cy.get('[role="group"][aria-label="Risk filter"]').contains('button', 'high').click();
      cy.wait('@getSecurityEvents').its('request.url').should('include', 'risk_level=high');
    });
  });

  describe('Compliance Audit → Audit log', () => {
    it('lists audit entries and filters by date', () => {
      cy.assertPageReady(AUDIT_LOG);
      cy.wait('@getGovernanceAuditLog');
      cy.contains('policy_violation_detected');
      cy.get('input[aria-label="Start date"]').type('2024-06-01');
      cy.contains('button', 'Apply').click();
      cy.wait('@getGovernanceAuditLog').its('request.url').should('include', 'start_date=2024-06-01');
    });
  });

  describe('Safety', () => {
    it('names Observability as the home of circuit breakers', () => {
      cy.assertPageReady('/app/ai/control/safety');
      cy.contains('Circuit breakers live in Observability → Circuit Breakers.');
    });
  });

  describe('Error Handling', () => {
    it('keeps the page up when the policies request fails', () => {
      cy.mockApiError('**/api/v1/ai/governance/policies*', 500, 'Failed to load policies');
      cy.navigateTo(RULES);
      cy.contains('h1', 'Control');
    });
  });

  describe('Responsive Design', () => {
    it('renders on a mobile viewport', () => {
      cy.viewport(375, 667);
      cy.assertPageReady(RULES);
      cy.contains('h1', 'Control');
    });
  });
});

/**
 * Intercepts shaped like GovernanceController's real payloads.
 */
function setupGovernanceIntercepts() {
  const pagination = (count: number) => ({ current_page: 1, total_pages: 1, total_count: count, per_page: 20 });

  const policies = [
    {
      id: 'policy-1', name: 'PII Data Protection', policy_type: 'data_access', category: 'privacy',
      description: 'Protect personally identifiable information', status: 'active', enforcement_level: 'block',
      conditions: {}, actions: {}, is_system: true, is_required: true, priority: 1, violation_count: 12,
      last_triggered_at: '2024-06-15T10:00:00Z', created_at: '2024-01-01T00:00:00Z',
    },
    {
      id: 'policy-2', name: 'Cost Limit Policy', policy_type: 'cost_limit', category: 'budget',
      description: 'Limit AI spending per workflow', status: 'active', enforcement_level: 'warn',
      conditions: {}, actions: {}, is_system: false, is_required: false, priority: 2, violation_count: 5,
      last_triggered_at: '2024-06-14T14:00:00Z', created_at: '2024-02-15T00:00:00Z',
    },
  ];

  const violations = [
    {
      id: 'violation-1', violation_id: 'VIO-001', severity: 'high', status: 'open',
      description: 'PII detected in workflow output', context: {}, source_type: 'workflow_run', source_id: 'run-123',
      remediation_steps: [], resolution_notes: null, detected_at: '2024-06-15T10:00:00Z', resolved_at: null,
      policy: { id: 'policy-1', name: 'PII Data Protection' },
    },
  ];

  const events = [
    {
      id: 'event-1', action: 'login_failed', resource_type: 'User', severity: 'high', risk_level: 'medium',
      source: 'web', ip_address: '10.0.0.9', created_at: '2024-06-15T09:00:00Z',
    },
  ];

  const entries = [
    {
      id: 'entry-1', entry_id: 'E-1', action_type: 'policy_violation_detected', resource_type: 'Ai::CompliancePolicy',
      resource_id: 'policy-1', outcome: 'blocked', description: 'Prompt blocked by policy', ip_address: '10.0.0.1',
      occurred_at: '2024-06-15T10:00:00Z', user_id: 'user-1',
    },
  ];

  cy.intercept('GET', '**/api/v1/ai/governance/policies*', {
    statusCode: 200, body: { success: true, data: { policies, pagination: pagination(2) } },
  }).as('getGovernancePolicies');

  cy.intercept('GET', '**/api/v1/ai/governance/violations*', {
    statusCode: 200, body: { success: true, data: { violations, pagination: pagination(1) } },
  }).as('getViolations');

  cy.intercept('GET', '**/api/v1/ai/governance/security_events*', {
    statusCode: 200, body: { success: true, data: { events, pagination: pagination(1) } },
  }).as('getSecurityEvents');

  cy.intercept('GET', '**/api/v1/ai/governance/audit_log*', {
    statusCode: 200, body: { success: true, data: { entries, pagination: pagination(1) } },
  }).as('getGovernanceAuditLog');

  cy.intercept('GET', '**/api/v1/ai/governance/summary*', {
    statusCode: 200,
    body: { success: true, data: { summary: {
      policies: { total: 2, active: 2, by_type: {} },
      violations: { total: 1, open: 1, by_severity: {} },
    } } },
  }).as('getComplianceSummary');
}

export {};
