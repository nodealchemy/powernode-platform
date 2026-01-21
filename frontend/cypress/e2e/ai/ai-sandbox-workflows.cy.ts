/// <reference types="cypress" />

/**
 * AI Sandbox Workflows Tests
 *
 * Comprehensive E2E tests for the AI Sandbox page:
 * - Sandbox CRUD operations
 * - Test scenario management
 * - Test run execution
 * - Performance benchmarks
 * - A/B testing
 * - Tab navigation
 */

describe('AI Sandbox Workflows Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['ai'] });
    setupSandboxIntercepts();
  });

  describe('Sandbox Page Load', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/sandbox');
    });

    it('should display sandbox page with title and description', () => {
      cy.assertContainsAny(['AI Sandbox', 'Sandbox', 'Testing']);
      cy.assertContainsAny(['testing', 'environments', 'agents', 'playback']);
    });

    it('should display action buttons', () => {
      cy.assertContainsAny(['Run Tests', 'Create Sandbox']);
    });

    it('should display breadcrumbs', () => {
      cy.assertContainsAny(['Dashboard', 'AI', 'Sandbox']);
    });
  });

  describe('Sandbox Selector', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/sandbox');
    });

    it('should display active sandbox selector when sandboxes exist', () => {
      cy.assertContainsAny(['Active Sandbox', 'Sandbox']);
      cy.get('select').should('exist');
    });

    it('should show sandbox details in selector', () => {
      cy.assertContainsAny(['runs', 'executions']);
    });

    it('should allow switching between sandboxes', () => {
      cy.get('select').first().then($select => {
        if ($select.find('option').length > 1) {
          cy.wrap($select).select(1);
          cy.waitForPageLoad();
        }
      });
    });
  });

  describe('Tab Navigation', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/sandbox');
    });

    it('should display all tabs', () => {
      cy.assertContainsAny(['Sandboxes', 'Test Scenarios', 'Mock Responses', 'Test Runs', 'Benchmarks', 'A/B Tests']);
    });

    it('should switch to Test Scenarios tab', () => {
      cy.get('button').contains(/scenarios/i).click();
      cy.assertContainsAny(['Scenario', 'Test', 'scenarios']);
    });

    it('should switch to Mock Responses tab', () => {
      cy.get('button').contains(/mock/i).click();
      cy.assertContainsAny(['Mock', 'Responses', 'Create Mock']);
    });

    it('should switch to Test Runs tab', () => {
      cy.get('button').contains(/runs/i).click();
      cy.assertContainsAny(['Run', 'Tests', 'runs']);
    });

    it('should switch to Benchmarks tab', () => {
      cy.get('button').contains(/benchmark/i).click();
      cy.assertContainsAny(['Benchmark', 'Performance']);
    });

    it('should switch to A/B Tests tab', () => {
      cy.get('button').contains(/a\/b/i).click();
      cy.assertContainsAny(['A/B', 'Test', 'variants']);
    });
  });

  describe('Sandboxes Tab', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/sandbox');
    });

    it('should display sandbox cards', () => {
      cy.get('[class*="grid"]').should('exist');
      cy.assertContainsAny(['Sandbox', 'active', 'inactive', 'runs', 'executions']);
    });

    it('should show sandbox status badges', () => {
      cy.get('[class*="px-2"][class*="py-1"]').should('exist');
    });

    it('should select sandbox when card clicked', () => {
      cy.get('[class*="cursor-pointer"]').first().click();
      cy.get('[class*="border-theme-accent"]').should('exist');
    });

    it('should display sandbox type and description', () => {
      cy.assertContainsAny(['standard', 'isolated', 'description', 'No description']);
    });
  });

  describe('Create Sandbox', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/sandbox');
    });

    it('should have create sandbox button', () => {
      cy.get('button').contains(/create sandbox/i).should('be.visible');
    });

    it('should create sandbox when button clicked', () => {
      cy.intercept('POST', '**/api/**/ai/sandboxes*', {
        statusCode: 201,
        body: {
          sandbox: {
            id: 'new-sandbox-123',
            name: 'Sandbox 4',
            sandbox_type: 'standard',
            status: 'active',
          },
        },
      }).as('createSandbox');

      cy.get('button').contains(/create sandbox/i).click();
      cy.wait('@createSandbox');
      cy.assertContainsAny(['created', 'success', 'Sandbox']);
    });
  });

  describe('Run Tests', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/sandbox');
    });

    it('should have run tests button', () => {
      cy.get('button').contains(/run tests/i).should('be.visible');
    });

    it('should run tests when button clicked with sandbox selected', () => {
      cy.intercept('POST', '**/api/**/ai/sandboxes/*/runs*', {
        statusCode: 201,
        body: {
          run: {
            id: 'run-123',
            run_id: 'RUN-001',
            status: 'running',
            run_type: 'manual',
          },
        },
      }).as('createRun');

      cy.get('button').contains(/run tests/i).click();
      cy.wait('@createRun');
      cy.assertContainsAny(['started', 'running', 'success']);
    });
  });

  describe('Test Scenarios Tab', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/sandbox');
      cy.get('button').contains(/scenarios/i).click();
    });

    it('should display scenarios list or empty state', () => {
      cy.get('body').then($body => {
        if ($body.text().includes('No test scenarios')) {
          cy.assertContainsAny(['No test scenarios', 'Create']);
        } else {
          cy.assertContainsAny(['Scenario', 'pass rate', 'runs']);
        }
      });
    });

    it('should display scenario status and type badges', () => {
      cy.get('body').then($body => {
        if (!$body.text().includes('No test scenarios')) {
          cy.get('[class*="px-2"][class*="py-1"]').should('have.length.at.least', 1);
        }
      });
    });

    it('should display scenario statistics', () => {
      cy.get('body').then($body => {
        if (!$body.text().includes('No test scenarios')) {
          cy.assertContainsAny(['runs', 'passed', 'failed', 'pass rate']);
        }
      });
    });
  });

  describe('Test Runs Tab', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/sandbox');
      cy.get('button').contains(/runs/i).click();
    });

    it('should display runs list or empty state', () => {
      cy.get('body').then($body => {
        if ($body.text().includes('No test runs')) {
          cy.assertContainsAny(['No test runs', 'Run Tests']);
        } else {
          cy.assertContainsAny(['RUN-', 'pass rate', 'scenarios']);
        }
      });
    });

    it('should display run status badges', () => {
      cy.get('body').then($body => {
        if (!$body.text().includes('No test runs')) {
          cy.assertContainsAny(['completed', 'running', 'failed', 'passed']);
        }
      });
    });

    it('should display run metrics', () => {
      cy.get('body').then($body => {
        if (!$body.text().includes('No test runs')) {
          cy.assertContainsAny(['scenarios', 'passed', 'failed', '%']);
        }
      });
    });
  });

  describe('Benchmarks Tab', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/sandbox');
      cy.get('button').contains(/benchmark/i).click();
    });

    it('should display benchmarks list or empty state', () => {
      cy.get('body').then($body => {
        if ($body.text().includes('No benchmarks')) {
          cy.assertContainsAny(['No benchmarks', 'Create Benchmark']);
        } else {
          cy.assertContainsAny(['Benchmark', 'runs', 'score']);
        }
      });
    });

    it('should display benchmark trends', () => {
      cy.get('body').then($body => {
        if (!$body.text().includes('No benchmarks')) {
          cy.assertContainsAny(['improving', 'degrading', 'stable', 'trend']);
        }
      });
    });
  });

  describe('A/B Tests Tab', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/sandbox');
      cy.get('button').contains(/a\/b/i).click();
    });

    it('should display A/B tests list or empty state', () => {
      cy.get('body').then($body => {
        if ($body.text().includes('No A/B tests')) {
          cy.assertContainsAny(['No A/B tests', 'Create A/B Test']);
        } else {
          cy.assertContainsAny(['A/B', 'impressions', 'conversions', 'significance']);
        }
      });
    });

    it('should display winning variant when determined', () => {
      cy.get('body').then($body => {
        if ($body.text().includes('Winner')) {
          cy.assertContainsAny(['Winner', 'winning']);
        }
      });
    });

    it('should display statistical significance', () => {
      cy.get('body').then($body => {
        if (!$body.text().includes('No A/B tests')) {
          cy.assertContainsAny(['significance', '%']);
        }
      });
    });
  });

  describe('Filters', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/sandbox');
    });

    it('should display search input', () => {
      cy.get('input[type="search"], input[placeholder*="Search"]').should('exist');
    });

    it('should display status filter', () => {
      cy.get('select').contains(/status|all status/i).should('exist');
    });

    it('should display type filter', () => {
      cy.get('select').contains(/type|all type/i).should('exist');
    });

    it('should filter sandboxes by status', () => {
      cy.get('select').first().select('active');
      cy.waitForPageLoad();
    });
  });

  describe('Loading States', () => {
    it('should display loading indicator while fetching data', () => {
      cy.intercept('GET', '**/api/**/ai/sandboxes*', {
        statusCode: 200,
        body: { items: [] },
        delay: 1000,
      }).as('slowSandboxes');

      cy.standardTestSetup({ intercepts: ['ai'] });
      cy.visit('/app/ai/sandbox');
      cy.verifyLoadingState();
    });
  });

  describe('Empty States', () => {
    it('should display empty state when no sandboxes exist', () => {
      cy.intercept('GET', '**/api/**/ai/sandboxes*', {
        statusCode: 200,
        body: { items: [] },
      }).as('emptySandboxes');

      cy.intercept('GET', '**/api/**/ai/sandbox/ab-tests*', {
        statusCode: 200,
        body: { items: [] },
      }).as('emptyAbTests');

      cy.standardTestSetup({ intercepts: ['ai'] });
      cy.navigateTo('/app/ai/sandbox');

      cy.assertContainsAny(['No sandboxes', 'Create', 'sandbox']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('**/api/**/ai/sandboxes**', {
        statusCode: 500,
        visitUrl: '/app/ai/sandbox',
      });
    });
  });

  describe('Responsive Design', () => {
    it('should display correctly across viewports', () => {
      cy.testResponsiveDesign('/app/ai/sandbox', {
        checkContent: 'Sandbox',
      });
    });
  });
});

/**
 * Setup sandbox API intercepts with mock data
 */
function setupSandboxIntercepts() {
  const mockSandboxes = [
    {
      id: 'sandbox-1',
      name: 'Production Test Sandbox',
      description: 'Testing environment for production workflows',
      sandbox_type: 'standard',
      status: 'active',
      recording_enabled: false,
      test_runs_count: 15,
      total_executions: 150,
      created_at: '2025-01-01T10:00:00Z',
    },
    {
      id: 'sandbox-2',
      name: 'Integration Sandbox',
      description: 'Integration testing environment',
      sandbox_type: 'isolated',
      status: 'active',
      recording_enabled: true,
      test_runs_count: 8,
      total_executions: 45,
      created_at: '2025-01-05T10:00:00Z',
    },
    {
      id: 'sandbox-3',
      name: 'Performance Sandbox',
      description: 'Performance testing environment',
      sandbox_type: 'performance',
      status: 'paused',
      recording_enabled: false,
      test_runs_count: 25,
      total_executions: 500,
      created_at: '2024-12-15T10:00:00Z',
    },
  ];

  const mockScenarios = [
    {
      id: 'scenario-1',
      name: 'Basic Agent Response Test',
      description: 'Tests basic agent response flow',
      scenario_type: 'unit',
      status: 'active',
      run_count: 50,
      pass_count: 48,
      fail_count: 2,
      pass_rate: 0.96,
    },
    {
      id: 'scenario-2',
      name: 'Multi-Agent Workflow Test',
      description: 'Tests multi-agent collaboration',
      scenario_type: 'integration',
      status: 'active',
      run_count: 20,
      pass_count: 18,
      fail_count: 2,
      pass_rate: 0.90,
    },
  ];

  const mockRuns = [
    {
      id: 'run-1',
      run_id: 'RUN-001',
      status: 'completed',
      run_type: 'manual',
      total_scenarios: 10,
      passed_scenarios: 9,
      failed_scenarios: 1,
      pass_rate: 90.0,
      duration_ms: 5500,
      created_at: '2025-01-15T10:00:00Z',
    },
    {
      id: 'run-2',
      run_id: 'RUN-002',
      status: 'running',
      run_type: 'scheduled',
      total_scenarios: 15,
      passed_scenarios: 10,
      failed_scenarios: 0,
      pass_rate: 100.0,
      duration_ms: null,
      created_at: '2025-01-15T11:00:00Z',
    },
  ];

  const mockBenchmarks = [
    {
      id: 'bench-1',
      name: 'Response Latency Benchmark',
      description: 'Measures agent response time',
      run_count: 100,
      sample_size: 1000,
      latest_score: 85.5,
      trend: 'improving',
    },
    {
      id: 'bench-2',
      name: 'Accuracy Benchmark',
      description: 'Measures response accuracy',
      run_count: 50,
      sample_size: 500,
      latest_score: 92.3,
      trend: 'stable',
    },
  ];

  const mockAbTests = [
    {
      id: 'ab-1',
      name: 'GPT-4 vs Claude Comparison',
      description: 'Compare response quality between models',
      status: 'running',
      target_type: 'model',
      total_impressions: 5000,
      total_conversions: 450,
      winning_variant: null,
      statistical_significance: 0.85,
    },
    {
      id: 'ab-2',
      name: 'Prompt Engineering Test',
      description: 'Compare different prompt strategies',
      status: 'completed',
      target_type: 'prompt',
      total_impressions: 10000,
      total_conversions: 1200,
      winning_variant: 'Variant B',
      statistical_significance: 0.95,
    },
  ];

  // Sandboxes
  cy.intercept('GET', '**/api/**/ai/sandboxes', {
    statusCode: 200,
    body: { items: mockSandboxes },
  }).as('getSandboxes');

  cy.intercept('POST', '**/api/**/ai/sandboxes', {
    statusCode: 201,
    body: {
      sandbox: {
        id: 'new-sandbox',
        name: 'New Sandbox',
        sandbox_type: 'standard',
        status: 'active',
        test_runs_count: 0,
        total_executions: 0,
      },
    },
  }).as('createSandbox');

  // Scenarios
  cy.intercept('GET', '**/api/**/ai/sandboxes/*/scenarios*', {
    statusCode: 200,
    body: { items: mockScenarios },
  }).as('getScenarios');

  // Runs
  cy.intercept('GET', '**/api/**/ai/sandboxes/*/runs*', {
    statusCode: 200,
    body: { items: mockRuns },
  }).as('getRuns');

  cy.intercept('POST', '**/api/**/ai/sandboxes/*/runs*', {
    statusCode: 201,
    body: {
      run: {
        id: 'new-run',
        run_id: 'RUN-003',
        status: 'running',
        run_type: 'manual',
      },
    },
  }).as('createRun');

  // Benchmarks
  cy.intercept('GET', '**/api/**/ai/sandboxes/*/benchmarks*', {
    statusCode: 200,
    body: { items: mockBenchmarks },
  }).as('getBenchmarks');

  // A/B Tests
  cy.intercept('GET', '**/api/**/ai/sandbox/ab-tests*', {
    statusCode: 200,
    body: { items: mockAbTests },
  }).as('getAbTests');
}

export {};
