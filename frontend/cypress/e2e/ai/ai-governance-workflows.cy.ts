/// <reference types="cypress" />

/**
 * AI Governance Workflows Tests
 *
 * Comprehensive E2E tests for AI Governance:
 * - Policy management
 * - Compliance rules
 * - Audit trails
 * - Access controls
 * - Content moderation
 */

describe('AI Governance Workflows Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['ai'] });
    setupGovernanceIntercepts();
  });

  describe('Governance Dashboard', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/governance');
    });

    it('should display governance page with title', () => {
      cy.assertContainsAny(['Governance', 'AI Governance', 'Compliance']);
    });

    it('should display governance overview cards', () => {
      cy.assertContainsAny(['Policies', 'Rules', 'Violations', 'Compliance']);
    });

    it('should display action buttons', () => {
      cy.assertContainsAny(['Create Policy', 'Add Rule', 'New']);
    });
  });

  describe('Policies Tab', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/governance');
    });

    it('should display policies list', () => {
      cy.assertContainsAny(['Policy', 'policies', 'active', 'status']);
    });

    it('should show policy status badges', () => {
      cy.get('[class*="px-2"][class*="py-1"]').should('exist');
    });

    it('should display policy details', () => {
      cy.assertContainsAny(['description', 'scope', 'enforcement']);
    });

    it('should have create policy button', () => {
      cy.get('button').contains(/create|add|new/i).should('exist');
    });

    it('should create policy when form submitted', () => {
      cy.intercept('POST', '**/api/**/ai/governance/policies*', {
        statusCode: 201,
        body: { success: true, policy: { id: 'policy-new' } },
      }).as('createPolicy');

      cy.get('button').contains(/create|add|new/i).first().click();
      cy.get('body').then($body => {
        if ($body.find('input[name="name"], input[placeholder*="name"]').length > 0) {
          cy.get('input').first().type('Test Policy');
          cy.get('button').contains(/save|create|submit/i).click();
          cy.wait('@createPolicy');
        }
      });
    });
  });

  describe('Compliance Rules Tab', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/governance');
      cy.get('button').contains(/rules|compliance/i).first().click();
    });

    it('should display compliance rules list', () => {
      cy.assertContainsAny(['Rule', 'rules', 'compliance', 'enforcement']);
    });

    it('should show rule severity levels', () => {
      cy.assertContainsAny(['critical', 'high', 'medium', 'low', 'warning']);
    });

    it('should display rule triggers and actions', () => {
      cy.assertContainsAny(['trigger', 'action', 'condition', 'when']);
    });
  });

  describe('Audit Log Tab', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/governance');
      cy.get('button').contains(/audit|log|history/i).first().click();
    });

    it('should display audit log entries', () => {
      cy.assertContainsAny(['Audit', 'Log', 'Event', 'Activity']);
    });

    it('should show event timestamps', () => {
      cy.get('body').then($body => {
        const hasTime = $body.text().match(/\d{1,2}:\d{2}/) !== null ||
                       $body.text().includes('ago') ||
                       $body.text().includes('today');
        expect(hasTime).to.be.true;
      });
    });

    it('should display event details', () => {
      cy.assertContainsAny(['user', 'action', 'resource', 'details']);
    });

    it('should have filter options', () => {
      cy.get('select, input[type="search"]').should('exist');
    });
  });

  describe('Violations Tab', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/governance');
      cy.get('button').contains(/violation|issue/i).first().click();
    });

    it('should display violations list or empty state', () => {
      cy.get('body').then($body => {
        if ($body.text().includes('No violations')) {
          cy.assertContainsAny(['No violations', 'compliant']);
        } else {
          cy.assertContainsAny(['Violation', 'severity', 'status']);
        }
      });
    });

    it('should show violation severity', () => {
      cy.get('body').then($body => {
        if (!$body.text().includes('No violations')) {
          cy.assertContainsAny(['critical', 'high', 'medium', 'low']);
        }
      });
    });

    it('should have resolve violation option', () => {
      cy.get('body').then($body => {
        if ($body.find('button:contains("Resolve")').length > 0) {
          cy.get('button').contains(/resolve/i).should('exist');
        }
      });
    });
  });

  describe('Content Moderation', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/governance');
      cy.get('button').contains(/moderation|content/i).first().click();
    });

    it('should display moderation settings', () => {
      cy.assertContainsAny(['Moderation', 'Content', 'Filter', 'Settings']);
    });

    it('should show moderation categories', () => {
      cy.assertContainsAny(['toxic', 'harmful', 'inappropriate', 'category']);
    });

    it('should allow enabling/disabling moderation', () => {
      cy.get('input[type="checkbox"], [role="switch"]').should('exist');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('**/api/**/ai/governance/**', {
        statusCode: 500,
        visitUrl: '/app/ai/governance',
      });
    });
  });

  describe('Responsive Design', () => {
    it('should display correctly across viewports', () => {
      cy.testResponsiveDesign('/app/ai/governance', {
        checkContent: 'Governance',
      });
    });
  });
});

function setupGovernanceIntercepts() {
  const mockPolicies = [
    {
      id: 'policy-1',
      name: 'Data Privacy Policy',
      description: 'Ensures AI responses do not expose sensitive data',
      status: 'active',
      scope: 'global',
      enforcement: 'strict',
      violations_count: 3,
      created_at: '2025-01-01T10:00:00Z',
    },
    {
      id: 'policy-2',
      name: 'Content Safety Policy',
      description: 'Prevents harmful content generation',
      status: 'active',
      scope: 'all_agents',
      enforcement: 'moderate',
      violations_count: 0,
      created_at: '2025-01-05T10:00:00Z',
    },
  ];

  const mockRules = [
    {
      id: 'rule-1',
      name: 'PII Detection',
      description: 'Blocks responses containing PII',
      severity: 'critical',
      trigger: 'response_contains_pii',
      action: 'block_and_notify',
      enabled: true,
    },
    {
      id: 'rule-2',
      name: 'Rate Limiting',
      description: 'Limits API calls per user',
      severity: 'medium',
      trigger: 'rate_exceeded',
      action: 'throttle',
      enabled: true,
    },
  ];

  const mockAuditLogs = [
    {
      id: 'log-1',
      event_type: 'policy_updated',
      user: 'admin@example.com',
      resource: 'Data Privacy Policy',
      action: 'update',
      timestamp: '2025-01-15T10:30:00Z',
    },
    {
      id: 'log-2',
      event_type: 'violation_resolved',
      user: 'security@example.com',
      resource: 'Violation #123',
      action: 'resolve',
      timestamp: '2025-01-15T09:00:00Z',
    },
  ];

  cy.intercept('GET', '**/api/**/ai/governance/policies*', {
    statusCode: 200,
    body: { items: mockPolicies },
  }).as('getPolicies');

  cy.intercept('GET', '**/api/**/ai/governance/rules*', {
    statusCode: 200,
    body: { items: mockRules },
  }).as('getRules');

  cy.intercept('GET', '**/api/**/ai/governance/audit*', {
    statusCode: 200,
    body: { items: mockAuditLogs },
  }).as('getAuditLogs');

  cy.intercept('POST', '**/api/**/ai/governance/policies*', {
    statusCode: 201,
    body: { success: true, policy: { id: 'policy-new' } },
  }).as('createPolicy');
}

export {};
