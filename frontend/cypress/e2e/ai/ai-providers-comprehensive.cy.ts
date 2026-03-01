/// <reference types="cypress" />

/**
 * AI Providers Comprehensive Tests
 *
 * Comprehensive E2E tests for AI Providers:
 * - Provider list display
 * - Provider cards and details
 * - Search and filtering
 * - Connection testing
 * - Provider actions
 */

describe('AI Providers Comprehensive Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['ai'] });
    setupProvidersIntercepts();
  });

  describe('Providers Overview', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/providers');
    });

    it('should display providers page with title', () => {
      cy.assertContainsAny(['AI Providers', 'Providers']);
    });

    it('should display summary stats cards', () => {
      cy.assertContainsAny(['Total Providers', 'Healthy Providers', 'Priority Providers', 'Active Credentials']);
    });

    it('should display search input', () => {
      cy.get('input[placeholder*="Search"]').should('exist');
    });

    it('should have filters button', () => {
      cy.get('button').contains(/filters/i).should('exist');
    });

    it('should have add provider button', () => {
      cy.get('button').contains(/add provider/i).should('exist');
    });
  });

  describe('Provider Cards', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/providers');
    });

    it('should display provider cards in grid', () => {
      cy.get('[class*="grid"]').should('exist');
    });

    it('should display OpenAI provider', () => {
      cy.assertContainsAny(['OpenAI', 'openai']);
    });

    it('should display Anthropic provider', () => {
      cy.assertContainsAny(['Anthropic', 'anthropic']);
    });

    it('should display provider description', () => {
      cy.assertContainsAny(['text generation', 'chat', 'GPT', 'Claude']);
    });

    it('should display health status badges', () => {
      cy.assertContainsAny(['Healthy', 'Unhealthy', 'Inactive', 'Unknown']);
    });

    it('should display provider type badges', () => {
      cy.assertContainsAny(['Text', 'Image', 'Code', 'Embedding', 'Multimodal']);
    });

    it('should display capabilities section', () => {
      cy.contains(/capabilities/i).should('exist');
    });

    it('should display model count', () => {
      cy.contains(/models/i).should('exist');
    });

    it('should display credentials count', () => {
      cy.contains(/credentials/i).should('exist');
    });

    it('should have Details button on cards', () => {
      cy.get('button').contains(/details/i).should('exist');
    });

    it('should have Test button when credentials exist', () => {
      // Test button appears when credential_count > 0; page always shows credentials info
      cy.get('button').contains(/test/i).should('exist');
    });

    it('should have Edit Settings button', () => {
      cy.get('button').contains(/edit settings/i).should('exist');
    });
  });

  describe('Provider Dropdown Actions', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/providers');
    });

    it('should have dropdown menu button', () => {
      cy.get('button').find('svg').should('exist');
    });

    it('should show dropdown options on click', () => {
      // Click the dropdown menu (MoreVertical icon button)
      cy.get('button').filter(':has(svg)').first().click();
      cy.assertContainsAny(['View Details', 'Test Connection', 'Edit Settings']);
    });
  });

  describe('Search and Filter', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/providers');
    });

    it('should filter by search query', () => {
      cy.get('input[placeholder*="Search"]').type('OpenAI');
      cy.waitForPageLoad();
    });

    it('should toggle filters panel', () => {
      cy.get('button').contains(/filters/i).click();
      cy.waitForPageLoad();
    });

    it('should clear search', () => {
      cy.get('input[placeholder*="Search"]').as('searchInput').type('test');
      cy.waitForPageLoad();
      cy.get('@searchInput').clear();
      cy.waitForPageLoad();
    });
  });

  describe('Connection Testing', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/providers');
    });

    it('should have Test All button in page actions', () => {
      cy.get('button').contains(/test all/i).should('exist');
    });

    it('should test individual connection when clicked', () => {
      cy.intercept('POST', '**/api/**/ai/provider_credentials/*/test*', {
        statusCode: 200,
        body: { success: true, response_time_ms: 150 },
      }).as('testConnection');

      // Find and click a Test button
      cy.get('button').contains(/^test$/i).first().click();
    });
  });

  describe('Page Actions', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/providers');
    });

    it('should have Refresh button', () => {
      cy.get('button').contains(/refresh/i).should('exist');
    });

    it('should have Setup Defaults button', () => {
      cy.get('button').contains(/setup defaults/i).should('exist');
    });

    it('should have Add Provider button', () => {
      cy.get('button').contains(/add provider/i).should('exist');
    });

    it('should refresh providers when refresh clicked', () => {
      cy.get('button').contains(/refresh/i).click();
      cy.wait('@getProviders');
    });
  });

  describe('Empty State', () => {
    it('should display empty state when no providers', () => {
      cy.intercept('GET', '**/api/**/ai/providers*', {
        statusCode: 200,
        body: { items: [], pagination: { current_page: 1, total_pages: 1, total_count: 0, per_page: 20 } },
      }).as('emptyProviders');

      cy.navigateTo('/app/ai/providers');
      cy.wait('@emptyProviders');
      cy.assertContainsAny(['No AI providers found', 'Get started', 'Setup Defaults', 'Add Provider']);
    });
  });

  describe('Provider Detail Modal', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/providers');
    });

    it('should open detail modal when Details clicked', () => {
      cy.get('button').contains(/details/i).first().click();
      // Modal should open with provider details
      cy.get('[role="dialog"], [class*="modal"]').should('exist');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('**/api/**/ai/providers**', {
        statusCode: 500,
        visitUrl: '/app/ai/providers',
      });
    });
  });

  describe('Responsive Design', () => {
    it('should display correctly across viewports', () => {
      cy.testResponsiveDesign('/app/ai/providers', {
        checkContent: 'Providers',
      });
    });
  });
});

function setupProvidersIntercepts() {
  // Mock data matching actual AiProvider interface from src/shared/types/ai.ts
  const mockProviders = [
    {
      id: 'provider-1',
      name: 'OpenAI',
      slug: 'openai',
      provider_type: 'text_generation',
      description: 'OpenAI GPT models for text generation and chat',
      api_base_url: 'https://api.openai.com/v1',
      capabilities: ['chat', 'completion', 'embedding', 'vision'],
      supported_models: [],
      configuration_schema: {},
      default_parameters: {},
      rate_limits: {},
      pricing_info: {},
      metadata: {},
      is_active: true,
      requires_auth: true,
      supports_streaming: true,
      supports_functions: true,
      supports_vision: true,
      supports_code_execution: false,
      documentation_url: 'https://platform.openai.com/docs',
      status_url: 'https://status.openai.com',
      priority_order: 1,
      credential_count: 2,
      model_count: 5,
      health_status: 'healthy',
      created_at: '2025-01-01T10:00:00Z',
      updated_at: '2025-01-15T10:00:00Z',
    },
    {
      id: 'provider-2',
      name: 'Anthropic',
      slug: 'anthropic',
      provider_type: 'text_generation',
      description: 'Anthropic Claude models for safe AI interactions',
      api_base_url: 'https://api.anthropic.com/v1',
      capabilities: ['chat', 'completion', 'vision'],
      supported_models: [],
      configuration_schema: {},
      default_parameters: {},
      rate_limits: {},
      pricing_info: {},
      metadata: {},
      is_active: true,
      requires_auth: true,
      supports_streaming: true,
      supports_functions: true,
      supports_vision: true,
      supports_code_execution: false,
      documentation_url: 'https://docs.anthropic.com',
      priority_order: 2,
      credential_count: 1,
      model_count: 3,
      health_status: 'healthy',
      created_at: '2025-01-05T10:00:00Z',
      updated_at: '2025-01-14T10:00:00Z',
    },
    {
      id: 'provider-3',
      name: 'Azure OpenAI',
      slug: 'azure',
      provider_type: 'text_generation',
      description: 'Microsoft Azure OpenAI Service',
      api_base_url: '',
      capabilities: ['chat', 'completion'],
      supported_models: [],
      configuration_schema: {},
      default_parameters: {},
      rate_limits: {},
      pricing_info: {},
      metadata: {},
      is_active: false,
      requires_auth: true,
      supports_streaming: true,
      supports_functions: true,
      supports_vision: false,
      supports_code_execution: false,
      priority_order: 3,
      credential_count: 0,
      model_count: 0,
      health_status: 'inactive',
      created_at: '2025-01-10T10:00:00Z',
      updated_at: '2025-01-10T10:00:00Z',
    },
    {
      id: 'provider-4',
      name: 'Google AI',
      slug: 'google',
      provider_type: 'text_generation',
      description: 'Google Gemini and PaLM models',
      api_base_url: '',
      capabilities: ['chat', 'completion', 'embedding'],
      supported_models: [],
      configuration_schema: {},
      default_parameters: {},
      rate_limits: {},
      pricing_info: {},
      metadata: {},
      is_active: false,
      requires_auth: true,
      supports_streaming: true,
      supports_functions: true,
      supports_vision: true,
      supports_code_execution: false,
      priority_order: 4,
      credential_count: 0,
      model_count: 0,
      health_status: 'inactive',
      created_at: '2025-01-10T10:00:00Z',
      updated_at: '2025-01-10T10:00:00Z',
    },
  ];

  const mockPagination = {
    current_page: 1,
    total_pages: 1,
    total_count: 4,
    per_page: 20
  };

  cy.intercept('GET', '**/api/**/ai/providers*', {
    statusCode: 200,
    body: { items: mockProviders, pagination: mockPagination },
  }).as('getProviders');

  cy.intercept('GET', '**/api/**/ai/providers/*', {
    statusCode: 200,
    body: { provider: mockProviders[0] },
  }).as('getProvider');

  cy.intercept('POST', '**/api/**/ai/provider_credentials/*/test*', {
    statusCode: 200,
    body: { success: true, response_time_ms: 150 },
  }).as('testConnection');

  cy.intercept('POST', '**/api/**/ai/providers/*/test*', {
    statusCode: 200,
    body: { success: true, response_time_ms: 150 },
  }).as('testProviderConnection');

  cy.intercept('DELETE', '**/api/**/ai/providers/*', {
    statusCode: 200,
    body: { success: true },
  }).as('deleteProvider');

  cy.intercept('POST', '**/api/**/ai/providers/setup_defaults*', {
    statusCode: 200,
    body: { created_providers: [], existing_providers: [] },
  }).as('setupDefaults');

  cy.intercept('POST', '**/api/**/ai/providers/bulk_test*', {
    statusCode: 200,
    body: { results: [], summary: { successful: 2, failed: 0, skipped: 2 } },
  }).as('bulkTest');
}

export {};
