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

// AI-related intercepts with mock data
Cypress.Commands.add('setupAiIntercepts', () => {
  // Mock workflow data
  const mockWorkflows = [
    {
      id: 'workflow-1',
      name: 'Test Workflow 1',
      description: 'A test workflow for automation',
      status: 'active',
      visibility: 'private',
      execution_mode: 'sequential',
      is_template: false,
      nodes_count: 5,
      runs_count: 12,
      version: 'v1.0.0',
      created_by: { id: 'user-1', name: 'Admin User' },
      created_at: '2024-01-15T10:00:00Z',
      updated_at: '2024-01-16T12:00:00Z'
    },
    {
      id: 'workflow-2',
      name: 'Data Processing Pipeline',
      description: 'Processes data in parallel',
      status: 'draft',
      visibility: 'account',
      execution_mode: 'parallel',
      is_template: false,
      nodes_count: 8,
      runs_count: 5,
      version: 'v1.1.0',
      created_by: { id: 'user-1', name: 'Admin User' },
      created_at: '2024-01-10T08:00:00Z',
      updated_at: '2024-01-14T16:00:00Z'
    },
    {
      id: 'workflow-3',
      name: 'Customer Onboarding Template',
      description: 'Template for customer onboarding',
      status: 'active',
      visibility: 'public',
      execution_mode: 'conditional',
      is_template: true,
      nodes_count: 10,
      runs_count: 25,
      version: 'v2.0.0',
      created_by: { id: 'user-2', name: 'Template Creator' },
      created_at: '2024-01-05T14:00:00Z',
      updated_at: '2024-01-12T10:00:00Z'
    }
  ];

  const mockWorkflowDetail = {
    ...mockWorkflows[0],
    nodes: [
      { id: 'node-1', type: 'trigger', name: 'Start Trigger', position: { x: 0, y: 0 } },
      { id: 'node-2', type: 'transform', name: 'Process Data', position: { x: 200, y: 0 } },
      { id: 'node-3', type: 'condition', name: 'Check Result', position: { x: 400, y: 0 } },
      { id: 'node-4', type: 'ai_agent', name: 'AI Analysis', position: { x: 600, y: 0 } },
      { id: 'node-5', type: 'notification', name: 'Send Notification', position: { x: 800, y: 0 } }
    ],
    edges: [
      { id: 'edge-1', source: 'node-1', target: 'node-2', type: 'default' },
      { id: 'edge-2', source: 'node-2', target: 'node-3', type: 'default' },
      { id: 'edge-3', source: 'node-3', target: 'node-4', type: 'success' },
      { id: 'edge-4', source: 'node-4', target: 'node-5', type: 'default' }
    ],
    executions: [
      { id: 'exec-1', status: 'completed', duration_ms: 1250, cost: 0.05, created_at: '2024-01-16T10:00:00Z' },
      { id: 'exec-2', status: 'completed', duration_ms: 980, cost: 0.03, created_at: '2024-01-16T09:00:00Z' },
      { id: 'exec-3', status: 'failed', duration_ms: 450, cost: 0.01, created_at: '2024-01-15T16:00:00Z' }
    ],
    validation: {
      is_valid: true,
      errors: [],
      warnings: ['Consider adding error handling'],
      last_validated_at: '2024-01-16T08:00:00Z'
    },
    settings: {
      timeout_seconds: 300,
      cost_limit: null,
      retry_config: { max_attempts: 3, backoff_multiplier: 2 }
    }
  };

  // Mock workflow templates
  const mockTemplates = [
    {
      id: 'template-1',
      name: 'Email Marketing Automation',
      description: 'Automate your email marketing campaigns',
      category: 'marketing',
      difficulty: 'beginner',
      execution_mode: 'sequential',
      estimated_duration: '5 min',
      nodes_count: 4,
      install_count: 150,
      rating: 4.5,
      is_verified: true,
      created_at: '2024-01-01T00:00:00Z'
    },
    {
      id: 'template-2',
      name: 'Data ETL Pipeline',
      description: 'Extract, transform, and load data',
      category: 'data',
      difficulty: 'intermediate',
      execution_mode: 'parallel',
      estimated_duration: '15 min',
      nodes_count: 8,
      install_count: 89,
      rating: 4.8,
      is_verified: true,
      created_at: '2024-01-05T00:00:00Z'
    },
    {
      id: 'template-3',
      name: 'Customer Support Bot',
      description: 'AI-powered customer support automation',
      category: 'support',
      difficulty: 'advanced',
      execution_mode: 'conditional',
      estimated_duration: '30 min',
      nodes_count: 12,
      install_count: 200,
      rating: 4.7,
      is_verified: false,
      created_at: '2024-01-10T00:00:00Z'
    }
  ];

  // Mock validation statistics
  const mockValidationStats = {
    total_workflows: 15,
    valid_workflows: 12,
    average_health: 85.5,
    issues_found: 8,
    workflows_by_status: {
      valid: 12,
      invalid: 2,
      pending: 1
    },
    recent_validations: [
      { workflow_id: 'workflow-1', status: 'valid', validated_at: '2024-01-16T10:00:00Z' },
      { workflow_id: 'workflow-2', status: 'invalid', validated_at: '2024-01-16T09:00:00Z' }
    ]
  };

  // Workflows list endpoint - /api/v1/ai/workflows
  // Use glob pattern with ** to match any host/port prefix
  cy.intercept('GET', '**/api/v1/ai/workflows', {
    statusCode: 200,
    body: {
      success: true,
      data: {
        items: mockWorkflows,
        pagination: { current_page: 1, total_pages: 1, total_count: 3, per_page: 25 }
      }
    }
  }).as('getWorkflows');

  // Also intercept with query params for filtered requests
  cy.intercept('GET', '**/api/v1/ai/workflows?*', {
    statusCode: 200,
    body: {
      success: true,
      data: {
        items: mockWorkflows,
        pagination: { current_page: 1, total_pages: 1, total_count: 3, per_page: 25 }
      }
    }
  }).as('getWorkflowsFiltered');

  // Single workflow detail - /api/v1/ai/workflows/:id
  // Match workflow detail but not nested resources or filtered list
  cy.intercept({ method: 'GET', url: '**/api/v1/ai/workflows/*' }, (req) => {
    // Skip if this is a filtered list request (has query params but no path segment after workflows)
    if (req.url.includes('?') && !req.url.match(/\/workflows\/[^/?]+/)) {
      return; // Let getWorkflowsFiltered handle this
    }
    // Skip nested resources (runs, executions, validate, export, duplicate, statistics, etc.)
    if (req.url.match(/\/workflows\/[^/]+\/(runs|executions|validate|export|duplicate|statistics)/)) {
      return;
    }
    // Skip validation-stats and validation-statistics endpoints
    if (req.url.includes('validation-stats') || req.url.includes('validation-statistics')) {
      return;
    }
    req.reply({
      statusCode: 200,
      body: { success: true, data: { workflow: mockWorkflowDetail } }
    });
  }).as('getWorkflow');

  // Create workflow
  cy.intercept('POST', '**/api/v1/ai/workflows', {
    statusCode: 201,
    body: { success: true, data: { workflow: mockWorkflows[0] } }
  }).as('createWorkflow');

  // Update workflow
  cy.intercept('PUT', '**/api/v1/ai/workflows/*', {
    statusCode: 200,
    body: { success: true, data: { workflow: mockWorkflows[0] } }
  }).as('updateWorkflow');

  // Delete workflow
  cy.intercept('DELETE', '**/api/v1/ai/workflows/*', {
    statusCode: 200,
    body: { success: true, data: null }
  }).as('deleteWorkflow');

  // Execute workflow
  cy.intercept('POST', '**/api/v1/ai/workflows/*/execute', {
    statusCode: 200,
    body: { success: true, data: { run: { id: 'run-new', status: 'running' } } }
  }).as('executeWorkflow');

  // Workflow executions/runs
  cy.intercept('GET', '**/api/v1/ai/workflows/*/runs*', {
    statusCode: 200,
    body: { success: true, data: { items: mockWorkflowDetail.executions, pagination: { current_page: 1, total_pages: 1, total_count: 3, per_page: 25 } } }
  }).as('getExecutions');

  // Workflow validate
  cy.intercept('GET', '**/api/v1/ai/workflows/*/validate', {
    statusCode: 200,
    body: { success: true, data: mockWorkflowDetail.validation }
  }).as('validateWorkflow');

  // Workflow export
  cy.intercept('GET', '**/api/v1/ai/workflows/*/export', {
    statusCode: 200,
    body: { success: true, data: { workflow: mockWorkflowDetail, format: 'json' } }
  }).as('exportWorkflow');

  // Workflow duplicate
  cy.intercept('POST', '**/api/v1/ai/workflows/*/duplicate', {
    statusCode: 200,
    body: { success: true, data: { workflow: { ...mockWorkflows[0], id: 'workflow-dup', name: 'Test Workflow 1 (Copy)' } } }
  }).as('duplicateWorkflow');

  // Workflow templates - /api/v1/ai/marketplace/templates
  cy.intercept('GET', '**/api/v1/ai/marketplace/templates', {
    statusCode: 200,
    body: {
      success: true,
      data: {
        items: mockTemplates,
        pagination: { current_page: 1, total_pages: 1, total_count: 3, per_page: 25 }
      }
    }
  }).as('getWorkflowTemplates');

  // Workflow templates with filters
  cy.intercept('GET', '**/api/v1/ai/marketplace/templates?*', {
    statusCode: 200,
    body: {
      success: true,
      data: {
        items: mockTemplates,
        pagination: { current_page: 1, total_pages: 1, total_count: 3, per_page: 25 }
      }
    }
  }).as('getWorkflowTemplatesFiltered');

  // Single template detail
  cy.intercept('GET', '**/api/v1/ai/marketplace/templates/*', {
    statusCode: 200,
    body: { success: true, data: mockTemplates[0] }
  }).as('getWorkflowTemplate');

  // Workflow validation statistics
  cy.intercept('GET', '**/api/v1/ai/workflows/validation-statistics', {
    statusCode: 200,
    body: { success: true, data: mockValidationStats }
  }).as('getValidationStats');

  // Also handle validation-stats path (alternative URL)
  cy.intercept('GET', '**/api/v1/ai/workflows/validation-stats', {
    statusCode: 200,
    body: { success: true, data: mockValidationStats }
  }).as('getValidationStatsAlt');

  // Also support the old path pattern for backwards compatibility
  cy.intercept('GET', '**/api/v1/ai/workflow-templates*', {
    statusCode: 200,
    body: {
      success: true,
      data: {
        items: mockTemplates,
        pagination: { current_page: 1, total_pages: 1, total_count: 3, per_page: 25 }
      }
    }
  }).as('getWorkflowTemplatesAlt');

  // Other AI endpoints
  cy.intercept('GET', '**/api/v1/ai/agents', {
    statusCode: 200,
    body: { success: true, data: { items: [], pagination: { current_page: 1, total_pages: 1, total_count: 0, per_page: 25 } } }
  }).as('getAgents');

  cy.intercept('GET', '**/api/v1/ai/agents?*', {
    statusCode: 200,
    body: { success: true, data: { items: [], pagination: { current_page: 1, total_pages: 1, total_count: 0, per_page: 25 } } }
  }).as('getAgentsFiltered');

  cy.intercept('GET', '**/api/v1/ai/conversations', {
    statusCode: 200,
    body: { success: true, data: { items: [], pagination: { current_page: 1, total_pages: 1, total_count: 0, per_page: 25 } } }
  }).as('getConversations');

  cy.intercept('GET', '**/api/v1/ai/conversations?*', {
    statusCode: 200,
    body: { success: true, data: { items: [], pagination: { current_page: 1, total_pages: 1, total_count: 0, per_page: 25 } } }
  }).as('getConversationsFiltered');

  cy.intercept('GET', '**/api/v1/ai/prompts', {
    statusCode: 200,
    body: { success: true, data: { items: [], pagination: { current_page: 1, total_pages: 1, total_count: 0, per_page: 25 } } }
  }).as('getPrompts');

  cy.intercept('GET', '**/api/v1/ai/prompts?*', {
    statusCode: 200,
    body: { success: true, data: { items: [], pagination: { current_page: 1, total_pages: 1, total_count: 0, per_page: 25 } } }
  }).as('getPromptsFiltered');

  cy.intercept('GET', '**/api/v1/ai/providers', {
    statusCode: 200,
    body: { success: true, data: { items: [], pagination: { current_page: 1, total_pages: 1, total_count: 0, per_page: 25 } } }
  }).as('getProviders');

  cy.intercept('GET', '**/api/v1/ai/providers?*', {
    statusCode: 200,
    body: { success: true, data: { items: [], pagination: { current_page: 1, total_pages: 1, total_count: 0, per_page: 25 } } }
  }).as('getProvidersFiltered');

  cy.intercept('GET', '**/api/v1/ai/contexts', {
    statusCode: 200,
    body: { success: true, data: { items: [], pagination: { current_page: 1, total_pages: 1, total_count: 0, per_page: 25 } } }
  }).as('getContexts');

  cy.intercept('GET', '**/api/v1/ai/contexts?*', {
    statusCode: 200,
    body: { success: true, data: { items: [], pagination: { current_page: 1, total_pages: 1, total_count: 0, per_page: 25 } } }
  }).as('getContextsFiltered');

  cy.intercept('GET', '**/api/v1/ai/agent-teams', {
    statusCode: 200,
    body: { success: true, data: { items: [], pagination: { current_page: 1, total_pages: 1, total_count: 0, per_page: 25 } } }
  }).as('getAgentTeams');

  cy.intercept('GET', '**/api/v1/ai/agent-teams?*', {
    statusCode: 200,
    body: { success: true, data: { items: [], pagination: { current_page: 1, total_pages: 1, total_count: 0, per_page: 25 } } }
  }).as('getAgentTeamsFiltered');

  // A2A Tasks endpoints
  const mockA2aTasks = [
    {
      id: 'a2a-task-1',
      task_id: 'task-001-abcd-1234',
      source_agent_id: 'agent-1',
      target_agent_id: 'agent-2',
      status: 'active',
      task_type: 'data_processing',
      priority: 'normal',
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    },
    {
      id: 'a2a-task-2',
      task_id: 'task-002-efgh-5678',
      source_agent_id: 'agent-2',
      target_agent_id: 'agent-3',
      status: 'completed',
      task_type: 'notification',
      priority: 'high',
      created_at: new Date(Date.now() - 3600000).toISOString(),
      updated_at: new Date(Date.now() - 1800000).toISOString()
    }
  ];

  cy.intercept('GET', '**/api/v1/ai/a2a/tasks', {
    statusCode: 200,
    body: { success: true, data: { items: mockA2aTasks, pagination: { current_page: 1, total_pages: 1, total_count: 2, per_page: 25 } } }
  }).as('getA2aTasks');

  cy.intercept('GET', '**/api/v1/ai/a2a/tasks?*', {
    statusCode: 200,
    body: { success: true, data: { items: mockA2aTasks, pagination: { current_page: 1, total_pages: 1, total_count: 2, per_page: 25 } } }
  }).as('getA2aTasksFiltered');

  cy.intercept('GET', '**/api/v1/ai/a2a/tasks/*', {
    statusCode: 200,
    body: { success: true, data: mockA2aTasks[0] }
  }).as('getA2aTask');

  // Agent Cards endpoints
  const mockAgentCards = [
    {
      id: 'card-1',
      name: 'Data Processor Agent',
      description: 'Handles data processing tasks',
      agent_id: 'agent-1',
      version: '1.0.0',
      capabilities: ['data_processing', 'transformation'],
      status: 'active',
      endpoint_url: 'https://agent.example.com/a2a',
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    },
    {
      id: 'card-2',
      name: 'Notification Agent',
      description: 'Sends notifications to users',
      agent_id: 'agent-2',
      version: '1.1.0',
      capabilities: ['notifications', 'email', 'sms'],
      status: 'active',
      endpoint_url: 'https://notify.example.com/a2a',
      created_at: new Date(Date.now() - 86400000).toISOString(),
      updated_at: new Date(Date.now() - 43200000).toISOString()
    }
  ];

  cy.intercept('GET', '**/api/v1/ai/agent-cards', {
    statusCode: 200,
    body: { success: true, data: { items: mockAgentCards, pagination: { current_page: 1, total_pages: 1, total_count: 2, per_page: 25 } } }
  }).as('getAgentCards');

  cy.intercept('GET', '**/api/v1/ai/agent-cards?*', {
    statusCode: 200,
    body: { success: true, data: { items: mockAgentCards, pagination: { current_page: 1, total_pages: 1, total_count: 2, per_page: 25 } } }
  }).as('getAgentCardsFiltered');

  cy.intercept('GET', '**/api/v1/ai/agent-cards/*', {
    statusCode: 200,
    body: { success: true, data: mockAgentCards[0] }
  }).as('getAgentCard');

  cy.intercept('POST', '**/api/v1/ai/agent-cards', {
    statusCode: 201,
    body: { success: true, data: mockAgentCards[0] }
  }).as('createAgentCard');

  cy.intercept('PUT', '**/api/v1/ai/agent-cards/*', {
    statusCode: 200,
    body: { success: true, data: mockAgentCards[0] }
  }).as('updateAgentCard');

  cy.intercept('DELETE', '**/api/v1/ai/agent-cards/*', {
    statusCode: 200,
    body: { success: true, data: null }
  }).as('deleteAgentCard');

  // Catch-all for other AI endpoints
  cy.intercept('GET', '**/api/v1/ai/**', {
    statusCode: 200,
    body: { success: true, data: {} }
  }).as('getAiGeneric');

  cy.intercept('POST', '**/api/v1/ai/**', {
    statusCode: 200,
    body: { success: true, data: {} }
  }).as('postAiGeneric');

  cy.intercept('PUT', '**/api/v1/ai/**', {
    statusCode: 200,
    body: { success: true, data: {} }
  }).as('putAiGeneric');

  cy.intercept('DELETE', '**/api/v1/ai/**', {
    statusCode: 200,
    body: { success: true, data: null }
  }).as('deleteAiGeneric');
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

  // Maintenance API intercepts
  const mockMaintenanceStatus = {
    mode: false,
    message: 'System is operational',
    scheduled_start: null,
    scheduled_end: null
  };

  const mockSystemHealth = {
    overall_status: 'healthy',
    database: { status: 'healthy', size: 1073741824, connection_time: 5 },
    redis: { status: 'healthy', memory_usage: 52428800, connected_clients: 15 },
    storage: { status: 'healthy', used_space: 10737418240, available_space: 107374182400 },
    services: [
      { name: 'API Server', status: 'healthy', uptime: 864000, memory_usage: 524288000 },
      { name: 'Background Worker', status: 'healthy', uptime: 432000, memory_usage: 262144000 },
      { name: 'Queue Processor', status: 'healthy', uptime: 604800, memory_usage: 134217728 }
    ]
  };

  const mockSystemMetrics = {
    cpu_usage: 35.5,
    memory_usage: 62.3,
    disk_usage: 45.8,
    database_connections: 25,
    queue_size: 12,
    active_users: 42,
    response_time_avg: 85
  };

  const mockBackups = [
    { id: 'backup-1', filename: 'backup_2024-01-15.sql.gz', size: 104857600, type: 'full', status: 'completed', created_at: '2024-01-15T10:00:00Z' },
    { id: 'backup-2', filename: 'backup_2024-01-14.sql.gz', size: 98566144, type: 'full', status: 'completed', created_at: '2024-01-14T10:00:00Z' },
    { id: 'backup-3', filename: 'backup_2024-01-13.sql.gz', size: 96468992, type: 'incremental', status: 'completed', created_at: '2024-01-13T10:00:00Z' }
  ];

  const mockCleanupStats = {
    old_logs: 150,
    expired_sessions: 45,
    temporary_files: 23,
    audit_logs_older_than_90_days: 1200,
    orphaned_uploads: 8,
    cache_entries: 256
  };

  const mockSchedules = [
    { id: 'schedule-1', description: 'Daily Backup', frequency: 'daily', next_run: '2024-01-16T02:00:00Z', enabled: true, task_type: 'backup' },
    { id: 'schedule-2', description: 'Weekly Cleanup', frequency: 'weekly', next_run: '2024-01-21T03:00:00Z', enabled: true, task_type: 'cleanup' }
  ];

  cy.intercept('GET', '/api/v1/admin/maintenance/status*', {
    statusCode: 200,
    body: { success: true, data: mockMaintenanceStatus }
  }).as('getMaintenanceStatus');

  cy.intercept('GET', '/api/v1/admin/maintenance/health*', {
    statusCode: 200,
    body: { success: true, data: mockSystemHealth }
  }).as('getSystemHealth');

  cy.intercept('GET', '/api/v1/admin/maintenance/metrics*', {
    statusCode: 200,
    body: { success: true, data: mockSystemMetrics }
  }).as('getSystemMetrics');

  cy.intercept('GET', '/api/v1/admin/maintenance/backups*', {
    statusCode: 200,
    body: { success: true, data: mockBackups }
  }).as('getBackups');

  cy.intercept('GET', '/api/v1/admin/maintenance/cleanup/stats*', {
    statusCode: 200,
    body: { success: true, data: mockCleanupStats }
  }).as('getCleanupStats');

  cy.intercept('GET', '/api/v1/admin/maintenance/schedules*', {
    statusCode: 200,
    body: { success: true, data: mockSchedules }
  }).as('getSchedules');

  // Catch-all for other maintenance endpoints
  cy.intercept('GET', '/api/v1/admin/maintenance*', {
    statusCode: 200,
    body: { success: true, data: {} }
  }).as('getMaintenanceGeneric');

  cy.intercept('POST', '/api/v1/admin/maintenance*', {
    statusCode: 200,
    body: { success: true, data: {} }
  }).as('postMaintenance');

  cy.intercept('PUT', '/api/v1/admin/maintenance*', {
    statusCode: 200,
    body: { success: true, data: {} }
  }).as('putMaintenance');
});

// DevOps-related intercepts
Cypress.Commands.add('setupDevopsIntercepts', () => {
  // Webhooks with mock data
  const mockWebhooks = [
    {
      id: 'webhook-1',
      name: 'Production Webhook',
      url: 'https://api.example.com/webhooks',
      events: ['subscription.created', 'payment.success'],
      status: 'active',
      created_at: new Date().toISOString(),
      last_triggered_at: new Date(Date.now() - 3600000).toISOString(),
      success_count: 145,
      failure_count: 3
    },
    {
      id: 'webhook-2',
      name: 'Staging Webhook',
      url: 'https://staging.example.com/webhooks',
      events: ['user.created', 'user.updated'],
      status: 'inactive',
      created_at: new Date(Date.now() - 86400000).toISOString(),
      last_triggered_at: null,
      success_count: 0,
      failure_count: 0
    }
  ];

  const mockWebhookStats = {
    total_endpoints: 2,
    active_endpoints: 1,
    inactive_endpoints: 1,
    total_deliveries_today: 48,
    successful_deliveries_today: 45,
    failed_deliveries_today: 3
  };

  cy.intercept('GET', '/api/v1/webhooks', {
    statusCode: 200,
    body: {
      success: true,
      data: {
        webhooks: mockWebhooks,
        pagination: { current_page: 1, per_page: 20, total_pages: 1, total_count: 2 },
        stats: mockWebhookStats
      }
    }
  }).as('getWebhooks');

  cy.intercept('GET', /\/api\/v1\/webhooks\/[^\/]+$/, {
    statusCode: 200,
    body: { success: true, data: mockWebhooks[0] }
  }).as('getWebhook');

  cy.intercept('GET', '/api/v1/webhooks/stats*', {
    statusCode: 200,
    body: { success: true, data: mockWebhookStats }
  }).as('getWebhookStats');

  cy.intercept('POST', '/api/v1/webhooks*').as('createWebhook');
  cy.intercept('PUT', '/api/v1/webhooks/*').as('updateWebhook');
  cy.intercept('DELETE', '/api/v1/webhooks/*').as('deleteWebhook');

  // API Keys with mock data
  const mockApiKeys = [
    {
      id: 'key-1',
      name: 'Production API Key',
      masked_key: 'pk_live_****1234',
      status: 'active',
      scopes: ['read', 'write'],
      created_at: new Date().toISOString(),
      last_used_at: new Date(Date.now() - 3600000).toISOString(),
      usage_count: 1250,
      description: 'Main production API key'
    },
    {
      id: 'key-2',
      name: 'Development API Key',
      masked_key: 'pk_test_****5678',
      status: 'active',
      scopes: ['read'],
      created_at: new Date(Date.now() - 86400000).toISOString(),
      last_used_at: new Date(Date.now() - 7200000).toISOString(),
      usage_count: 450,
      description: 'Development testing key'
    }
  ];

  cy.intercept('GET', '/api/v1/api_keys*', {
    statusCode: 200,
    body: {
      success: true,
      data: {
        api_keys: mockApiKeys,
        stats: { requests_today: 125, total_keys: 2 }
      }
    }
  }).as('getApiKeys');

  cy.intercept('POST', '/api/v1/api_keys*').as('createApiKey');
  cy.intercept('PUT', '/api/v1/api_keys/*').as('updateApiKey');
  cy.intercept('DELETE', '/api/v1/api_keys/*').as('deleteApiKey');
  cy.intercept('POST', '/api/v1/api_keys/*/regenerate*').as('regenerateApiKey');

  // Git Providers with mock data
  const mockGitProviders = [
    {
      id: 'provider-1',
      name: 'GitHub',
      type: 'github',
      configured: true,
      credential_count: 2,
      api_url: 'https://api.github.com'
    },
    {
      id: 'provider-2',
      name: 'GitLab',
      type: 'gitlab',
      configured: true,
      credential_count: 1,
      api_url: 'https://gitlab.com/api/v4'
    },
    {
      id: 'provider-3',
      name: 'Bitbucket',
      type: 'bitbucket',
      configured: false,
      credential_count: 0,
      api_url: 'https://api.bitbucket.org/2.0'
    }
  ];

  // Git providers API uses /git/providers endpoint (not /git_providers)
  cy.intercept('GET', '/api/v1/git/providers*', {
    statusCode: 200,
    body: { success: true, data: { providers: mockGitProviders } }
  }).as('getGitProviders');

  cy.intercept('GET', /\/api\/v1\/git\/providers\/[^\/]+$/, {
    statusCode: 200,
    body: { success: true, data: { provider: mockGitProviders[0] } }
  }).as('getGitProvider');

  cy.intercept('POST', '/api/v1/git/providers*').as('createGitProvider');
  cy.intercept('PUT', '/api/v1/git/providers/*').as('updateGitProvider');
  cy.intercept('DELETE', '/api/v1/git/providers/*').as('deleteGitProvider');

  // Git credentials
  cy.intercept('GET', '/api/v1/git/providers/*/credentials*', {
    statusCode: 200,
    body: { success: true, data: { credentials: [] } }
  }).as('getGitCredentials');

  // Pipelines with mock data (DevOps CI/CD Pipelines)
  const mockPipelines = [
    {
      id: 'pipeline-1',
      name: 'Production Deploy',
      slug: 'production-deploy',
      description: 'Deploy to production servers',
      pipeline_type: 'deployment',
      is_active: true,
      triggers: { manual: true, push: { branches: ['main'] } },
      timeout_minutes: 30,
      step_count: 5,
      run_count: 145,
      success_rate: 98.5,
      last_run: {
        id: 'run-1',
        run_number: 145,
        status: 'success',
        started_at: new Date(Date.now() - 3600000).toISOString(),
        completed_at: new Date(Date.now() - 3500000).toISOString()
      },
      created_at: new Date(Date.now() - 86400000 * 30).toISOString(),
      updated_at: new Date(Date.now() - 3600000).toISOString()
    },
    {
      id: 'pipeline-2',
      name: 'Staging Deploy',
      slug: 'staging-deploy',
      description: 'Deploy to staging environment',
      pipeline_type: 'deployment',
      is_active: true,
      triggers: { manual: true, push: { branches: ['develop'] } },
      timeout_minutes: 20,
      step_count: 4,
      run_count: 280,
      success_rate: 95.0,
      last_run: {
        id: 'run-2',
        run_number: 280,
        status: 'success',
        started_at: new Date(Date.now() - 7200000).toISOString(),
        completed_at: new Date(Date.now() - 7000000).toISOString()
      },
      created_at: new Date(Date.now() - 86400000 * 60).toISOString(),
      updated_at: new Date(Date.now() - 7200000).toISOString()
    },
    {
      id: 'pipeline-3',
      name: 'Test Pipeline',
      slug: 'test-pipeline',
      description: 'Run automated tests',
      pipeline_type: 'testing',
      is_active: false,
      triggers: { manual: true },
      timeout_minutes: 15,
      step_count: 3,
      run_count: 0,
      success_rate: null,
      last_run: null,
      created_at: new Date(Date.now() - 86400000 * 7).toISOString(),
      updated_at: new Date(Date.now() - 86400000 * 7).toISOString()
    }
  ];

  const mockPipelineRuns = [
    {
      id: 'run-1',
      run_number: 145,
      status: 'success',
      trigger_type: 'manual',
      started_at: new Date(Date.now() - 3600000).toISOString(),
      completed_at: new Date(Date.now() - 3500000).toISOString(),
      duration_seconds: 100,
      pipeline_name: 'Production Deploy',
      pipeline_slug: 'production-deploy'
    },
    {
      id: 'run-2',
      run_number: 144,
      status: 'success',
      trigger_type: 'webhook',
      started_at: new Date(Date.now() - 86400000).toISOString(),
      completed_at: new Date(Date.now() - 86300000).toISOString(),
      duration_seconds: 100,
      pipeline_name: 'Production Deploy',
      pipeline_slug: 'production-deploy'
    }
  ];

  // DevOps Pipelines - /api/v1/devops/pipelines
  cy.intercept('GET', '/api/v1/devops/pipelines', {
    statusCode: 200,
    body: {
      success: true,
      data: {
        pipelines: mockPipelines,
        meta: { total: 3, active_count: 2, total_runs: 425 }
      }
    }
  }).as('getPipelines');

  cy.intercept('GET', '/api/v1/devops/pipelines?*', {
    statusCode: 200,
    body: {
      success: true,
      data: {
        pipelines: mockPipelines,
        meta: { total: 3, active_count: 2, total_runs: 425 }
      }
    }
  }).as('getPipelinesFiltered');

  cy.intercept('GET', /\/api\/v1\/devops\/pipelines\/[^\/]+$/, {
    statusCode: 200,
    body: { success: true, data: { pipeline: mockPipelines[0] } }
  }).as('getPipeline');

  cy.intercept('POST', '/api/v1/devops/pipelines', {
    statusCode: 201,
    body: { success: true, data: { pipeline: mockPipelines[0] } }
  }).as('createPipeline');

  cy.intercept('PUT', '/api/v1/devops/pipelines/*', {
    statusCode: 200,
    body: { success: true, data: { pipeline: mockPipelines[0] } }
  }).as('updatePipeline');

  cy.intercept('PATCH', '/api/v1/devops/pipelines/*', {
    statusCode: 200,
    body: { success: true, data: { pipeline: mockPipelines[0] } }
  }).as('patchPipeline');

  cy.intercept('DELETE', '/api/v1/devops/pipelines/*', {
    statusCode: 200,
    body: { success: true, data: null }
  }).as('deletePipeline');

  cy.intercept('POST', '/api/v1/devops/pipelines/*/trigger', {
    statusCode: 200,
    body: { success: true, data: { pipeline_run: { id: 'run-new', status: 'running', run_number: 146 } } }
  }).as('triggerPipeline');

  cy.intercept('POST', '/api/v1/devops/pipelines/*/duplicate', {
    statusCode: 200,
    body: { success: true, data: { pipeline: { ...mockPipelines[0], id: 'pipeline-dup', name: 'Production Deploy (Copy)' } } }
  }).as('duplicatePipeline');

  cy.intercept('GET', '/api/v1/devops/pipelines/*/export_yaml', {
    statusCode: 200,
    body: { success: true, data: { pipeline_id: 'pipeline-1', pipeline_name: 'Production Deploy', yaml: '# Pipeline YAML\nname: Production Deploy', generated_at: new Date().toISOString() } }
  }).as('exportPipelineYaml');

  // Pipeline runs - /api/v1/devops/pipeline_runs
  cy.intercept('GET', '/api/v1/devops/pipeline_runs*', {
    statusCode: 200,
    body: {
      success: true,
      data: {
        pipeline_runs: mockPipelineRuns,
        meta: { total: 2, page: 1, per_page: 25, total_pages: 1, status_counts: { success: 2 } }
      }
    }
  }).as('getPipelineRuns');

  cy.intercept('GET', /\/api\/v1\/devops\/pipeline_runs\/[^\/]+$/, {
    statusCode: 200,
    body: { success: true, data: { pipeline_run: mockPipelineRuns[0] } }
  }).as('getPipelineRun');

  cy.intercept('POST', '/api/v1/devops/pipeline_runs/*/cancel', {
    statusCode: 200,
    body: { success: true, data: { pipeline_run: { ...mockPipelineRuns[0], status: 'cancelled' } } }
  }).as('cancelPipelineRun');

  cy.intercept('POST', '/api/v1/devops/pipeline_runs/*/retry', {
    statusCode: 200,
    body: { success: true, data: { pipeline_run: { id: 'run-retry', status: 'running' } } }
  }).as('retryPipelineRun');

  cy.intercept('GET', '/api/v1/devops/pipeline_runs/*/logs', {
    statusCode: 200,
    body: { success: true, data: { pipeline_run_id: 'run-1', status: 'success', logs: [] } }
  }).as('getPipelineRunLogs');

  // Runners with mock data
  const mockRunners = [
    {
      id: 'runner-1',
      name: 'linux-runner-01',
      external_id: 'runner-ext-1',
      status: 'online',
      busy: false,
      labels: ['linux', 'x64', 'self-hosted'],
      os: 'linux',
      architecture: 'x64',
      total_jobs_run: 450,
      success_rate: 98.2,
      provider_id: 'provider-1',
      created_at: new Date(Date.now() - 86400000 * 30).toISOString()
    },
    {
      id: 'runner-2',
      name: 'windows-runner-01',
      external_id: 'runner-ext-2',
      status: 'online',
      busy: true,
      labels: ['windows', 'x64', 'self-hosted'],
      os: 'windows',
      architecture: 'x64',
      total_jobs_run: 280,
      success_rate: 95.5,
      provider_id: 'provider-1',
      created_at: new Date(Date.now() - 86400000 * 20).toISOString()
    },
    {
      id: 'runner-3',
      name: 'macos-runner-01',
      external_id: 'runner-ext-3',
      status: 'offline',
      busy: false,
      labels: ['macos', 'arm64', 'self-hosted'],
      os: 'macos',
      architecture: 'arm64',
      total_jobs_run: 120,
      success_rate: 92.0,
      provider_id: 'provider-1',
      created_at: new Date(Date.now() - 86400000 * 10).toISOString()
    }
  ];

  const mockRunnerStats = {
    total: 3,
    online: 2,
    offline: 1,
    busy: 1
  };

  cy.intercept('GET', '/api/v1/git_runners*', {
    statusCode: 200,
    body: {
      success: true,
      data: {
        runners: mockRunners,
        stats: mockRunnerStats,
        pagination: { current_page: 1, per_page: 20, total_pages: 1, total_count: 3 }
      }
    }
  }).as('getRunners');

  cy.intercept('GET', /\/api\/v1\/git_runners\/[^\/]+$/, {
    statusCode: 200,
    body: { success: true, data: mockRunners[0] }
  }).as('getRunner');

  cy.intercept('POST', '/api/v1/git_runners/sync*', {
    statusCode: 200,
    body: { success: true, data: { synced_count: 3 } }
  }).as('syncRunners');

  cy.intercept('DELETE', '/api/v1/git_runners/*').as('deleteRunner');

  // Integrations with mock data
  const mockIntegrations = [
    {
      id: 'int-1',
      name: 'GitHub Integration',
      type: 'github_action',
      status: 'active',
      execution_count: 125,
      last_executed_at: new Date(Date.now() - 3600000).toISOString(),
      created_at: new Date(Date.now() - 86400000 * 30).toISOString()
    },
    {
      id: 'int-2',
      name: 'Slack Webhook',
      type: 'webhook',
      status: 'active',
      execution_count: 450,
      last_executed_at: new Date(Date.now() - 1800000).toISOString(),
      created_at: new Date(Date.now() - 86400000 * 60).toISOString()
    },
    {
      id: 'int-3',
      name: 'Custom MCP Server',
      type: 'mcp_server',
      status: 'paused',
      execution_count: 50,
      last_executed_at: new Date(Date.now() - 86400000).toISOString(),
      created_at: new Date(Date.now() - 86400000 * 15).toISOString()
    }
  ];

  cy.intercept('GET', '/api/v1/integrations/instances*', {
    statusCode: 200,
    body: { success: true, data: { instances: mockIntegrations } }
  }).as('getIntegrations');

  cy.intercept('GET', /\/api\/v1\/integrations\/instances\/[^\/]+$/, {
    statusCode: 200,
    body: { success: true, data: mockIntegrations[0] }
  }).as('getIntegration');

  cy.intercept('POST', '/api/v1/integrations/instances*').as('createIntegration');
  cy.intercept('PUT', '/api/v1/integrations/instances/*').as('updateIntegration');
  cy.intercept('DELETE', '/api/v1/integrations/instances/*').as('deleteIntegration');
  cy.intercept('POST', '/api/v1/integrations/instances/*/activate*').as('activateIntegration');
  cy.intercept('POST', '/api/v1/integrations/instances/*/deactivate*').as('deactivateIntegration');

  // Legacy endpoints
  cy.intercept('GET', '/api/v1/api-keys*').as('getApiKeysLegacy');
  cy.intercept('GET', '/api/v1/integrations*').as('getIntegrationsLegacy');
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

  // Audit logs endpoints with mock data
  const mockAuditLogs = {
    data: [
      {
        id: 'log-1',
        event_type: 'user.login',
        action: 'login',
        actor_id: 'user-1',
        actor_email: 'demo@powernode.org',
        actor_name: 'Demo User',
        ip_address: '192.168.1.1',
        user_agent: 'Mozilla/5.0',
        status: 'success',
        risk_level: 'low',
        created_at: new Date().toISOString(),
        metadata: {}
      },
      {
        id: 'log-2',
        event_type: 'user.password_changed',
        action: 'password_change',
        actor_id: 'user-1',
        actor_email: 'demo@powernode.org',
        actor_name: 'Demo User',
        ip_address: '192.168.1.1',
        user_agent: 'Mozilla/5.0',
        status: 'success',
        risk_level: 'medium',
        created_at: new Date(Date.now() - 86400000).toISOString(),
        metadata: {}
      }
    ],
    meta: {
      total: 2,
      current_page: 1,
      total_pages: 1,
      per_page: 25
    }
  };

  const mockSecuritySummary = {
    totalEvents: 156,
    securityEvents: 24,
    failedEvents: 8,
    highRiskEvents: 3,
    suspiciousEvents: 2,
    uniqueUsers: 12,
    uniqueIps: 8
  };

  cy.intercept('GET', '/api/v1/audit_logs*', {
    statusCode: 200,
    body: { success: true, ...mockAuditLogs }
  }).as('getAuditLogsNew');

  cy.intercept('GET', '/api/v1/audit_logs/security_summary*', {
    statusCode: 200,
    body: { success: true, data: mockSecuritySummary }
  }).as('getSecuritySummary');

  // System services endpoints with mock data
  const mockServices = [
    {
      id: 'service-1',
      name: 'Email Service',
      type: 'email',
      provider: 'SMTP',
      status: 'active',
      description: 'Email delivery service via SMTP',
      last_checked_at: new Date().toISOString(),
      health: 'healthy',
      latency_ms: 45
    },
    {
      id: 'service-2',
      name: 'Storage Service',
      type: 'storage',
      provider: 'S3',
      status: 'active',
      description: 'Cloud storage service',
      last_checked_at: new Date().toISOString(),
      health: 'healthy',
      latency_ms: 120
    },
    {
      id: 'service-3',
      name: 'Queue Service',
      type: 'queue',
      provider: 'Redis',
      status: 'active',
      description: 'Background job queue via Redis',
      last_checked_at: new Date().toISOString(),
      health: 'healthy',
      latency_ms: 5
    },
    {
      id: 'service-4',
      name: 'Database Service',
      type: 'database',
      provider: 'PostgreSQL',
      status: 'active',
      description: 'Primary database connection',
      last_checked_at: new Date().toISOString(),
      health: 'healthy',
      latency_ms: 12
    }
  ];

  cy.intercept('GET', '/api/v1/system/services*', {
    statusCode: 200,
    body: { success: true, data: { services: mockServices } }
  }).as('getSystemServices');

  cy.intercept('POST', '/api/v1/system/services/*/test*', {
    statusCode: 200,
    body: { success: true, data: { status: 'healthy', latency_ms: 50 } }
  }).as('testServiceConnection');

  cy.intercept('PUT', '/api/v1/system/services/*', {
    statusCode: 200,
    body: { success: true, data: {} }
  }).as('updateService');
});

// Marketplace-related intercepts
Cypress.Commands.add('setupMarketplaceIntercepts', () => {
  // Mock subscription data with both active and paused subscriptions
  const mockSubscriptions = [
    {
      id: 'sub-1',
      item_id: 'item-1',
      item_name: 'Workflow Automation Pro',
      item_type: 'workflow_template',
      item_icon: null,
      status: 'active',
      tier: 'Pro',
      subscribed_at: '2024-01-15T10:00:00Z'
    },
    {
      id: 'sub-2',
      item_id: 'item-2',
      item_name: 'Integration Helper',
      item_type: 'integration_template',
      item_icon: null,
      status: 'paused',
      tier: 'Basic',
      subscribed_at: '2024-02-01T14:30:00Z'
    },
    {
      id: 'sub-3',
      item_id: 'item-3',
      item_name: 'Pipeline Builder',
      item_type: 'pipeline_template',
      item_icon: null,
      status: 'active',
      tier: 'Enterprise',
      subscribed_at: '2024-03-10T09:15:00Z'
    }
  ];

  // Mock marketplace items data
  const mockItems = [
    {
      id: 'item-1',
      name: 'Workflow Automation Pro',
      description: 'Professional workflow automation tools',
      type: 'workflow_template',
      icon: null,
      rating: 4.8,
      install_count: 1250,
      version: '2.1.0',
      tags: ['automation', 'workflow', 'productivity'],
      is_verified: true,
      category: 'Automation',
      status: 'published'
    },
    {
      id: 'item-2',
      name: 'Integration Helper',
      description: 'Connect your services seamlessly',
      type: 'integration_template',
      icon: null,
      rating: 4.5,
      install_count: 890,
      version: '1.3.2',
      tags: ['integration', 'api', 'connector'],
      is_verified: true,
      category: 'Integration',
      status: 'published'
    },
    {
      id: 'item-3',
      name: 'Pipeline Builder',
      description: 'Build powerful data pipelines',
      type: 'pipeline_template',
      icon: null,
      rating: 4.7,
      install_count: 560,
      version: '3.0.1',
      tags: ['pipeline', 'data', 'etl'],
      is_verified: false,
      category: 'Data',
      status: 'published'
    }
  ];

  // Single item detail mock
  const mockItemDetail = {
    ...mockItems[0],
    long_description: 'Detailed description of the workflow automation tool',
    author: 'Powernode Team',
    created_at: '2024-01-01T00:00:00Z',
    updated_at: '2024-06-15T12:00:00Z'
  };

  // Main marketplace endpoint - matches /api/v1/marketplace?page=1&per_page=20 etc
  cy.intercept('GET', /\/api\/v1\/marketplace(\?.*)?$/, {
    statusCode: 200,
    body: { success: true, data: mockItems }
  }).as('getMarketplace');
  // Item detail endpoint - matches /api/v1/marketplace/{type}/{id}
  cy.intercept('GET', /\/api\/v1\/marketplace\/[^\/]+\/[^\/]+$/, {
    statusCode: 200,
    body: { success: true, data: mockItemDetail }
  }).as('getMarketplaceItem');
  // Subscribe to an item - matches /api/v1/marketplace/{type}/{id}/subscribe
  cy.intercept('POST', /\/api\/v1\/marketplace\/[^\/]+\/[^\/]+\/subscribe/, {
    statusCode: 200,
    body: { success: true, data: { id: 'sub-new', status: 'active' } }
  }).as('subscribeItem');

  // Subscriptions endpoints with mock data
  cy.intercept('GET', '/api/v1/marketplace/subscriptions*', {
    statusCode: 200,
    body: { success: true, data: mockSubscriptions }
  }).as('getSubscriptions');
  cy.intercept('POST', '/api/v1/marketplace/subscriptions/*/pause*', {
    statusCode: 200,
    body: { success: true, data: { id: 'sub-1', status: 'paused' } }
  }).as('pauseSubscription');
  cy.intercept('POST', '/api/v1/marketplace/subscriptions/*/resume*', {
    statusCode: 200,
    body: { success: true, data: { id: 'sub-2', status: 'active' } }
  }).as('resumeSubscription');
  cy.intercept('DELETE', '/api/v1/marketplace/subscriptions/*', {
    statusCode: 200,
    body: { success: true, data: { id: 'sub-1', status: 'cancelled' } }
  }).as('cancelSubscription');
});

// Content-related intercepts
Cypress.Commands.add('setupContentIntercepts', () => {
  // Mock page data
  const mockPage = {
    id: 'page-123',
    title: 'Test Page Title',
    slug: 'test-page',
    content: '# Welcome\n\nThis is test content.',
    rendered_content: '<h1>Welcome</h1><p>This is test content.</p>',
    meta_description: 'Test page description',
    status: 'published',
    published_at: '2025-01-10T10:00:00Z',
    word_count: 150,
    estimated_read_time: 2,
    created_at: '2025-01-01T00:00:00Z',
    updated_at: '2025-01-10T10:00:00Z'
  };

  const mockPages = [mockPage, { ...mockPage, id: 'page-456', title: 'Another Page', slug: 'another-page' }];

  // Mock KB article data
  const mockKbArticle = {
    id: 'article-123',
    title: 'Test KB Article',
    slug: 'test-article',
    content: '# KB Article Content\n\nThis is knowledge base content.',
    rendered_content: '<h1>KB Article Content</h1><p>This is knowledge base content.</p>',
    category_id: 'cat-1',
    category: { id: 'cat-1', name: 'Getting Started', slug: 'getting-started' },
    tags: ['help', 'tutorial', 'guide'],
    status: 'published',
    published_at: '2025-01-10T10:00:00Z',
    view_count: 250,
    is_featured: true,
    estimated_read_time: 5,
    author: { id: 'user-1', name: 'John Doe', email: 'john@example.com' },
    created_at: '2025-01-01T00:00:00Z',
    updated_at: '2025-01-10T10:00:00Z'
  };

  const mockKbArticles = [
    mockKbArticle,
    { ...mockKbArticle, id: 'article-456', title: 'Second Article', slug: 'second-article', is_featured: false }
  ];

  const mockKbCategories = [
    { id: 'cat-1', name: 'Getting Started', slug: 'getting-started', article_count: 5 },
    { id: 'cat-2', name: 'Troubleshooting', slug: 'troubleshooting', article_count: 3 },
    { id: 'cat-3', name: 'Advanced Topics', slug: 'advanced-topics', article_count: 8 }
  ];

  // Pages endpoints with mock data
  cy.intercept('GET', '/api/v1/pages', {
    statusCode: 200,
    body: { success: true, data: mockPages, meta: { current_page: 1, per_page: 20, total_count: 2, total_pages: 1 } }
  }).as('getPages');

  cy.intercept('GET', /\/api\/v1\/pages\/[^\/]+$/, {
    statusCode: 200,
    body: { success: true, data: mockPage }
  }).as('getPage');

  cy.intercept('POST', '/api/v1/pages*').as('createPage');
  cy.intercept('PUT', '/api/v1/pages/*').as('updatePage');
  cy.intercept('DELETE', '/api/v1/pages/*').as('deletePage');

  // Admin pages endpoints
  cy.intercept('GET', '/api/v1/admin/pages*', {
    statusCode: 200,
    body: { success: true, data: mockPages, meta: { current_page: 1, per_page: 20, total_count: 2, total_pages: 1 } }
  }).as('getAdminPages');

  cy.intercept('GET', /\/api\/v1\/admin\/pages\/[^\/]+$/, {
    statusCode: 200,
    body: { success: true, data: mockPage }
  }).as('getAdminPage');

  // KB endpoints with mock data
  cy.intercept('GET', '/api/v1/kb/articles*', {
    statusCode: 200,
    body: { success: true, data: mockKbArticles, meta: { current_page: 1, per_page: 20, total_count: 2, total_pages: 1 } }
  }).as('getKbArticles');

  cy.intercept('GET', /\/api\/v1\/kb\/articles\/[^\/]+$/, {
    statusCode: 200,
    body: { success: true, data: mockKbArticle }
  }).as('getKbArticle');

  cy.intercept('GET', '/api/v1/kb/categories*', {
    statusCode: 200,
    body: { success: true, data: mockKbCategories }
  }).as('getKbCategories');

  cy.intercept('GET', /\/api\/v1\/kb\/categories\/[^\/]+$/, {
    statusCode: 200,
    body: { success: true, data: mockKbCategories[0] }
  }).as('getKbCategory');

  // Catch-all for KB endpoints
  cy.intercept('GET', '/api/v1/kb*', {
    statusCode: 200,
    body: { success: true, data: mockKbArticles }
  }).as('getKnowledgeBase');

  cy.intercept('GET', '/api/v1/blog*').as('getBlog');

  cy.intercept('POST', '/api/v1/kb/**').as('createKbContent');
  cy.intercept('PUT', '/api/v1/kb/**').as('updateKbContent');
  cy.intercept('DELETE', '/api/v1/kb/**').as('deleteKbContent');
});

// Privacy-related intercepts
Cypress.Commands.add('setupPrivacyIntercepts', () => {
  // Mock consent preferences data
  const mockConsents = {
    marketing: { granted: true, required: false, description: 'Receive marketing emails and promotional content' },
    analytics: { granted: true, required: false, description: 'Allow usage analytics to improve our services' },
    cookies: { granted: true, required: true, description: 'Essential cookies for site functionality' },
    data_sharing: { granted: false, required: false, description: 'Share data with trusted partners' },
    third_party: { granted: false, required: false, description: 'Allow third-party integrations' },
    communications: { granted: true, required: true, description: 'Service-related communications' },
    newsletter: { granted: true, required: false, description: 'Weekly newsletter updates' },
    promotional: { granted: false, required: false, description: 'Promotional offers and discounts' },
  };

  // Mock privacy dashboard response
  const mockDashboard = {
    consents: mockConsents,
    export_requests: [],
    deletion_requests: [],
    terms_status: {
      needs_review: false,
      missing: []
    },
    data_retention_info: []
  };

  // Dashboard endpoint - returns full privacy dashboard data
  cy.intercept('GET', '/api/v1/privacy/dashboard*', {
    statusCode: 200,
    body: { success: true, data: mockDashboard }
  }).as('getPrivacyDashboard');

  // Consents endpoints
  cy.intercept('GET', '/api/v1/privacy/consents*', {
    statusCode: 200,
    body: { success: true, data: { consents: mockConsents, consent_types: {} } }
  }).as('getConsents');

  cy.intercept('PUT', '/api/v1/privacy/consents*', {
    statusCode: 200,
    body: { success: true, data: { consents: mockConsents } }
  }).as('updateConsents');

  // Export endpoints
  cy.intercept('GET', '/api/v1/privacy/exports*', {
    statusCode: 200,
    body: { success: true, data: { requests: [] } }
  }).as('getExports');

  cy.intercept('POST', '/api/v1/privacy/export*', {
    statusCode: 200,
    body: {
      success: true,
      data: {
        request: {
          id: 'export-new',
          status: 'pending',
          format: 'json',
          export_type: 'full',
          downloadable: false,
          created_at: new Date().toISOString()
        }
      }
    }
  }).as('requestExport');

  // Deletion endpoints
  cy.intercept('GET', '/api/v1/privacy/deletion*', {
    statusCode: 200,
    body: { success: true, data: { request: null } }
  }).as('getDeletionStatus');

  cy.intercept('POST', '/api/v1/privacy/deletion*', {
    statusCode: 200,
    body: {
      success: true,
      data: {
        request: {
          id: 'del-new',
          status: 'pending',
          deletion_type: 'full',
          can_be_cancelled: true,
          in_grace_period: true,
          days_until_deletion: 30,
          created_at: new Date().toISOString()
        }
      }
    }
  }).as('requestDeletion');

  cy.intercept('DELETE', '/api/v1/privacy/deletion/*', {
    statusCode: 200,
    body: { success: true, data: { request: { id: 'del-1', status: 'cancelled' } } }
  }).as('cancelDeletion');
});

// Wait for page load (loading spinner gone, page container visible)
Cypress.Commands.add('waitForPageLoad', () => {
  // Wait for any loading spinners to disappear (quick check)
  cy.get('[data-testid="loading-spinner"], .loading-spinner, [data-loading="true"]', { timeout: 50 })
    .should('not.exist')
    .then({ timeout: 50 }, () => {}); // Ignore if not found

  // Wait for page container to be visible (reduced from 10s to 5s)
  cy.get('[data-testid="page-container"], [data-testid="page-content"], main', { timeout: 5000 })
    .should('be.visible');
});

// Wait for table to load with data
Cypress.Commands.add('waitForTableLoad', () => {
  // Wait for table to exist and have rows (reduced from 10s to 5s)
  cy.get('table tbody tr, [data-testid="table-row"], [role="row"]', { timeout: 5000 })
    .should('exist');

  // Ensure loading states are cleared
  cy.get('[data-testid="table-loading"], [data-loading="true"]', { timeout: 50 })
    .should('not.exist')
    .then({ timeout: 50 }, () => {}); // Ignore if not found
});

// Wait for modal to be visible (reduced from 10s to 5s)
Cypress.Commands.add('waitForModal', () => {
  cy.get('[data-testid="modal"], [role="dialog"], .modal', { timeout: 5000 })
    .should('be.visible');
});

// Wait for modal to close (reduced from 10s to 5s)
Cypress.Commands.add('waitForModalClose', () => {
  cy.get('[data-testid="modal"], [role="dialog"], .modal', { timeout: 5000 })
    .should('not.exist');
});

// Wait for DOM to stabilize (no rapid changes)
Cypress.Commands.add('waitForStableDOM', () => {
  // Use Cypress retry-ability instead of explicit waits
  // Verify body is visible and stable
  cy.get('body').should('be.visible');
  // Only check for page-level loading spinners, not button spinners
  // Use a more specific selector to avoid matching button loading states
  cy.get('[data-testid="loading-spinner"], .loading-spinner, [data-loading="true"]', { timeout: 50 })
    .should('not.exist')
    .then({ timeout: 50 }, () => {}); // Ignore if not found
});

// Wait for element to be actionable (visible and not covered by overlays)
Cypress.Commands.add('waitForActionable', (selector: string) => {
  // First ensure any overlays are gone
  cy.get('[data-testid="modal-overlay"], .modal-backdrop, [data-testid="loading-overlay"]', { timeout: 50 })
    .should('not.exist')
    .then({ timeout: 50 }, () => {}); // Ignore if not found

  // Then wait for element to be visible and return it (reduced from 10s to 5s)
  return cy.get(selector, { timeout: 5000 }).should('be.visible');
});

export {};
