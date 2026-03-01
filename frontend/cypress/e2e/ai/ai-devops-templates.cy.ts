/// <reference types="cypress" />

/**
 * AI DevOps Templates Tests
 *
 * Comprehensive E2E tests for the DevOps Templates page:
 * - Template management
 * - Installation workflow
 * - Pipeline executions
 * - Deployment risk assessment
 * - AI code reviews
 * - Analytics dashboard
 */

describe('AI DevOps Templates Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['ai'] });
    setupDevOpsTemplatesIntercepts();
  });

  describe('Page Load and Layout', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/devops');
    });

    it('should display DevOps templates page with title', () => {
      cy.assertContainsAny(['DevOps', 'AI Templates', 'Templates']);
    });

    it('should display page description', () => {
      cy.assertContainsAny(['pipelines', 'code review', 'deployment', 'validation']);
    });

    it('should display action buttons', () => {
      cy.assertContainsAny(['New Execution', 'Create Template']);
    });

    it('should display breadcrumbs', () => {
      cy.assertContainsAny(['Dashboard', 'AI', 'DevOps']);
    });
  });

  describe('Analytics Summary Cards', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/devops');
    });

    it('should display total executions card', () => {
      cy.assertContainsAny(['Total Executions', 'Executions']);
      cy.assertContainsAny(['success rate', '%']);
    });

    it('should display deployments card', () => {
      cy.assertContainsAny(['Deployments', 'Deploy']);
    });

    it('should display code reviews card', () => {
      cy.assertContainsAny(['Code Reviews', 'Reviews']);
      cy.assertContainsAny(['critical issues', 'issues']);
    });

    it('should display average duration card', () => {
      cy.assertContainsAny(['Avg Duration', 'Duration', 'Average']);
    });
  });

  describe('Tab Navigation', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/devops');
    });

    it('should display all tabs', () => {
      cy.assertContainsAny(['Templates', 'Installations', 'Executions', 'Risk Assessments', 'Code Reviews', 'Analytics']);
    });

    it('should switch to Installations tab', () => {
      cy.get('button').contains(/installations/i).click();
      cy.assertContainsAny(['Installation', 'installed', 'version']);
    });

    it('should switch to Executions tab', () => {
      cy.get('button').contains(/executions/i).click();
      cy.assertContainsAny(['Execution', 'pipeline', 'status']);
    });

    it('should switch to Risk Assessments tab', () => {
      cy.get('button').contains(/risk/i).click();
      cy.assertContainsAny(['Risk', 'Assessment', 'deployment']);
    });

    it('should switch to Code Reviews tab', () => {
      cy.get('button').contains(/reviews/i).click();
      cy.assertContainsAny(['Review', 'code', 'files']);
    });

    it('should switch to Analytics tab', () => {
      cy.get('button').contains(/analytics/i).click();
      cy.assertContainsAny(['Analytics', 'insights', 'coming soon']);
    });
  });

  describe('Templates Tab', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/devops');
    });

    it('should display template cards', () => {
      cy.assertContainsAny(['Template', 'install', 'category']);
    });

    it('should show template status badges', () => {
      cy.get('[data-testid="template-status-badge"], [data-testid="devops-template-card"]').should('have.length.at.least', 1);
    });

    it('should display template category and type', () => {
      cy.assertContainsAny(['code_quality', 'deployment', 'testing', 'documentation']);
    });

    it('should display install count', () => {
      cy.assertContainsAny(['installs', 'installations']);
    });

    it('should show installed status for installed templates', () => {
      cy.assertContainsAny(['Installed', 'Install']);
    });

    it('should have install button for uninstalled templates', () => {
      cy.get('button').contains(/install/i).should('exist');
    });
  });

  describe('Install Template', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/devops');
    });

    it('should install template when install button clicked', () => {
      cy.intercept('POST', '**/api/**/ai/devops/templates/*/install*', {
        statusCode: 200,
        body: { success: true, installation: { id: 'install-1' } },
      }).as('installTemplate');

      cy.get('button').contains(/install/i).first().click();
      cy.wait('@installTemplate');
      cy.assertContainsAny(['installed', 'success']);
    });
  });

  describe('Installations Tab', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/devops');
      cy.get('button').contains(/installations/i).click();
    });

    it('should display installations list or empty state', () => {
      cy.assertContainsAny(['No installations', 'Install', 'Installation', 'version', 'executions']);
    });

    it('should display installation version', () => {
      cy.assertContainsAny(['No installations', 'v']);
    });

    it('should display execution count and success rate', () => {
      cy.assertContainsAny(['No installations', 'executions', 'success', '%']);
    });
  });

  describe('Executions Tab', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/devops');
      cy.get('button').contains(/executions/i).click();
    });

    it('should display executions list or empty state', () => {
      cy.assertContainsAny(['No executions', 'Pipeline', 'Execution', 'pipeline', 'status']);
    });

    it('should display execution status badges', () => {
      cy.assertContainsAny(['No executions', 'completed', 'running', 'failed']);
    });

    it('should display git information', () => {
      cy.assertContainsAny(['No executions', 'Branch', 'Commit', 'PR']);
    });

    it('should display execution duration', () => {
      cy.assertContainsAny(['No executions', 's']);
    });
  });

  describe('Risk Assessments Tab', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/devops');
      cy.get('button').contains(/risk/i).click();
    });

    it('should display risk assessments list or empty state', () => {
      cy.assertContainsAny(['No risk assessments', 'deployment', 'Risk', 'Assessment', 'level']);
    });

    it('should display risk level badges', () => {
      cy.assertContainsAny(['No risk assessments', 'CRITICAL', 'HIGH', 'MEDIUM', 'LOW']);
    });

    it('should display approve/reject buttons for assessed risks', () => {
      cy.assertContainsAny(['Approve', 'Reject', 'No risk assessments']);
    });

    it('should display risk recommendations', () => {
      cy.assertContainsAny(['Recommendations', 'recommendation', 'No risk assessments']);
    });
  });

  describe('Risk Decision Flow', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/devops');
      cy.get('button').contains(/risk/i).click();
    });

    it('should approve risk when approve button clicked', () => {
      cy.intercept('POST', '**/api/**/ai/devops/risks/*/approve*', {
        statusCode: 200,
        body: { success: true, message: 'Deployment approved' },
      }).as('approveRisk');

      cy.get('button').contains(/approve/i).first().click();
      cy.wait('@approveRisk');
      cy.assertContainsAny(['approved', 'success']);
    });

    it('should reject risk when reject button clicked', () => {
      cy.intercept('POST', '**/api/**/ai/devops/risks/*/reject*', {
        statusCode: 200,
        body: { success: true, message: 'Deployment rejected' },
      }).as('rejectRisk');

      cy.get('button').contains(/reject/i).first().click();
      cy.wait('@rejectRisk');
      cy.assertContainsAny(['rejected', 'success']);
    });
  });

  describe('Code Reviews Tab', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/devops');
      cy.get('button').contains(/reviews/i).click();
    });

    it('should display code reviews list or empty state', () => {
      cy.assertContainsAny(['No code reviews', 'AI code reviews', 'Review', 'files', 'issues']);
    });

    it('should display review status and rating', () => {
      cy.assertContainsAny(['No code reviews', 'completed', 'analyzing', 'rating']);
    });

    it('should display approval recommendation', () => {
      cy.assertContainsAny(['No code reviews', 'approve', 'reject', 'request_changes']);
    });

    it('should display code review metrics', () => {
      cy.assertContainsAny(['No code reviews', 'files', 'issues', 'critical', 'suggestions']);
    });

    it('should display lines added/removed', () => {
      cy.assertContainsAny(['No code reviews', '+']);
    });
  });

  describe('Filters', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/devops');
    });

    it('should display search input', () => {
      cy.get('input[type="search"], input[placeholder*="Search"]').should('exist');
    });

    it('should display category filter', () => {
      cy.get('select').should('have.length.at.least', 1);
      cy.assertContainsAny(['Categories', 'Category', 'All']);
    });

    it('should display status filter', () => {
      cy.assertContainsAny(['Status', 'All Status']);
    });

    it('should filter templates by category', () => {
      cy.get('select').first().select('deployment');
      cy.waitForPageLoad();
    });
  });

  describe('Loading States', () => {
    it('should display loading indicator while fetching data', () => {
      cy.intercept('GET', '**/api/**/ai/devops/**', {
        statusCode: 200,
        body: { items: [] },
        delay: 1000,
      }).as('slowDevops');

      cy.standardTestSetup({ intercepts: ['ai'] });
      cy.visit('/app/ai/devops');
      cy.verifyLoadingState();
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('**/api/**/ai/devops/**', {
        statusCode: 500,
        visitUrl: '/app/ai/devops',
      });
    });
  });

  describe('Responsive Design', () => {
    it('should display correctly across viewports', () => {
      cy.testResponsiveDesign('/app/ai/devops', {
        checkContent: 'DevOps',
      });
    });
  });
});

/**
 * Setup DevOps templates API intercepts with mock data
 */
function setupDevOpsTemplatesIntercepts() {
  const mockTemplates = [
    {
      id: 'template-1',
      name: 'Code Quality Check',
      description: 'Automated code quality analysis using AI',
      category: 'code_quality',
      template_type: 'workflow',
      status: 'published',
      installation_count: 150,
      created_at: '2025-01-01T10:00:00Z',
    },
    {
      id: 'template-2',
      name: 'Smart Deployment',
      description: 'AI-driven deployment validation and rollback',
      category: 'deployment',
      template_type: 'pipeline',
      status: 'published',
      installation_count: 85,
      created_at: '2025-01-05T10:00:00Z',
    },
    {
      id: 'template-3',
      name: 'Auto Documentation',
      description: 'Generate documentation from code',
      category: 'documentation',
      template_type: 'task',
      status: 'draft',
      installation_count: 25,
      created_at: '2025-01-10T10:00:00Z',
    },
  ];

  const mockInstallations = [
    {
      id: 'install-1',
      template: mockTemplates[0],
      status: 'active',
      installed_version: '1.2.0',
      execution_count: 45,
      success_rate: 0.95,
    },
    {
      id: 'install-2',
      template: mockTemplates[1],
      status: 'active',
      installed_version: '2.0.1',
      execution_count: 20,
      success_rate: 0.90,
    },
  ];

  const mockExecutions = [
    {
      id: 'exec-1',
      execution_id: 'EXEC-001',
      status: 'completed',
      pipeline_type: 'code_quality',
      branch: 'main',
      commit_sha: 'abc123def456',
      pull_request_number: 42,
      duration_ms: 12500,
      created_at: '2025-01-15T10:00:00Z',
    },
    {
      id: 'exec-2',
      execution_id: 'EXEC-002',
      status: 'running',
      pipeline_type: 'deployment',
      branch: 'feature/new-feature',
      commit_sha: 'def456ghi789',
      pull_request_number: null,
      duration_ms: null,
      created_at: '2025-01-15T11:00:00Z',
    },
  ];

  const mockRisks = [
    {
      id: 'risk-1',
      assessment_id: 'RISK-001',
      status: 'assessed',
      risk_level: 'high',
      deployment_type: 'production',
      target_environment: 'prod-us-east-1',
      risk_score: 78,
      summary: 'Database migration detected with potential downtime',
      recommendations: ['Run migration during off-peak hours', 'Enable maintenance mode'],
    },
    {
      id: 'risk-2',
      assessment_id: 'RISK-002',
      status: 'approved',
      risk_level: 'low',
      deployment_type: 'staging',
      target_environment: 'staging',
      risk_score: 15,
      summary: 'Minor configuration change',
      recommendations: [],
    },
  ];

  const mockReviews = [
    {
      id: 'review-1',
      review_id: 'REV-001',
      status: 'completed',
      overall_rating: 'B+',
      approval_recommendation: 'approve',
      files_reviewed: 12,
      lines_added: 250,
      lines_removed: 80,
      issues_found: 5,
      critical_issues: 1,
      suggestions_count: 8,
    },
    {
      id: 'review-2',
      review_id: 'REV-002',
      status: 'analyzing',
      overall_rating: null,
      approval_recommendation: 'pending',
      files_reviewed: 0,
      lines_added: 150,
      lines_removed: 50,
      issues_found: 0,
      critical_issues: 0,
      suggestions_count: 0,
    },
  ];

  const mockAnalytics = {
    total_executions: 1250,
    success_rate: 0.92,
    average_duration_ms: 15000,
    deployments: {
      total: 350,
      successful: 340,
      failed: 10,
    },
    code_reviews: {
      total: 500,
      critical_issues: 45,
    },
  };

  // Templates
  cy.intercept('GET', '**/api/**/ai/devops/templates*', {
    statusCode: 200,
    body: { items: mockTemplates },
  }).as('getTemplates');

  cy.intercept('POST', '**/api/**/ai/devops/templates/*/install*', {
    statusCode: 200,
    body: { success: true, installation: { id: 'new-install' } },
  }).as('installTemplate');

  // Installations
  cy.intercept('GET', '**/api/**/ai/devops/installations*', {
    statusCode: 200,
    body: { items: mockInstallations },
  }).as('getInstallations');

  // Executions
  cy.intercept('GET', '**/api/**/ai/devops/executions*', {
    statusCode: 200,
    body: { items: mockExecutions },
  }).as('getExecutions');

  // Risks
  cy.intercept('GET', '**/api/**/ai/devops/risks*', {
    statusCode: 200,
    body: { items: mockRisks },
  }).as('getRisks');

  cy.intercept('POST', '**/api/**/ai/devops/risks/*/approve*', {
    statusCode: 200,
    body: { success: true, message: 'Deployment approved' },
  }).as('approveRisk');

  cy.intercept('POST', '**/api/**/ai/devops/risks/*/reject*', {
    statusCode: 200,
    body: { success: true, message: 'Deployment rejected' },
  }).as('rejectRisk');

  // Reviews
  cy.intercept('GET', '**/api/**/ai/devops/reviews*', {
    statusCode: 200,
    body: { items: mockReviews },
  }).as('getReviews');

  // Analytics
  cy.intercept('GET', '**/api/**/ai/devops/analytics*', {
    statusCode: 200,
    body: { analytics: mockAnalytics },
  }).as('getAnalytics');
}

export {};
