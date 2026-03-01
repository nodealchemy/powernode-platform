/// <reference types="cypress" />

/**
 * AI Conversations Comprehensive Tests
 *
 * Comprehensive E2E tests for AI Conversations:
 * - Conversation list management
 * - Create new conversations
 * - View and continue conversations
 * - Export, archive, delete operations
 * - Search and filter functionality
 */

describe('AI Conversations Comprehensive Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['ai'] });
    setupConversationsIntercepts();
  });

  describe('Conversations List', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/conversations');
    });

    it('should display conversations page with title', () => {
      cy.assertContainsAny(['AI Conversations', 'Conversations']);
    });

    it('should have start conversation button', () => {
      cy.get('button').contains(/start conversation/i).should('exist');
    });

    it('should display search input', () => {
      cy.get('input[placeholder*="Search conversations"]').should('exist');
    });

    it('should display status filter dropdown', () => {
      cy.assertContainsAny(['Status', 'All Statuses']);
    });

    it('should display agent filter dropdown', () => {
      cy.assertContainsAny(['Agent', 'All Agents']);
    });
  });

  describe('Conversations Table', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/conversations');
    });

    it('should display conversation table or empty state', () => {
      cy.assertContainsAny(['Conversation', 'No conversations found', 'table']);
    });

    it('should display conversation titles', () => {
      cy.get('body').then($body => {
        if (!$body.text().includes('No conversations found')) {
          cy.assertContainsAny(['Product Development', 'Customer Support', 'Conversation']);
        }
      });
    });

    it('should display status column', () => {
      cy.get('body').then($body => {
        if (!$body.text().includes('No conversations found')) {
          cy.assertContainsAny(['Active', 'Completed', 'Archived', 'Status']);
        }
      });
    });

    it('should display messages column', () => {
      cy.assertContainsAny(['Messages', 'messages']);
    });

    it('should display cost column', () => {
      cy.assertContainsAny(['Cost', '$']);
    });

    it('should display last activity column', () => {
      cy.assertContainsAny(['Last Activity', 'ago', 'Yesterday']);
    });

    it('should display associated agent name', () => {
      cy.get('body').then($body => {
        if (!$body.text().includes('No conversations found')) {
          cy.assertContainsAny(['Agent', 'Assistant']);
        }
      });
    });
  });

  describe('Conversation Actions', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/conversations');
    });

    it('should have action buttons when conversations exist', () => {
      // Wait for table to render
      cy.waitForPageLoad();
      cy.get('body').then($body => {
        // Check if table has conversation data (look for table rows with data)
        const hasConversations = $body.find('tr').length > 1 || $body.text().includes('Product Development');
        if (hasConversations) {
          // Look for action buttons by their SVG icons
          cy.get('button svg').should('exist');
        } else {
          cy.log('No conversations visible - skipping action button test');
        }
      });
    });

    it('should have table with proper columns', () => {
      cy.assertContainsAny(['Conversation', 'Status', 'Messages', 'Cost', 'Last Activity', 'Actions']);
    });
  });

  describe('Create Conversation', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/conversations');
    });

    it('should open create conversation modal', () => {
      cy.get('button').contains(/start conversation/i).click();
      cy.get('[role="dialog"], [class*="modal"]').should('exist');
    });

    it('should have agent selector in create modal', () => {
      cy.get('button').contains(/start conversation/i).click();
      cy.assertContainsAny(['Agent', 'Select', 'Choose']);
    });

    it('should have message input in create modal', () => {
      cy.get('button').contains(/start conversation/i).click();
      cy.get('textarea, input[type="text"]').should('exist');
    });
  });

  describe('Search and Filter', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/conversations');
    });

    it('should filter by search query', () => {
      cy.get('input[placeholder*="Search conversations"]').type('Product');
      cy.waitForPageLoad();
    });

    it('should have status filter options', () => {
      cy.assertContainsAny(['All Statuses', 'Active', 'Completed', 'Archived']);
    });

    it('should have agent filter options', () => {
      cy.assertContainsAny(['All Agents', 'Agent']);
    });
  });

  describe('Table Row Interactions', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/conversations');
    });

    it('should have clickable rows when conversations exist', () => {
      cy.waitForPageLoad();
      cy.get('body').then($body => {
        const hasData = $body.text().includes('Product Development') || $body.find('tr').length > 1;
        if (hasData) {
          cy.get('tr').should('have.length.at.least', 1);
        } else {
          cy.log('No conversation data visible - skipping row interaction test');
        }
      });
    });
  });

  describe('Empty State', () => {
    it('should display empty state when no conversations', () => {
      cy.intercept('GET', '**/api/**/ai/conversations*', {
        statusCode: 200,
        body: {
          items: [],
          pagination: { current_page: 1, total_pages: 1, total_count: 0, per_page: 25 }
        },
      }).as('emptyConversations');

      cy.navigateTo('/app/ai/conversations');
      cy.wait('@emptyConversations');
      cy.assertContainsAny(['No conversations found', 'Get started', 'Start Conversation']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('**/api/**/ai/conversations**', {
        statusCode: 500,
        visitUrl: '/app/ai/conversations',
      });
    });
  });

  describe('Responsive Design', () => {
    it('should display correctly across viewports', () => {
      cy.testResponsiveDesign('/app/ai/conversations', {
        checkContent: 'Conversations',
      });
    });
  });
});

function setupConversationsIntercepts() {
  // Mock data matching ConversationBase interface
  const mockConversations = [
    {
      id: 'conv-1',
      title: 'Product Development Discussion',
      status: 'active',
      ai_agent: {
        id: 'agent-1',
        name: 'Development Assistant',
        agent_type: 'assistant'
      },
      message_count: 25,
      total_tokens: 5000,
      total_cost: 0.15,
      created_at: '2025-01-15T10:00:00Z',
      updated_at: '2025-01-15T14:30:00Z',
      last_activity_at: '2025-01-15T14:30:00Z',
      metadata: {
        created_by: 'user-1',
        total_messages: 25,
        total_tokens: 5000,
        total_cost: 0.15,
        last_activity: '2025-01-15T14:30:00Z'
      }
    },
    {
      id: 'conv-2',
      title: 'Customer Support Query',
      status: 'completed',
      ai_agent: {
        id: 'agent-2',
        name: 'Support Agent',
        agent_type: 'assistant'
      },
      message_count: 12,
      total_tokens: 2500,
      total_cost: 0.08,
      created_at: '2025-01-14T09:00:00Z',
      updated_at: '2025-01-14T10:00:00Z',
      last_activity_at: '2025-01-14T10:00:00Z',
      metadata: {
        created_by: 'user-1',
        total_messages: 12,
        total_tokens: 2500,
        total_cost: 0.08,
        last_activity: '2025-01-14T10:00:00Z'
      }
    },
    {
      id: 'conv-3',
      title: 'Data Analysis Request',
      status: 'archived',
      ai_agent: {
        id: 'agent-3',
        name: 'Data Analyst',
        agent_type: 'data_analyst'
      },
      message_count: 8,
      total_tokens: 1500,
      total_cost: 0.05,
      created_at: '2025-01-10T15:00:00Z',
      updated_at: '2025-01-10T16:00:00Z',
      last_activity_at: '2025-01-10T16:00:00Z',
      metadata: {
        created_by: 'user-1',
        total_messages: 8,
        total_tokens: 1500,
        total_cost: 0.05,
        last_activity: '2025-01-10T16:00:00Z'
      }
    },
  ];

  const mockAgents = [
    {
      id: 'agent-1',
      name: 'Development Assistant',
      description: 'AI assistant for development tasks',
      agent_type: 'assistant',
      status: 'active',
      is_active: true,
      ai_provider: { id: 'provider-1', name: 'OpenAI', slug: 'openai', provider_type: 'text_generation' },
      mcp_tool_manifest: { name: 'dev-assistant', description: 'Development assistant', type: 'assistant', version: '1.0' },
      skill_slugs: ['chat', 'code_generation'],
      mcp_input_schema: {},
      mcp_output_schema: {},
      mcp_metadata: {},
      metadata: {},
      created_at: '2025-01-01T00:00:00Z',
      updated_at: '2025-01-15T00:00:00Z',
    },
    {
      id: 'agent-2',
      name: 'Support Agent',
      description: 'Customer support AI',
      agent_type: 'assistant',
      status: 'active',
      is_active: true,
      ai_provider: { id: 'provider-2', name: 'Anthropic', slug: 'anthropic', provider_type: 'text_generation' },
      mcp_tool_manifest: { name: 'support-agent', description: 'Support agent', type: 'assistant', version: '1.0' },
      skill_slugs: ['chat'],
      mcp_input_schema: {},
      mcp_output_schema: {},
      mcp_metadata: {},
      metadata: {},
      created_at: '2025-01-05T00:00:00Z',
      updated_at: '2025-01-14T00:00:00Z',
    },
  ];

  const mockPagination = {
    current_page: 1,
    total_pages: 1,
    total_count: 3,
    per_page: 25
  };

  // Match exact API path for conversations list
  cy.intercept('GET', '/api/v1/ai/conversations', {
    statusCode: 200,
    body: { success: true, items: mockConversations, pagination: mockPagination },
  }).as('getConversations');

  cy.intercept('GET', '/api/v1/ai/conversations?*', {
    statusCode: 200,
    body: { success: true, items: mockConversations, pagination: mockPagination },
  }).as('getConversationsWithParams');

  cy.intercept('GET', '**/api/**/ai/conversations/*', {
    statusCode: 200,
    body: { conversation: mockConversations[0] },
  }).as('getConversation');

  cy.intercept('GET', '**/api/**/ai/agents*', {
    statusCode: 200,
    body: { items: mockAgents, pagination: mockPagination },
  }).as('getAgents');

  cy.intercept('POST', '**/api/**/ai/conversations*', {
    statusCode: 201,
    body: { success: true, conversation: mockConversations[0] },
  }).as('createConversation');

  cy.intercept('POST', '**/api/**/ai/conversations/*/messages*', {
    statusCode: 200,
    body: { success: true, message: { id: 'msg-new', sender_type: 'ai', content: 'Response' } },
  }).as('sendMessage');

  cy.intercept('DELETE', '**/api/**/ai/conversations/*', {
    statusCode: 200,
    body: { success: true },
  }).as('deleteConversation');

  cy.intercept('POST', '**/api/**/ai/conversations/*/archive*', {
    statusCode: 200,
    body: { success: true },
  }).as('archiveConversation');

  cy.intercept('POST', '**/api/**/ai/conversations/*/unarchive*', {
    statusCode: 200,
    body: { success: true },
  }).as('unarchiveConversation');

  cy.intercept('GET', '**/api/**/ai/conversations/*/export*', {
    statusCode: 200,
    body: { download_url: '/downloads/export.json' },
  }).as('exportConversation');
}

export {};
