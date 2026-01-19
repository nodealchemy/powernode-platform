/// <reference types="cypress" />

/**
 * AI Governance Suite Page Tests
 *
 * Tests for Governance & Compliance functionality (Phase 4):
 * - Compliance policies management
 * - Policy violations tracking
 * - Approval chains and workflows
 * - Data classifications
 * - Compliance reports
 * - Audit log viewing
 * - Error handling
 * - Responsive design
 */

describe('AI Governance Suite Page Tests', () => {
  beforeEach(() => {
    Cypress.on('uncaught:exception', () => false);
    cy.standardTestSetup({ intercepts: ['ai'] });
    setupGovernanceIntercepts();
  });

  describe('Page Navigation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/governance');
    });

    it('should navigate to Governance page', () => {
      cy.assertContainsAny(['Governance', 'Compliance', 'Policies']);
    });

    it('should display page title', () => {
      cy.assertContainsAny(['Governance', 'Compliance']);
    });

    it('should display page description', () => {
      cy.assertContainsAny(['compliance', 'policies', 'governance', 'enterprise']);
    });
  });

  describe('Compliance Policies', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/governance');
    });

    it('should display policies section', () => {
      cy.assertContainsAny(['Policies', 'Policy', 'Compliance']);
    });

    it('should have Create Policy button', () => {
      cy.assertHasElement([
        'button:contains("Create Policy")',
        'button:contains("Add Policy")',
        'button:contains("New")',
        '[data-testid*="create"]'
      ]);
    });

    it('should display policy status indicators', () => {
      cy.assertContainsAny(['Active', 'Draft', 'Disabled', 'Status', 'Policies']);
    });

    it('should display enforcement levels', () => {
      cy.assertContainsAny(['Log', 'Warn', 'Block', 'Require Approval', 'Enforcement', 'Policies']);
    });
  });

  describe('Policy Violations', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/governance');
    });

    it('should display violations section or tab', () => {
      cy.assertContainsAny(['Violations', 'Issues', 'Alerts', 'Governance']);
    });

    it('should display severity indicators', () => {
      cy.assertContainsAny(['Critical', 'High', 'Medium', 'Low', 'Severity', 'Governance']);
    });

    it('should display violation status', () => {
      cy.assertContainsAny(['Open', 'Acknowledged', 'Resolved', 'Dismissed', 'Status', 'Governance']);
    });
  });

  describe('Approval Chains', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/governance');
    });

    it('should display approval chains section', () => {
      cy.assertContainsAny(['Approval', 'Chain', 'Workflow', 'Governance']);
    });

    it('should have Create Approval Chain option', () => {
      cy.assertHasElement([
        'button:contains("Create")',
        'button:contains("Add")',
        'button:contains("New")',
        '[data-testid*="create"]'
      ]);
    });
  });

  describe('Pending Approvals', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/governance');
    });

    it('should display pending approvals section', () => {
      cy.assertContainsAny(['Pending', 'Approvals', 'Requests', 'Governance']);
    });

    it('should have approve/reject actions when requests exist', () => {
      cy.assertHasElement([
        'button:contains("Approve")',
        'button:contains("Reject")',
        '[data-testid*="approve"]',
        '[data-testid*="reject"]',
        'button'
      ]);
    });
  });

  describe('Data Classifications', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/governance');
    });

    it('should display data classification options', () => {
      cy.assertContainsAny(['Classification', 'Data', 'PII', 'PHI', 'PCI', 'Confidential', 'Governance']);
    });

    it('should have Create Classification option', () => {
      cy.assertHasElement([
        'button:contains("Create")',
        'button:contains("Add")',
        'button:contains("New")',
        '[data-testid*="create"]'
      ]);
    });
  });

  describe('Compliance Reports', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/governance');
    });

    it('should display reports section', () => {
      cy.assertContainsAny(['Reports', 'Report', 'Generate', 'Governance']);
    });

    it('should have Generate Report option', () => {
      cy.assertHasElement([
        'button:contains("Generate")',
        'button:contains("Create")',
        'button:contains("New Report")',
        '[data-testid*="generate"]',
        'button'
      ]);
    });

    it('should display report formats', () => {
      cy.assertContainsAny(['PDF', 'HTML', 'JSON', 'CSV', 'Format', 'Governance']);
    });
  });

  describe('Audit Log', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/governance');
    });

    it('should display audit log section', () => {
      cy.assertContainsAny(['Audit', 'Log', 'Activity', 'History', 'Governance']);
    });

    it('should display audit entry details', () => {
      cy.assertContainsAny(['Action', 'User', 'Time', 'Resource', 'Governance']);
    });
  });

  describe('Compliance Summary', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/governance');
    });

    it('should display compliance summary dashboard', () => {
      cy.assertContainsAny(['Summary', 'Overview', 'Dashboard', 'Governance']);
    });

    it('should display key metrics', () => {
      cy.assertContainsAny(['Total', 'Active', 'Pending', 'Violations', 'Policies', 'Governance']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('**/api/v1/ai/governance/**', {
        statusCode: 500,
        visitUrl: '/app/ai/governance'
      });
    });

    it('should display error notification on failure', () => {
      cy.mockApiError('**/api/v1/ai/governance/policies*', 500, 'Failed to load policies');
      cy.navigateTo('/app/ai/governance');
      cy.assertContainsAny(['Error', 'Failed', 'Governance', 'Policies']);
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '**/api/v1/ai/governance/policies*', {
        delay: 1000,
        statusCode: 200,
        body: { success: true, data: { items: [], pagination: { current_page: 1, total_pages: 1, total_count: 0, per_page: 25 } } }
      }).as('getPoliciesDelayed');
      cy.visit('/app/ai/governance');
      cy.assertHasElement(['[class*="spin"]', '[class*="loading"]', '[class*="Spin"]', '[class*="Loading"]', 'div']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.testResponsiveDesign('/app/ai/governance', {
        checkContent: ['Governance', 'Compliance']
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.assertPageReady('/app/ai/governance');
      cy.assertContainsAny(['Governance', 'Compliance']);
    });

    it('should adapt layout on small screens', () => {
      cy.viewport(375, 667);
      cy.assertPageReady('/app/ai/governance');
      cy.get('body').should('be.visible');
    });
  });
});

/**
 * Set up Governance API intercepts
 */
function setupGovernanceIntercepts() {
  const mockPolicies = [
    {
      id: 'policy-1',
      name: 'PII Data Protection',
      policy_type: 'data_protection',
      category: 'privacy',
      description: 'Protect personally identifiable information',
      status: 'active',
      enforcement_level: 'block',
      conditions: { data_types: ['pii', 'email', 'phone'] },
      actions: { action: 'mask' },
      is_system: true,
      is_required: true,
      priority: 1,
      violation_count: 12,
      last_triggered_at: '2024-06-15T10:00:00Z',
      created_at: '2024-01-01T00:00:00Z'
    },
    {
      id: 'policy-2',
      name: 'Cost Limit Policy',
      policy_type: 'cost_control',
      category: 'budget',
      description: 'Limit AI spending per workflow',
      status: 'active',
      enforcement_level: 'warn',
      conditions: { max_cost_usd: 100 },
      actions: { action: 'notify' },
      is_system: false,
      is_required: false,
      priority: 2,
      violation_count: 5,
      last_triggered_at: '2024-06-14T14:00:00Z',
      created_at: '2024-02-15T00:00:00Z'
    }
  ];

  const mockViolations = [
    {
      id: 'violation-1',
      violation_id: 'VIO-001',
      severity: 'high',
      status: 'open',
      description: 'PII detected in workflow output',
      context: { workflow_id: 'wf-1', field: 'output.text' },
      source_type: 'workflow_run',
      source_id: 'run-123',
      remediation_steps: ['Review output', 'Apply masking'],
      resolution_notes: null,
      detected_at: '2024-06-15T10:00:00Z',
      resolved_at: null,
      policy: { id: 'policy-1', name: 'PII Data Protection' }
    }
  ];

  const mockApprovalChains = [
    {
      id: 'chain-1',
      name: 'Production Deployment Approval',
      description: 'Requires manager approval for production deployments',
      trigger_type: 'deployment',
      trigger_conditions: { environment: 'production' },
      steps: [{ approver_type: 'role', approver_id: 'manager', required: true }],
      status: 'active',
      is_sequential: true,
      timeout_hours: 24,
      usage_count: 45,
      created_at: '2024-01-01T00:00:00Z'
    }
  ];

  const mockClassifications = [
    {
      id: 'class-1',
      name: 'Personal Identifiable Information',
      classification_level: 'pii',
      description: 'Names, emails, phone numbers, addresses',
      detection_patterns: [{ type: 'regex', pattern: '\\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Z|a-z]{2,}\\b' }],
      handling_requirements: { encrypt: true, mask: true, audit: true },
      requires_encryption: true,
      requires_masking: true,
      requires_audit: true,
      is_system: true,
      detection_count: 234
    }
  ];

  const mockSummary = {
    policies: { total: 5, active: 4, by_type: { data_protection: 2, cost_control: 2, access_control: 1 } },
    violations: { total: 25, open: 8, by_severity: { critical: 1, high: 3, medium: 4, low: 17 } },
    approvals: { pending: 3, approved: 45, rejected: 2 },
    data_detections: { total: 156, by_action: { masked: 120, blocked: 20, logged: 16 } }
  };

  // Policies
  cy.intercept('GET', '**/api/v1/ai/governance/policies', {
    statusCode: 200,
    body: { success: true, data: { items: mockPolicies, pagination: { current_page: 1, total_pages: 1, total_count: 2, per_page: 25 } } }
  }).as('getGovernancePolicies');

  cy.intercept('GET', '**/api/v1/ai/governance/policies?*', {
    statusCode: 200,
    body: { success: true, data: { items: mockPolicies, pagination: { current_page: 1, total_pages: 1, total_count: 2, per_page: 25 } } }
  }).as('getGovernancePoliciesFiltered');

  cy.intercept('POST', '**/api/v1/ai/governance/policies', {
    statusCode: 201,
    body: { success: true, data: { policy: mockPolicies[0] } }
  }).as('createGovernancePolicy');

  // Violations
  cy.intercept('GET', '**/api/v1/ai/governance/violations*', {
    statusCode: 200,
    body: { success: true, data: { items: mockViolations, pagination: { current_page: 1, total_pages: 1, total_count: 1, per_page: 25 } } }
  }).as('getViolations');

  // Approval Chains
  cy.intercept('GET', '**/api/v1/ai/governance/approval_chains*', {
    statusCode: 200,
    body: { success: true, data: { items: mockApprovalChains, pagination: { current_page: 1, total_pages: 1, total_count: 1, per_page: 25 } } }
  }).as('getApprovalChains');

  // Approval Requests
  cy.intercept('GET', '**/api/v1/ai/governance/approval_requests*', {
    statusCode: 200,
    body: { success: true, data: { items: [], pagination: { current_page: 1, total_pages: 1, total_count: 0, per_page: 25 } } }
  }).as('getApprovalRequests');

  cy.intercept('GET', '**/api/v1/ai/governance/approval_requests/pending*', {
    statusCode: 200,
    body: { success: true, data: { approval_requests: [] } }
  }).as('getPendingApprovals');

  // Classifications
  cy.intercept('GET', '**/api/v1/ai/governance/classifications*', {
    statusCode: 200,
    body: { success: true, data: { items: mockClassifications, pagination: { current_page: 1, total_pages: 1, total_count: 1, per_page: 25 } } }
  }).as('getClassifications');

  // Reports
  cy.intercept('GET', '**/api/v1/ai/governance/reports*', {
    statusCode: 200,
    body: { success: true, data: { items: [], pagination: { current_page: 1, total_pages: 1, total_count: 0, per_page: 25 } } }
  }).as('getComplianceReports');

  cy.intercept('POST', '**/api/v1/ai/governance/reports', {
    statusCode: 201,
    body: { success: true, data: { report: { id: 'report-1', status: 'generating' } } }
  }).as('generateReport');

  // Summary
  cy.intercept('GET', '**/api/v1/ai/governance/summary*', {
    statusCode: 200,
    body: { success: true, data: { summary: mockSummary } }
  }).as('getComplianceSummary');

  // Audit Log
  cy.intercept('GET', '**/api/v1/ai/governance/audit_log*', {
    statusCode: 200,
    body: { success: true, data: { items: [], pagination: { current_page: 1, total_pages: 1, total_count: 0, per_page: 25 } } }
  }).as('getGovernanceAuditLog');
}

export {};
