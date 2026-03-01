/// <reference types="cypress" />

/**
 * AI Workflow Approval E2E Tests
 *
 * Tests for the /ai-workflows/approve/:token route which handles
 * step approval responses for AI workflows.
 */

describe('AI Workflow Approval Page Tests', () => {
  const mockApprovalDetails = {
    node_name: 'Review and Approve',
    workflow_name: 'Data Processing Pipeline',
    run_id: 'WF-RUN-456',
    trigger_type: 'manual',
    status: 'pending',
    expires_at: new Date(Date.now() + 3600000).toISOString(),
    time_remaining_seconds: 3600,
    requires_comment: false,
    approval_message: 'Please review the data transformation results before proceeding.',
    node_configuration: {
      node_type: 'approval',
    },
    workflow: {
      id: 'workflow-123',
      name: 'Data Processing Pipeline',
    },
    workflow_run: {
      id: 'run-789',
      run_id: 'WF-RUN-456',
      status: 'waiting_approval',
    },
  };

  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Loading State', () => {
    it('should display loading state while fetching approval details', () => {
      cy.intercept('GET', '**/ai_workflows/approval_tokens/*', {
        delay: 1000,
        statusCode: 200,
        body: { success: true, data: mockApprovalDetails },
      }).as('getApprovalDetails');

      cy.visit('/ai-workflows/approve/test-token-123');
      cy.contains('Loading approval details').should('be.visible');
    });
  });

  describe('Approval Details Display', () => {
    beforeEach(() => {
      cy.intercept('GET', '**/ai_workflows/approval_tokens/*', {
        statusCode: 200,
        body: { success: true, data: mockApprovalDetails },
      }).as('getApprovalDetails');
    });

    it('should display AI Workflow Approval Required title', () => {
      cy.visit('/ai-workflows/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('AI Workflow Approval Required').should('be.visible');
    });

    it('should display workflow name', () => {
      cy.visit('/ai-workflows/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('Data Processing Pipeline').should('be.visible');
    });

    it('should display step/node name', () => {
      cy.visit('/ai-workflows/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('Review and Approve').should('be.visible');
    });

    it('should display run ID', () => {
      cy.visit('/ai-workflows/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('WF-RUN-456').should('be.visible');
    });

    it('should display trigger type', () => {
      cy.visit('/ai-workflows/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('Manual trigger').should('be.visible');
    });

    it('should display approval message', () => {
      cy.visit('/ai-workflows/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('Please review the data transformation results').should('be.visible');
    });

    it('should display time remaining', () => {
      cy.visit('/ai-workflows/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('remaining').should('be.visible');
    });
  });

  describe('Approval Actions', () => {
    beforeEach(() => {
      cy.intercept('GET', '**/ai_workflows/approval_tokens/*', {
        statusCode: 200,
        body: { success: true, data: mockApprovalDetails },
      }).as('getApprovalDetails');
    });

    it('should display Approve and Reject buttons', () => {
      cy.visit('/ai-workflows/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('button', 'Approve').should('be.visible');
      cy.contains('button', 'Reject').should('be.visible');
    });

    it('should display comment textarea', () => {
      cy.visit('/ai-workflows/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.get('textarea').should('be.visible');
    });

    it('should successfully approve workflow step', () => {
      cy.intercept('POST', '**/ai_workflows/approval_tokens/*/approve', {
        statusCode: 200,
        body: { success: true, data: { message: 'Step approved successfully' } },
      }).as('approveStep');

      cy.visit('/ai-workflows/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('button', 'Approve').click();
      cy.wait('@approveStep');
      cy.contains('Step Approved').should('be.visible');
      cy.contains('workflow step has been approved').should('be.visible');
    });

    it('should successfully reject workflow step', () => {
      cy.intercept('POST', '**/ai_workflows/approval_tokens/*/reject', {
        statusCode: 200,
        body: { success: true, data: { message: 'Step rejected successfully' } },
      }).as('rejectStep');

      cy.visit('/ai-workflows/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('button', 'Reject').click();
      cy.wait('@rejectStep');
      cy.contains('Step Rejected').should('be.visible');
      cy.contains('workflow step has been rejected').should('be.visible');
    });

    it('should submit with optional comment', () => {
      cy.intercept('POST', '**/ai_workflows/approval_tokens/*/approve', {
        statusCode: 200,
        body: { success: true, data: { message: 'Step approved' } },
      }).as('approveStep');

      cy.visit('/ai-workflows/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.get('textarea').type('Reviewed the data - looks good to proceed');
      cy.contains('button', 'Approve').click();
      cy.wait('@approveStep');
      cy.contains('Step Approved').should('be.visible');
    });
  });

  describe('Required Comment', () => {
    const detailsWithRequiredComment = {
      ...mockApprovalDetails,
      requires_comment: true,
    };

    beforeEach(() => {
      cy.intercept('GET', '**/ai_workflows/approval_tokens/*', {
        statusCode: 200,
        body: { success: true, data: detailsWithRequiredComment },
      }).as('getApprovalDetails');
    });

    it('should show required indicator for comment when required', () => {
      cy.visit('/ai-workflows/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('Comment').should('be.visible');
      cy.get('label').contains('*').should('exist');
    });

    it('should show error notification when comment is required but empty', () => {
      cy.visit('/ai-workflows/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('button', 'Approve').click();
      cy.assertContainsAny(['Comment Required', 'provide a comment']);
    });
  });

  describe('Expired Approval', () => {
    const expiredDetails = {
      ...mockApprovalDetails,
      time_remaining_seconds: 0,
      expires_at: new Date(Date.now() - 3600000).toISOString(),
    };

    beforeEach(() => {
      cy.intercept('GET', '**/ai_workflows/approval_tokens/*', {
        statusCode: 200,
        body: { success: true, data: expiredDetails },
      }).as('getApprovalDetails');
    });

    it('should display expired message', () => {
      cy.visit('/ai-workflows/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('expired').should('be.visible');
    });

    it('should not show approve/reject buttons when expired', () => {
      cy.visit('/ai-workflows/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('button', 'Approve').should('not.exist');
      cy.contains('button', 'Reject').should('not.exist');
    });

    it('should show View in Dashboard button when expired', () => {
      cy.visit('/ai-workflows/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('View in Dashboard').should('be.visible');
    });
  });

  describe('Error States', () => {
    it('should display error for invalid token', () => {
      cy.intercept('GET', '**/ai_workflows/approval_tokens/*', {
        statusCode: 404,
        body: { success: false, error: 'Approval request not found' },
      }).as('getApprovalDetailsError');

      cy.visit('/ai-workflows/approve/invalid-token');
      cy.wait('@getApprovalDetailsError');
      cy.contains('Unable to Process Request').should('be.visible');
    });

    it('should display error for already processed approval', () => {
      cy.intercept('GET', '**/ai_workflows/approval_tokens/*', {
        statusCode: 400,
        body: { success: false, error: 'This approval has already been processed' },
      }).as('getApprovalDetailsError');

      cy.visit('/ai-workflows/approve/processed-token');
      cy.wait('@getApprovalDetailsError');
      cy.contains('Unable to Process Request').should('be.visible');
      // Note: Component shows HTTP status error instead of API error message
      cy.assertContainsAny(['already been processed', 'status code 400']);
    });

    it('should have Go to Workflows button on error', () => {
      cy.intercept('GET', '**/ai_workflows/approval_tokens/*', {
        statusCode: 404,
        body: { success: false, error: 'Not found' },
      }).as('getApprovalDetailsError');

      cy.visit('/ai-workflows/approve/invalid-token');
      cy.wait('@getApprovalDetailsError');
      cy.contains('Go to Workflows').should('be.visible');
    });
  });

  describe('Trigger Type Display', () => {
    it('should display schedule trigger type', () => {
      const scheduleTriggerDetails = {
        ...mockApprovalDetails,
        trigger_type: 'schedule',
      };

      cy.intercept('GET', '**/ai_workflows/approval_tokens/*', {
        statusCode: 200,
        body: { success: true, data: scheduleTriggerDetails },
      }).as('getApprovalDetails');

      cy.visit('/ai-workflows/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('Scheduled run').should('be.visible');
    });

    it('should display webhook trigger type', () => {
      const webhookTriggerDetails = {
        ...mockApprovalDetails,
        trigger_type: 'webhook',
      };

      cy.intercept('GET', '**/ai_workflows/approval_tokens/*', {
        statusCode: 200,
        body: { success: true, data: webhookTriggerDetails },
      }).as('getApprovalDetails');

      cy.visit('/ai-workflows/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('Webhook trigger').should('be.visible');
    });

    it('should display API trigger type', () => {
      const apiTriggerDetails = {
        ...mockApprovalDetails,
        trigger_type: 'api',
      };

      cy.intercept('GET', '**/ai_workflows/approval_tokens/*', {
        statusCode: 200,
        body: { success: true, data: apiTriggerDetails },
      }).as('getApprovalDetails');

      cy.visit('/ai-workflows/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('API trigger').should('be.visible');
    });
  });

  describe('Completion State', () => {
    beforeEach(() => {
      cy.intercept('GET', '**/ai_workflows/approval_tokens/*', {
        statusCode: 200,
        body: { success: true, data: mockApprovalDetails },
      }).as('getApprovalDetails');
    });

    it('should display View Workflow Run button after approval', () => {
      cy.intercept('POST', '**/ai_workflows/approval_tokens/*/approve', {
        statusCode: 200,
        body: { success: true, data: { message: 'Approved' } },
      }).as('approveStep');

      cy.visit('/ai-workflows/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('button', 'Approve').click();
      cy.wait('@approveStep');
      cy.contains('View Workflow Run').should('be.visible');
    });

    it('should navigate to workflow run when clicking View Workflow Run', () => {
      cy.intercept('POST', '**/ai_workflows/approval_tokens/*/approve', {
        statusCode: 200,
        body: { success: true, data: { message: 'Approved' } },
      }).as('approveStep');

      cy.visit('/ai-workflows/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('button', 'Approve').click();
      cy.wait('@approveStep');
      cy.contains('View Workflow Run').click();
      cy.url().should('include', '/app/ai/workflows/workflow-123/runs/run-789');
    });
  });

  describe('Responsive Layout', () => {
    beforeEach(() => {
      cy.intercept('GET', '**/ai_workflows/approval_tokens/*', {
        statusCode: 200,
        body: { success: true, data: mockApprovalDetails },
      }).as('getApprovalDetails');
    });

    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/ai-workflows/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('AI Workflow Approval Required').should('be.visible');
      cy.contains('button', 'Approve').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/ai-workflows/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('AI Workflow Approval Required').should('be.visible');
    });
  });

  describe('Footer Display', () => {
    beforeEach(() => {
      cy.intercept('GET', '**/ai_workflows/approval_tokens/*', {
        statusCode: 200,
        body: { success: true, data: mockApprovalDetails },
      }).as('getApprovalDetails');
    });

    it('should display Powernode Platform branding in footer', () => {
      cy.visit('/ai-workflows/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('Powernode Platform - AI Workflow Approval').should('be.visible');
    });
  });
});

export {};
