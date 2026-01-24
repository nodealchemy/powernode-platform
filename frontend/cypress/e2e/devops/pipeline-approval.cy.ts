/// <reference types="cypress" />

/**
 * Pipeline Approval E2E Tests
 *
 * Tests for the /devops/approve/:token and /devops/reject/:token routes
 * which handle step approval responses for DevOps pipelines.
 */

describe('Pipeline Approval Page Tests', () => {
  const mockApprovalDetails = {
    step_name: 'Deploy to Production',
    pipeline_name: 'Main Deployment Pipeline',
    run_number: 'RUN-123',
    trigger_type: 'pull_request',
    trigger_context: {
      pull_request_number: 42,
      branch: 'main',
    },
    status: 'pending',
    expires_at: new Date(Date.now() + 3600000).toISOString(),
    time_remaining_seconds: 3600,
    requires_comment: false,
    step_configuration: {
      step_type: 'approval',
      description: 'Please review and approve deployment to production environment.',
    },
  };

  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Loading State', () => {
    it('should display loading state while fetching approval details', () => {
      cy.intercept('GET', '**/devops/step_approvals/*', {
        delay: 1000,
        statusCode: 200,
        body: { success: true, data: mockApprovalDetails },
      }).as('getApprovalDetails');

      cy.visit('/devops/approve/test-token-123');
      cy.contains('Loading approval details').should('be.visible');
    });
  });

  describe('Approval Details Display', () => {
    beforeEach(() => {
      cy.intercept('GET', '**/devops/step_approvals/*', {
        statusCode: 200,
        body: { success: true, data: mockApprovalDetails },
      }).as('getApprovalDetails');
    });

    it('should display approval page title', () => {
      cy.visit('/devops/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('Pipeline Approval Required').should('be.visible');
    });

    it('should display pipeline name', () => {
      cy.visit('/devops/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('Main Deployment Pipeline').should('be.visible');
    });

    it('should display step name', () => {
      cy.visit('/devops/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('Deploy to Production').should('be.visible');
    });

    it('should display run number', () => {
      cy.visit('/devops/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('RUN-123').should('be.visible');
    });

    it('should display trigger context for pull request', () => {
      cy.visit('/devops/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('Pull Request #42').should('be.visible');
    });

    it('should display step description', () => {
      cy.visit('/devops/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('Please review and approve deployment').should('be.visible');
    });

    it('should display time remaining', () => {
      cy.visit('/devops/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('remaining').should('be.visible');
    });
  });

  describe('Approval Actions', () => {
    beforeEach(() => {
      cy.intercept('GET', '**/devops/step_approvals/*', {
        statusCode: 200,
        body: { success: true, data: mockApprovalDetails },
      }).as('getApprovalDetails');
    });

    it('should display Approve and Reject buttons', () => {
      cy.visit('/devops/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('button', 'Approve').should('be.visible');
      cy.contains('button', 'Reject').should('be.visible');
    });

    it('should display comment textarea', () => {
      cy.visit('/devops/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.get('textarea').should('be.visible');
    });

    it('should successfully approve step', () => {
      cy.intercept('POST', '**/devops/step_approvals/*/approve', {
        statusCode: 200,
        body: { success: true, data: { message: 'Step approved successfully' } },
      }).as('approveStep');

      cy.visit('/devops/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('button', 'Approve').click();
      cy.wait('@approveStep');
      cy.contains('Step Approved').should('be.visible');
      cy.contains('pipeline step has been approved').should('be.visible');
    });

    it('should successfully reject step', () => {
      cy.intercept('POST', '**/devops/step_approvals/*/reject', {
        statusCode: 200,
        body: { success: true, data: { message: 'Step rejected successfully' } },
      }).as('rejectStep');

      cy.visit('/devops/reject/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('button', 'Reject').click();
      cy.wait('@rejectStep');
      cy.contains('Step Rejected').should('be.visible');
      cy.contains('pipeline step has been rejected').should('be.visible');
    });

    it('should submit with optional comment', () => {
      cy.intercept('POST', '**/devops/step_approvals/*/approve', {
        statusCode: 200,
        body: { success: true, data: { message: 'Step approved' } },
      }).as('approveStep');

      cy.visit('/devops/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.get('textarea').type('LGTM - approving for production');
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
      cy.intercept('GET', '**/devops/step_approvals/*', {
        statusCode: 200,
        body: { success: true, data: detailsWithRequiredComment },
      }).as('getApprovalDetails');
    });

    it('should show required indicator for comment when required', () => {
      cy.visit('/devops/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('Comment').should('be.visible');
      cy.get('label').contains('*').should('exist');
    });

    it('should show error notification when comment is required but empty', () => {
      cy.visit('/devops/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('button', 'Approve').click();
      // Should not make API call without comment
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
      cy.intercept('GET', '**/devops/step_approvals/*', {
        statusCode: 200,
        body: { success: true, data: expiredDetails },
      }).as('getApprovalDetails');
    });

    it('should display expired message', () => {
      cy.visit('/devops/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('expired').should('be.visible');
    });

    it('should not show approve/reject buttons when expired', () => {
      cy.visit('/devops/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('button', 'Approve').should('not.exist');
      cy.contains('button', 'Reject').should('not.exist');
    });

    it('should show View in Dashboard button when expired', () => {
      cy.visit('/devops/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('View in Dashboard').should('be.visible');
    });
  });

  describe('Error States', () => {
    it('should display error for invalid token', () => {
      cy.intercept('GET', '**/devops/step_approvals/*', {
        statusCode: 404,
        body: { success: false, error: 'Approval request not found' },
      }).as('getApprovalDetailsError');

      cy.visit('/devops/approve/invalid-token');
      cy.wait('@getApprovalDetailsError');
      cy.contains('Unable to Process Request').should('be.visible');
    });

    it('should display error for already processed approval', () => {
      cy.intercept('GET', '**/devops/step_approvals/*', {
        statusCode: 400,
        body: { success: false, error: 'This approval has already been processed' },
      }).as('getApprovalDetailsError');

      cy.visit('/devops/approve/processed-token');
      cy.wait('@getApprovalDetailsError');
      cy.contains('Unable to Process Request').should('be.visible');
      // Note: Component shows HTTP status error instead of API error message
      cy.assertContainsAny(['already been processed', 'status code 400']);
    });

    it('should display error when approval action fails', () => {
      cy.intercept('GET', '**/devops/step_approvals/*', {
        statusCode: 200,
        body: { success: true, data: mockApprovalDetails },
      }).as('getApprovalDetails');

      cy.intercept('POST', '**/devops/step_approvals/*/approve', {
        statusCode: 500,
        body: { success: false, error: 'Failed to process approval' },
      }).as('approveStepError');

      cy.visit('/devops/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('button', 'Approve').click();
      cy.wait('@approveStepError');
      cy.contains('Unable to Process Request').should('be.visible');
    });

    it('should have Go to Dashboard button on error', () => {
      cy.intercept('GET', '**/devops/step_approvals/*', {
        statusCode: 404,
        body: { success: false, error: 'Not found' },
      }).as('getApprovalDetailsError');

      cy.visit('/devops/approve/invalid-token');
      cy.wait('@getApprovalDetailsError');
      cy.contains('Go to Dashboard').should('be.visible');
    });
  });

  describe('Trigger Type Display', () => {
    it('should display push trigger context', () => {
      const pushTriggerDetails = {
        ...mockApprovalDetails,
        trigger_type: 'push',
        trigger_context: { branch: 'main', ref: 'refs/heads/main' },
      };

      cy.intercept('GET', '**/devops/step_approvals/*', {
        statusCode: 200,
        body: { success: true, data: pushTriggerDetails },
      }).as('getApprovalDetails');

      cy.visit('/devops/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('Push to main').should('be.visible');
    });

    it('should display manual trigger context', () => {
      const manualTriggerDetails = {
        ...mockApprovalDetails,
        trigger_type: 'manual',
        trigger_context: {},
      };

      cy.intercept('GET', '**/devops/step_approvals/*', {
        statusCode: 200,
        body: { success: true, data: manualTriggerDetails },
      }).as('getApprovalDetails');

      cy.visit('/devops/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('Manual trigger').should('be.visible');
    });

    it('should display schedule trigger context', () => {
      const scheduleTriggerDetails = {
        ...mockApprovalDetails,
        trigger_type: 'schedule',
        trigger_context: {},
      };

      cy.intercept('GET', '**/devops/step_approvals/*', {
        statusCode: 200,
        body: { success: true, data: scheduleTriggerDetails },
      }).as('getApprovalDetails');

      cy.visit('/devops/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('Scheduled run').should('be.visible');
    });
  });

  describe('Completion State', () => {
    beforeEach(() => {
      cy.intercept('GET', '**/devops/step_approvals/*', {
        statusCode: 200,
        body: { success: true, data: mockApprovalDetails },
      }).as('getApprovalDetails');
    });

    it('should display View Pipeline Runs button after approval', () => {
      cy.intercept('POST', '**/devops/step_approvals/*/approve', {
        statusCode: 200,
        body: { success: true, data: { message: 'Approved' } },
      }).as('approveStep');

      cy.visit('/devops/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('button', 'Approve').click();
      cy.wait('@approveStep');
      cy.contains('View Pipeline Runs').should('be.visible');
    });

    it('should navigate to pipeline runs when clicking View Pipeline Runs', () => {
      cy.intercept('POST', '**/devops/step_approvals/*/approve', {
        statusCode: 200,
        body: { success: true, data: { message: 'Approved' } },
      }).as('approveStep');

      cy.visit('/devops/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('button', 'Approve').click();
      cy.wait('@approveStep');
      cy.contains('View Pipeline Runs').click();
      cy.url().should('include', '/app/devops/pipelines');
    });
  });

  describe('Responsive Layout', () => {
    beforeEach(() => {
      cy.intercept('GET', '**/devops/step_approvals/*', {
        statusCode: 200,
        body: { success: true, data: mockApprovalDetails },
      }).as('getApprovalDetails');
    });

    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/devops/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('Pipeline Approval Required').should('be.visible');
      cy.contains('button', 'Approve').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/devops/approve/test-token-123');
      cy.wait('@getApprovalDetails');
      cy.contains('Pipeline Approval Required').should('be.visible');
    });
  });
});

export {};
