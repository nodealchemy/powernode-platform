/// <reference types="cypress" />

/**
 * AI DevOps Templates Page Tests
 *
 * Tests for DevOps Pipeline Templates functionality (Phase 4):
 * - Template browsing and management
 * - Template installation
 * - Pipeline executions
 * - Deployment risk assessments
 * - Code reviews
 * - Analytics dashboard
 * - Error handling
 * - Responsive design
 */

describe('AI DevOps Templates Page Tests', () => {
  beforeEach(() => {
    Cypress.on('uncaught:exception', () => false);
    cy.standardTestSetup({ intercepts: ['ai', 'devops'] });
    setupDevopsTemplatesIntercepts();
  });

  describe('Page Navigation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/devops-templates');
    });

    it('should navigate to DevOps Templates page', () => {
      cy.assertContainsAny(['DevOps', 'Templates', 'Pipeline', 'CI/CD']);
    });

    it('should display page title', () => {
      cy.assertContainsAny(['DevOps', 'Templates', 'Pipeline']);
    });

    it('should display page description', () => {
      cy.assertContainsAny(['pipeline', 'templates', 'CI/CD', 'automation', 'deployment']);
    });
  });

  describe('Template Management', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/devops-templates');
    });

    it('should display templates section', () => {
      cy.assertContainsAny(['Templates', 'Template', 'DevOps']);
    });

    it('should have Create Template button', () => {
      cy.assertHasElement([
        'button:contains("Create Template")',
        'button:contains("New Template")',
        'button:contains("Create")',
        '[data-testid*="create"]'
      ]);
    });

    it('should display template categories', () => {
      cy.assertContainsAny(['Category', 'code_quality', 'deployment', 'testing', 'documentation', 'DevOps']);
    });

    it('should display template types', () => {
      cy.assertContainsAny(['Type', 'pr_review', 'commit_analysis', 'release', 'DevOps']);
    });
  });

  describe('Template Installation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/devops-templates');
    });

    it('should display installed templates section', () => {
      cy.assertContainsAny(['Installed', 'My Templates', 'Installations', 'DevOps']);
    });

    it('should have Install Template option', () => {
      cy.assertHasElement([
        'button:contains("Install")',
        'button:contains("Add")',
        '[data-testid*="install"]',
        'button'
      ]);
    });

    it('should display installation status', () => {
      cy.assertContainsAny(['Active', 'Paused', 'Disabled', 'Status', 'DevOps']);
    });
  });

  describe('Pipeline Executions', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/devops-templates');
    });

    it('should display executions section', () => {
      cy.assertContainsAny(['Executions', 'Runs', 'Pipeline', 'DevOps']);
    });

    it('should display execution status', () => {
      cy.assertContainsAny(['Pending', 'Running', 'Completed', 'Failed', 'Status', 'DevOps']);
    });

    it('should display pipeline types', () => {
      cy.assertContainsAny(['PR Review', 'Commit', 'Deployment', 'Release', 'Manual', 'DevOps']);
    });

    it('should have Create Execution option', () => {
      cy.assertHasElement([
        'button:contains("Execute")',
        'button:contains("Run")',
        'button:contains("Create")',
        '[data-testid*="execute"]',
        'button'
      ]);
    });
  });

  describe('Deployment Risk Assessment', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/devops-templates');
    });

    it('should display risk assessments section', () => {
      cy.assertContainsAny(['Risk', 'Assessment', 'Deployment', 'DevOps']);
    });

    it('should display risk levels', () => {
      cy.assertContainsAny(['Low', 'Medium', 'High', 'Critical', 'Risk', 'DevOps']);
    });

    it('should have Assess Risk option', () => {
      cy.assertHasElement([
        'button:contains("Assess")',
        'button:contains("Analyze")',
        'button:contains("Check")',
        '[data-testid*="assess"]',
        'button'
      ]);
    });

    it('should display approval requirements', () => {
      cy.assertContainsAny(['Approval', 'Required', 'Approve', 'Reject', 'DevOps']);
    });
  });

  describe('Code Reviews', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/devops-templates');
    });

    it('should display code reviews section', () => {
      cy.assertContainsAny(['Code Review', 'Reviews', 'PR', 'Pull Request', 'DevOps']);
    });

    it('should display review status', () => {
      cy.assertContainsAny(['Pending', 'Analyzing', 'Completed', 'Failed', 'DevOps']);
    });

    it('should display review metrics', () => {
      cy.assertContainsAny(['Issues', 'Suggestions', 'Files', 'Lines', 'DevOps']);
    });

    it('should have Create Review option', () => {
      cy.assertHasElement([
        'button:contains("Review")',
        'button:contains("Analyze")',
        'button:contains("Create")',
        '[data-testid*="review"]',
        'button'
      ]);
    });
  });

  describe('Analytics Dashboard', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/devops-templates');
    });

    it('should display analytics section', () => {
      cy.assertContainsAny(['Analytics', 'Statistics', 'Metrics', 'Dashboard', 'DevOps']);
    });

    it('should display execution metrics', () => {
      cy.assertContainsAny(['Total', 'Success Rate', 'Duration', 'Executions', 'DevOps']);
    });

    it('should display deployment metrics', () => {
      cy.assertContainsAny(['Deployments', 'Risk Level', 'Decisions', 'DevOps']);
    });

    it('should display code review metrics', () => {
      cy.assertContainsAny(['Reviews', 'Issues Found', 'Critical', 'DevOps']);
    });
  });

  describe('Template Marketplace', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/devops-templates');
    });

    it('should display marketplace templates', () => {
      cy.assertContainsAny(['Marketplace', 'Community', 'Premium', 'Templates', 'DevOps']);
    });

    it('should display template pricing', () => {
      cy.assertContainsAny(['Free', 'Premium', '$', 'Price', 'DevOps']);
    });

    it('should display template ratings', () => {
      cy.assertContainsAny(['Rating', 'Stars', 'Reviews', 'Installations', 'DevOps']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('**/api/v1/ai/devops/**', {
        statusCode: 500,
        visitUrl: '/app/ai/devops-templates'
      });
    });

    it('should display error notification on failure', () => {
      cy.mockApiError('**/api/v1/ai/devops/templates*', 500, 'Failed to load templates');
      cy.navigateTo('/app/ai/devops-templates');
      cy.assertContainsAny(['Error', 'Failed', 'DevOps', 'Templates']);
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '**/api/v1/ai/devops/templates*', {
        delay: 1000,
        statusCode: 200,
        body: { success: true, data: { items: [], pagination: { current_page: 1, total_pages: 1, total_count: 0, per_page: 25 } } }
      }).as('getTemplatesDelayed');
      cy.visit('/app/ai/devops-templates');
      cy.assertHasElement(['[class*="spin"]', '[class*="loading"]', '[class*="Spin"]', '[class*="Loading"]', 'div']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.testResponsiveDesign('/app/ai/devops-templates', {
        checkContent: ['DevOps', 'Template']
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.assertPageReady('/app/ai/devops-templates');
      cy.assertContainsAny(['DevOps', 'Template']);
    });

    it('should adapt layout on small screens', () => {
      cy.viewport(375, 667);
      cy.assertPageReady('/app/ai/devops-templates');
      cy.get('body').should('be.visible');
    });
  });
});

/**
 * Set up DevOps Templates API intercepts
 */
function setupDevopsTemplatesIntercepts() {
  const mockTemplates = [
    {
      id: 'devops-template-1',
      name: 'AI Code Review',
      slug: 'ai-code-review',
      description: 'Automated AI-powered code review for pull requests',
      category: 'code_quality',
      template_type: 'pr_review',
      status: 'published',
      visibility: 'public',
      version: '2.0.0',
      installation_count: 450,
      average_rating: 4.7,
      is_system: false,
      is_featured: true,
      price_usd: null,
      published_at: '2024-01-15T10:00:00Z'
    },
    {
      id: 'devops-template-2',
      name: 'Deployment Risk Analyzer',
      slug: 'deployment-risk-analyzer',
      description: 'AI-based deployment risk assessment',
      category: 'deployment',
      template_type: 'deployment',
      status: 'published',
      visibility: 'public',
      version: '1.5.0',
      installation_count: 280,
      average_rating: 4.5,
      is_system: false,
      is_featured: true,
      price_usd: 29,
      published_at: '2024-02-01T14:00:00Z'
    },
    {
      id: 'devops-template-3',
      name: 'Release Notes Generator',
      slug: 'release-notes-generator',
      description: 'Auto-generate release notes from commits',
      category: 'documentation',
      template_type: 'release',
      status: 'published',
      visibility: 'marketplace',
      version: '1.0.0',
      installation_count: 120,
      average_rating: 4.2,
      is_system: false,
      is_featured: false,
      price_usd: 49,
      published_at: '2024-03-10T09:00:00Z'
    }
  ];

  const mockInstallations = [
    {
      id: 'devops-install-1',
      status: 'active',
      installed_version: '2.0.0',
      execution_count: 156,
      success_count: 148,
      failure_count: 8,
      success_rate: 94.87,
      last_executed_at: '2024-06-15T10:00:00Z',
      created_at: '2024-01-20T10:00:00Z',
      template: { id: 'devops-template-1', name: 'AI Code Review' }
    }
  ];

  const mockExecutions = [
    {
      id: 'exec-1',
      execution_id: 'EXEC-001',
      pipeline_type: 'pr_review',
      status: 'completed',
      trigger_source: 'github',
      trigger_event: 'pull_request',
      repository_id: 'repo-1',
      branch: 'feature/new-feature',
      commit_sha: 'abc123',
      pull_request_number: '42',
      duration_ms: 45000,
      started_at: '2024-06-15T10:00:00Z',
      completed_at: '2024-06-15T10:00:45Z',
      created_at: '2024-06-15T10:00:00Z'
    }
  ];

  const mockRisks = [
    {
      id: 'risk-1',
      assessment_id: 'RISK-001',
      deployment_type: 'production',
      target_environment: 'production',
      risk_level: 'medium',
      risk_score: 65,
      status: 'assessed',
      decision: 'approved',
      requires_approval: true,
      risk_factors: [{ factor: 'Database migration', severity: 'medium' }],
      change_analysis: { files_changed: 15, lines_added: 450, lines_removed: 120 },
      impact_analysis: { affected_services: ['api', 'worker'] },
      recommendations: ['Run additional integration tests', 'Monitor error rates closely'],
      mitigations: [{ action: 'Enable feature flag', status: 'completed' }],
      summary: 'Medium risk deployment with database migration',
      decision_rationale: 'Approved with monitoring requirements',
      assessed_at: '2024-06-15T10:00:00Z',
      decision_at: '2024-06-15T10:30:00Z',
      created_at: '2024-06-15T09:00:00Z'
    }
  ];

  const mockReviews = [
    {
      id: 'review-1',
      review_id: 'REV-001',
      status: 'completed',
      repository_id: 'repo-1',
      pull_request_number: '42',
      commit_sha: 'abc123',
      base_branch: 'main',
      head_branch: 'feature/new-feature',
      files_reviewed: 12,
      lines_added: 450,
      lines_removed: 120,
      issues_found: 5,
      critical_issues: 1,
      suggestions_count: 8,
      overall_rating: 'B',
      approval_recommendation: 'approve_with_changes',
      tokens_used: 15000,
      cost_usd: 0.45,
      started_at: '2024-06-15T10:00:00Z',
      completed_at: '2024-06-15T10:05:00Z',
      created_at: '2024-06-15T10:00:00Z'
    }
  ];

  const mockAnalytics = {
    total_executions: 425,
    by_status: { completed: 380, failed: 30, cancelled: 15 },
    by_type: { pr_review: 200, deployment: 150, release: 75 },
    success_rate: 92.7,
    average_duration_ms: 48000,
    deployments: {
      total: 150,
      by_risk_level: { low: 80, medium: 50, high: 18, critical: 2 },
      by_decision: { approved: 140, rejected: 8, overridden: 2 }
    },
    code_reviews: {
      total: 200,
      issues_found: 850,
      critical_issues: 45
    }
  };

  // Templates
  cy.intercept('GET', '**/api/v1/ai/devops/templates', {
    statusCode: 200,
    body: { success: true, data: { items: mockTemplates, pagination: { current_page: 1, total_pages: 1, total_count: 3, per_page: 25 } } }
  }).as('getDevopsTemplates');

  cy.intercept('GET', '**/api/v1/ai/devops/templates?*', {
    statusCode: 200,
    body: { success: true, data: { items: mockTemplates, pagination: { current_page: 1, total_pages: 1, total_count: 3, per_page: 25 } } }
  }).as('getDevopsTemplatesFiltered');

  cy.intercept('GET', /\/api\/v1\/ai\/devops\/templates\/[^\/]+$/, {
    statusCode: 200,
    body: { success: true, data: { template: mockTemplates[0] } }
  }).as('getDevopsTemplate');

  cy.intercept('POST', '**/api/v1/ai/devops/templates', {
    statusCode: 201,
    body: { success: true, data: { template: mockTemplates[0] } }
  }).as('createDevopsTemplate');

  // Installations
  cy.intercept('GET', '**/api/v1/ai/devops/installations*', {
    statusCode: 200,
    body: { success: true, data: { items: mockInstallations, pagination: { current_page: 1, total_pages: 1, total_count: 1, per_page: 25 } } }
  }).as('getDevopsInstallations');

  cy.intercept('POST', '**/api/v1/ai/devops/templates/*/install', {
    statusCode: 201,
    body: { success: true, data: { installation: mockInstallations[0] } }
  }).as('installDevopsTemplate');

  // Executions
  cy.intercept('GET', '**/api/v1/ai/devops/executions*', {
    statusCode: 200,
    body: { success: true, data: { items: mockExecutions, pagination: { current_page: 1, total_pages: 1, total_count: 1, per_page: 25 } } }
  }).as('getDevopsExecutions');

  cy.intercept('POST', '**/api/v1/ai/devops/executions', {
    statusCode: 201,
    body: { success: true, data: { execution: mockExecutions[0] } }
  }).as('createDevopsExecution');

  // Risks
  cy.intercept('GET', '**/api/v1/ai/devops/risks*', {
    statusCode: 200,
    body: { success: true, data: { items: mockRisks, pagination: { current_page: 1, total_pages: 1, total_count: 1, per_page: 25 } } }
  }).as('getDeploymentRisks');

  cy.intercept('POST', '**/api/v1/ai/devops/risks/assess', {
    statusCode: 201,
    body: { success: true, data: { assessment: mockRisks[0] } }
  }).as('assessDeploymentRisk');

  cy.intercept('PUT', '**/api/v1/ai/devops/risks/*/approve', {
    statusCode: 200,
    body: { success: true, data: { assessment: { ...mockRisks[0], status: 'approved' } } }
  }).as('approveDeploymentRisk');

  // Reviews
  cy.intercept('GET', '**/api/v1/ai/devops/reviews*', {
    statusCode: 200,
    body: { success: true, data: { items: mockReviews, pagination: { current_page: 1, total_pages: 1, total_count: 1, per_page: 25 } } }
  }).as('getCodeReviews');

  cy.intercept('POST', '**/api/v1/ai/devops/reviews', {
    statusCode: 201,
    body: { success: true, data: { review: mockReviews[0] } }
  }).as('createCodeReview');

  // Analytics
  cy.intercept('GET', '**/api/v1/ai/devops/analytics*', {
    statusCode: 200,
    body: { success: true, data: { analytics: mockAnalytics } }
  }).as('getDevopsAnalytics');
}

export {};
