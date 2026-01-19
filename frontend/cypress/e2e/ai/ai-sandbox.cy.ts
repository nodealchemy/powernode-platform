/// <reference types="cypress" />

/**
 * AI Sandbox Testing Page Tests
 *
 * Tests for Sandbox & Testing Infrastructure functionality (Phase 4):
 * - Sandbox environment management
 * - Test scenarios
 * - Mock responses
 * - Test runs and results
 * - Performance benchmarks
 * - A/B testing
 * - Error handling
 * - Responsive design
 */

describe('AI Sandbox Testing Page Tests', () => {
  beforeEach(() => {
    Cypress.on('uncaught:exception', () => false);
    cy.standardTestSetup({ intercepts: ['ai'] });
    setupSandboxIntercepts();
  });

  describe('Page Navigation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/sandbox');
    });

    it('should navigate to Sandbox Testing page', () => {
      cy.assertContainsAny(['Sandbox', 'Testing', 'Test Environment']);
    });

    it('should display page title', () => {
      cy.assertContainsAny(['Sandbox', 'Testing']);
    });

    it('should display page description', () => {
      cy.assertContainsAny(['testing', 'sandbox', 'environment', 'isolated']);
    });
  });

  describe('Sandbox Management', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/sandbox');
    });

    it('should display sandboxes section', () => {
      cy.assertContainsAny(['Sandboxes', 'Sandbox', 'Environments', 'Testing']);
    });

    it('should have Create Sandbox button', () => {
      cy.assertHasElement([
        'button:contains("Create Sandbox")',
        'button:contains("New Sandbox")',
        'button:contains("Create")',
        '[data-testid*="create"]'
      ]);
    });

    it('should display sandbox types', () => {
      cy.assertContainsAny(['Standard', 'Isolated', 'Production Mirror', 'Performance', 'Security', 'Sandbox']);
    });

    it('should display sandbox status', () => {
      cy.assertContainsAny(['Active', 'Inactive', 'Paused', 'Expired', 'Status', 'Sandbox']);
    });
  });

  describe('Sandbox Actions', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/sandbox');
    });

    it('should have activate/deactivate actions', () => {
      cy.assertHasElement([
        'button:contains("Activate")',
        'button:contains("Deactivate")',
        '[data-testid*="activate"]',
        'button'
      ]);
    });

    it('should have delete action', () => {
      cy.assertHasElement([
        'button:contains("Delete")',
        '[data-testid*="delete"]',
        'button[aria-label*="delete"]',
        'button'
      ]);
    });

    it('should display sandbox analytics link', () => {
      cy.assertContainsAny(['Analytics', 'Statistics', 'Metrics', 'Sandbox']);
    });
  });

  describe('Test Scenarios', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/sandbox');
    });

    it('should display scenarios section', () => {
      cy.assertContainsAny(['Scenarios', 'Test Cases', 'Tests', 'Sandbox']);
    });

    it('should display scenario types', () => {
      cy.assertContainsAny(['Unit', 'Integration', 'Regression', 'Performance', 'Security', 'Chaos', 'Sandbox']);
    });

    it('should have Create Scenario option', () => {
      cy.assertHasElement([
        'button:contains("Create Scenario")',
        'button:contains("Add Scenario")',
        'button:contains("New")',
        '[data-testid*="create"]',
        'button'
      ]);
    });

    it('should display scenario status', () => {
      cy.assertContainsAny(['Draft', 'Active', 'Disabled', 'Archived', 'Status', 'Sandbox']);
    });
  });

  describe('Mock Responses', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/sandbox');
    });

    it('should display mocks section', () => {
      cy.assertContainsAny(['Mocks', 'Mock', 'Responses', 'Sandbox']);
    });

    it('should display match types', () => {
      cy.assertContainsAny(['Exact', 'Contains', 'Regex', 'Semantic', 'Always', 'Sandbox']);
    });

    it('should have Create Mock option', () => {
      cy.assertHasElement([
        'button:contains("Create Mock")',
        'button:contains("Add Mock")',
        'button:contains("New")',
        '[data-testid*="mock"]',
        'button'
      ]);
    });
  });

  describe('Test Runs', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/sandbox');
    });

    it('should display test runs section', () => {
      cy.assertContainsAny(['Test Runs', 'Runs', 'Executions', 'Sandbox']);
    });

    it('should display run types', () => {
      cy.assertContainsAny(['Manual', 'Scheduled', 'CI Triggered', 'Regression', 'Smoke', 'Sandbox']);
    });

    it('should display run status', () => {
      cy.assertContainsAny(['Pending', 'Running', 'Completed', 'Failed', 'Cancelled', 'Sandbox']);
    });

    it('should have Create Run option', () => {
      cy.assertHasElement([
        'button:contains("Run Tests")',
        'button:contains("Execute")',
        'button:contains("Create Run")',
        '[data-testid*="run"]',
        'button'
      ]);
    });

    it('should display pass rate metrics', () => {
      cy.assertContainsAny(['Pass Rate', 'Passed', 'Failed', 'Skipped', 'Sandbox']);
    });
  });

  describe('Test Results', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/sandbox');
    });

    it('should display results section', () => {
      cy.assertContainsAny(['Results', 'Outcomes', 'Test Results', 'Sandbox']);
    });

    it('should display result status', () => {
      cy.assertContainsAny(['Passed', 'Failed', 'Skipped', 'Error', 'Timeout', 'Sandbox']);
    });

    it('should display assertion results', () => {
      cy.assertContainsAny(['Assertions', 'Expected', 'Actual', 'Output', 'Sandbox']);
    });
  });

  describe('Performance Benchmarks', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/sandbox');
    });

    it('should display benchmarks section', () => {
      cy.assertContainsAny(['Benchmarks', 'Performance', 'Profiling', 'Sandbox']);
    });

    it('should have Create Benchmark option', () => {
      cy.assertHasElement([
        'button:contains("Create Benchmark")',
        'button:contains("Add Benchmark")',
        'button:contains("New")',
        '[data-testid*="benchmark"]',
        'button'
      ]);
    });

    it('should display benchmark metrics', () => {
      cy.assertContainsAny(['Baseline', 'Threshold', 'Score', 'Trend', 'Sandbox']);
    });

    it('should display trend indicators', () => {
      cy.assertContainsAny(['Improving', 'Stable', 'Degrading', 'Trend', 'Sandbox']);
    });
  });

  describe('A/B Testing', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/sandbox');
    });

    it('should display A/B tests section', () => {
      cy.assertContainsAny(['A/B Test', 'Experiment', 'Variant', 'Sandbox']);
    });

    it('should have Create A/B Test option', () => {
      cy.assertHasElement([
        'button:contains("Create A/B Test")',
        'button:contains("New Experiment")',
        'button:contains("Create")',
        '[data-testid*="ab-test"]',
        'button'
      ]);
    });

    it('should display test status', () => {
      cy.assertContainsAny(['Draft', 'Running', 'Paused', 'Completed', 'Cancelled', 'Sandbox']);
    });

    it('should display statistical significance', () => {
      cy.assertContainsAny(['Significance', 'Confidence', 'Winning', 'Variant', 'Sandbox']);
    });
  });

  describe('Sandbox Analytics', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/sandbox');
    });

    it('should display analytics dashboard', () => {
      cy.assertContainsAny(['Analytics', 'Statistics', 'Dashboard', 'Sandbox']);
    });

    it('should display test run metrics', () => {
      cy.assertContainsAny(['Total Runs', 'Pass Rate', 'Average', 'Sandbox']);
    });

    it('should display usage metrics', () => {
      cy.assertContainsAny(['Executions', 'Usage', 'Last Used', 'Sandbox']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('**/api/v1/ai/sandboxes**', {
        statusCode: 500,
        visitUrl: '/app/ai/sandbox'
      });
    });

    it('should display error notification on failure', () => {
      cy.mockApiError('**/api/v1/ai/sandboxes*', 500, 'Failed to load sandboxes');
      cy.navigateTo('/app/ai/sandbox');
      cy.assertContainsAny(['Error', 'Failed', 'Sandbox', 'Testing']);
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '**/api/v1/ai/sandboxes*', {
        delay: 1000,
        statusCode: 200,
        body: { success: true, data: { items: [], pagination: { current_page: 1, total_pages: 1, total_count: 0, per_page: 25 } } }
      }).as('getSandboxesDelayed');
      cy.visit('/app/ai/sandbox');
      cy.assertHasElement(['[class*="spin"]', '[class*="loading"]', '[class*="Spin"]', '[class*="Loading"]', 'div']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.testResponsiveDesign('/app/ai/sandbox', {
        checkContent: ['Sandbox', 'Testing']
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.assertPageReady('/app/ai/sandbox');
      cy.assertContainsAny(['Sandbox', 'Testing']);
    });

    it('should adapt layout on small screens', () => {
      cy.viewport(375, 667);
      cy.assertPageReady('/app/ai/sandbox');
      cy.get('body').should('be.visible');
    });
  });
});

/**
 * Set up Sandbox Testing API intercepts
 */
function setupSandboxIntercepts() {
  const mockSandboxes = [
    {
      id: 'sandbox-1',
      name: 'Development Sandbox',
      description: 'Primary development testing environment',
      sandbox_type: 'standard',
      status: 'active',
      is_isolated: false,
      recording_enabled: true,
      test_runs_count: 45,
      total_executions: 1250,
      last_used_at: '2024-06-15T10:00:00Z',
      expires_at: null,
      created_at: '2024-01-01T00:00:00Z'
    },
    {
      id: 'sandbox-2',
      name: 'Isolated Security Sandbox',
      description: 'Isolated environment for security testing',
      sandbox_type: 'security',
      status: 'active',
      is_isolated: true,
      recording_enabled: true,
      test_runs_count: 12,
      total_executions: 340,
      last_used_at: '2024-06-14T14:00:00Z',
      expires_at: '2024-12-31T23:59:59Z',
      created_at: '2024-03-15T00:00:00Z'
    },
    {
      id: 'sandbox-3',
      name: 'Performance Testing',
      description: 'Performance benchmarking environment',
      sandbox_type: 'performance',
      status: 'paused',
      is_isolated: true,
      recording_enabled: false,
      test_runs_count: 8,
      total_executions: 450,
      last_used_at: '2024-06-10T09:00:00Z',
      expires_at: null,
      created_at: '2024-02-01T00:00:00Z'
    }
  ];

  const mockScenarios = [
    {
      id: 'scenario-1',
      name: 'Customer Support Flow Test',
      description: 'Tests the complete customer support agent workflow',
      scenario_type: 'integration',
      status: 'active',
      target_type: 'workflow',
      target_workflow_id: 'wf-1',
      target_agent_id: null,
      input_data: { query: 'Help with billing' },
      expected_output: { response_type: 'helpful' },
      assertions: [{ type: 'contains', field: 'response', value: 'billing' }],
      timeout_seconds: 60,
      run_count: 25,
      pass_count: 23,
      fail_count: 2,
      pass_rate: 92,
      last_run_at: '2024-06-15T10:00:00Z',
      created_at: '2024-01-15T00:00:00Z'
    }
  ];

  const mockMocks = [
    {
      id: 'mock-1',
      name: 'OpenAI GPT-4 Mock',
      provider_type: 'openai',
      model_name: 'gpt-4',
      endpoint: '/v1/chat/completions',
      match_type: 'contains',
      match_criteria: { content: 'billing' },
      response_data: { choices: [{ message: { content: 'I can help with billing.' } }] },
      latency_ms: 100,
      error_rate: 0,
      is_active: true,
      priority: 1,
      hit_count: 450,
      last_hit_at: '2024-06-15T10:00:00Z',
      created_at: '2024-01-01T00:00:00Z'
    }
  ];

  const mockRuns = [
    {
      id: 'run-1',
      run_id: 'RUN-001',
      run_type: 'manual',
      status: 'completed',
      total_scenarios: 5,
      passed_scenarios: 4,
      failed_scenarios: 1,
      skipped_scenarios: 0,
      pass_rate: 80,
      duration_ms: 15000,
      started_at: '2024-06-15T10:00:00Z',
      completed_at: '2024-06-15T10:00:15Z',
      created_at: '2024-06-15T10:00:00Z'
    }
  ];

  const mockBenchmarks = [
    {
      id: 'benchmark-1',
      benchmark_id: 'BENCH-001',
      name: 'Response Time Benchmark',
      description: 'Measures workflow response times',
      status: 'active',
      target_workflow_id: 'wf-1',
      target_agent_id: null,
      baseline_metrics: { avg_response_ms: 500, p95_response_ms: 800 },
      thresholds: { max_response_ms: 1000 },
      sample_size: 100,
      run_count: 15,
      latest_results: { avg_response_ms: 450, p95_response_ms: 720 },
      latest_score: 92,
      trend: 'improving',
      last_run_at: '2024-06-15T10:00:00Z',
      created_at: '2024-01-01T00:00:00Z'
    }
  ];

  const mockAbTests = [
    {
      id: 'ab-test-1',
      test_id: 'AB-001',
      name: 'Prompt Variation Test',
      description: 'Testing different prompt styles',
      status: 'running',
      target_type: 'prompt',
      target_id: 'prompt-1',
      variants: [
        { id: 'control', name: 'Control', config: {} },
        { id: 'variant-a', name: 'Variant A', config: { tone: 'friendly' } }
      ],
      traffic_allocation: { control: 50, 'variant-a': 50 },
      success_metrics: ['conversion_rate', 'satisfaction_score'],
      total_impressions: 1000,
      total_conversions: 150,
      winning_variant: null,
      statistical_significance: 85,
      started_at: '2024-06-01T00:00:00Z',
      ended_at: null,
      created_at: '2024-06-01T00:00:00Z'
    }
  ];

  const mockAnalytics = {
    test_runs: {
      total: 45,
      by_status: { completed: 40, failed: 3, cancelled: 2 },
      recent: mockRuns
    },
    scenarios: {
      total: 15,
      active: 12,
      by_type: { unit: 5, integration: 6, regression: 2, performance: 2 },
      average_pass_rate: 88.5
    },
    recordings: {
      total: 250,
      by_type: { workflow: 180, agent: 70 }
    },
    usage: {
      total_executions: 1250,
      last_used_at: '2024-06-15T10:00:00Z'
    }
  };

  // Sandboxes
  cy.intercept('GET', '**/api/v1/ai/sandboxes', {
    statusCode: 200,
    body: { success: true, data: { items: mockSandboxes, pagination: { current_page: 1, total_pages: 1, total_count: 3, per_page: 25 } } }
  }).as('getSandboxes');

  cy.intercept('GET', '**/api/v1/ai/sandboxes?*', {
    statusCode: 200,
    body: { success: true, data: { items: mockSandboxes, pagination: { current_page: 1, total_pages: 1, total_count: 3, per_page: 25 } } }
  }).as('getSandboxesFiltered');

  cy.intercept('GET', /\/api\/v1\/ai\/sandboxes\/[^\/]+$/, {
    statusCode: 200,
    body: { success: true, data: { sandbox: mockSandboxes[0] } }
  }).as('getSandbox');

  cy.intercept('POST', '**/api/v1/ai/sandboxes', {
    statusCode: 201,
    body: { success: true, data: { sandbox: mockSandboxes[0] } }
  }).as('createSandbox');

  cy.intercept('PUT', '**/api/v1/ai/sandboxes/*', {
    statusCode: 200,
    body: { success: true, data: { sandbox: mockSandboxes[0] } }
  }).as('updateSandbox');

  cy.intercept('DELETE', '**/api/v1/ai/sandboxes/*', {
    statusCode: 200,
    body: { success: true, data: { message: 'Sandbox deleted' } }
  }).as('deleteSandbox');

  cy.intercept('PUT', '**/api/v1/ai/sandboxes/*/activate', {
    statusCode: 200,
    body: { success: true, data: { sandbox: { ...mockSandboxes[0], status: 'active' } } }
  }).as('activateSandbox');

  cy.intercept('PUT', '**/api/v1/ai/sandboxes/*/deactivate', {
    statusCode: 200,
    body: { success: true, data: { sandbox: { ...mockSandboxes[0], status: 'inactive' } } }
  }).as('deactivateSandbox');

  // Analytics
  cy.intercept('GET', '**/api/v1/ai/sandboxes/*/analytics*', {
    statusCode: 200,
    body: { success: true, data: { analytics: mockAnalytics } }
  }).as('getSandboxAnalytics');

  // Scenarios
  cy.intercept('GET', '**/api/v1/ai/sandboxes/*/scenarios*', {
    statusCode: 200,
    body: { success: true, data: { items: mockScenarios, pagination: { current_page: 1, total_pages: 1, total_count: 1, per_page: 25 } } }
  }).as('getScenarios');

  cy.intercept('POST', '**/api/v1/ai/sandboxes/*/scenarios', {
    statusCode: 201,
    body: { success: true, data: { scenario: mockScenarios[0] } }
  }).as('createScenario');

  // Mocks
  cy.intercept('GET', '**/api/v1/ai/sandboxes/*/mocks*', {
    statusCode: 200,
    body: { success: true, data: { items: mockMocks, pagination: { current_page: 1, total_pages: 1, total_count: 1, per_page: 25 } } }
  }).as('getMocks');

  cy.intercept('POST', '**/api/v1/ai/sandboxes/*/mocks', {
    statusCode: 201,
    body: { success: true, data: { mock: mockMocks[0] } }
  }).as('createMock');

  // Test Runs
  cy.intercept('GET', '**/api/v1/ai/sandboxes/*/runs*', {
    statusCode: 200,
    body: { success: true, data: { items: mockRuns, pagination: { current_page: 1, total_pages: 1, total_count: 1, per_page: 25 } } }
  }).as('getTestRuns');

  cy.intercept('POST', '**/api/v1/ai/sandboxes/*/runs', {
    statusCode: 201,
    body: { success: true, data: { run: mockRuns[0] } }
  }).as('createTestRun');

  cy.intercept('POST', '**/api/v1/ai/sandboxes/*/runs/*/execute', {
    statusCode: 200,
    body: { success: true, data: { run: { ...mockRuns[0], status: 'running' } } }
  }).as('executeTestRun');

  // Benchmarks
  cy.intercept('GET', '**/api/v1/ai/sandboxes/*/benchmarks*', {
    statusCode: 200,
    body: { success: true, data: { items: mockBenchmarks, pagination: { current_page: 1, total_pages: 1, total_count: 1, per_page: 25 } } }
  }).as('getBenchmarks');

  cy.intercept('POST', '**/api/v1/ai/sandboxes/*/benchmarks', {
    statusCode: 201,
    body: { success: true, data: { benchmark: mockBenchmarks[0] } }
  }).as('createBenchmark');

  cy.intercept('POST', '**/api/v1/ai/sandboxes/*/benchmarks/*/run', {
    statusCode: 200,
    body: { success: true, data: { benchmark: mockBenchmarks[0], results: {}, violations: [], comparison: {} } }
  }).as('runBenchmark');

  // A/B Tests
  cy.intercept('GET', '**/api/v1/ai/ab_tests*', {
    statusCode: 200,
    body: { success: true, data: { items: mockAbTests, pagination: { current_page: 1, total_pages: 1, total_count: 1, per_page: 25 } } }
  }).as('getAbTests');

  cy.intercept('POST', '**/api/v1/ai/ab_tests', {
    statusCode: 201,
    body: { success: true, data: { ab_test: mockAbTests[0] } }
  }).as('createAbTest');

  cy.intercept('PUT', '**/api/v1/ai/ab_tests/*/start', {
    statusCode: 200,
    body: { success: true, data: { ab_test: { ...mockAbTests[0], status: 'running' } } }
  }).as('startAbTest');

  cy.intercept('GET', '**/api/v1/ai/ab_tests/*/results', {
    statusCode: 200,
    body: { success: true, data: { results: { test_id: 'AB-001', status: 'running', total_impressions: 1000, total_conversions: 150, variants: {}, has_sufficient_data: true, statistical_significance: 85, winning_variant: null } } }
  }).as('getAbTestResults');
}

export {};
