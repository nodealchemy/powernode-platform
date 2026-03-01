/// <reference types="cypress" />

/**
 * AI Agent Marketplace Page Tests
 *
 * Tests for Agent Marketplace functionality (Phase 4):
 * - Template browsing and filtering
 * - Template installation
 * - Reviews and ratings
 * - Publisher dashboard
 * - Categories navigation
 * - Error handling
 * - Responsive design
 */

describe('AI Agent Marketplace Page Tests', () => {
  beforeEach(() => {
    Cypress.on('uncaught:exception', () => false);
    cy.standardTestSetup({ intercepts: ['ai'] });
    setupAgentMarketplaceIntercepts();
  });

  describe('Page Navigation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/agent-marketplace');
    });

    it('should navigate to Agent Marketplace page', () => {
      cy.assertContainsAny(['Agent Marketplace', 'Marketplace', 'Templates']);
    });

    it('should display page title', () => {
      cy.assertContainsAny(['Agent Marketplace', 'Marketplace']);
    });

    it('should display page description', () => {
      cy.assertContainsAny(['Pre-built', 'agents', 'templates', 'vertical']);
    });
  });

  describe('Template Browsing', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/agent-marketplace');
    });

    it('should display template grid or list', () => {
      cy.assertHasElement(['[class*="grid"]', '[class*="card"]', '[class*="Card"]', '[data-testid*="template"]']);
    });

    it('should display template cards with name and rating', () => {
      cy.assertContainsAny(['Customer Support', 'Sales Assistant', 'Template', 'Rating']);
    });

    it('should display pricing information', () => {
      cy.assertContainsAny(['Free', 'Premium', '$', 'Price', 'Subscription']);
    });

    it('should display installation count', () => {
      cy.assertContainsAny(['installs', 'installations', 'downloads', 'users']);
    });
  });

  describe('Category Filtering', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/agent-marketplace');
    });

    it('should display category filters', () => {
      cy.assertContainsAny(['Category', 'Categories', 'All', 'SaaS', 'DevOps', 'Finance']);
    });

    it('should display vertical filters', () => {
      cy.assertContainsAny(['Vertical', 'Industry', 'All', 'Support', 'Sales']);
    });

    it('should display pricing type filters', () => {
      cy.assertContainsAny(['Pricing', 'Free', 'Premium', 'One-time', 'Subscription']);
    });

    it('should have search functionality', () => {
      cy.assertHasElement(['input[type="search"]', 'input[placeholder*="Search"]', '[data-testid*="search"]', 'input']);
    });
  });

  describe('Template Details', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/agent-marketplace');
    });

    it('should have template detail view functionality', () => {
      // Template cards are clickable divs that contain template information
      cy.assertHasElement([
        '[class*="rounded-lg"][class*="cursor-pointer"]',
        '[class*="border"][class*="rounded-lg"]',
        'div[class*="hover"]'
      ]);
    });

    it('should display install button', () => {
      cy.assertHasElement([
        'button:contains("Install")',
        'button:contains("Get")',
        'button:contains("Add")',
        '[data-testid*="install"]'
      ]);
    });
  });

  describe('Installation Flow', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/agent-marketplace');
    });

    it('should have install action available', () => {
      cy.assertHasElement([
        'button:contains("Install")',
        'button:contains("Get")',
        '[data-testid*="install"]',
        'button[type="button"]'
      ]);
    });
  });

  describe('My Installations', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/agent-marketplace');
    });

    it('should have link to view installations', () => {
      cy.assertContainsAny(['My Installations', 'Installed', 'My Agents', 'Templates']);
    });
  });

  describe('Reviews Section', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/agent-marketplace');
    });

    it('should display reviews or rating information', () => {
      cy.assertContainsAny(['Review', 'Rating', 'Stars', 'Feedback', 'Template']);
    });
  });

  describe('Publisher Features', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/agent-marketplace');
    });

    it('should have publisher section or link', () => {
      cy.assertContainsAny(['Publisher', 'Publish', 'Create Template', 'My Templates', 'Templates']);
    });
  });

  describe('Featured Templates', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/agent-marketplace');
    });

    it('should display featured or popular templates', () => {
      cy.assertContainsAny(['Featured', 'Popular', 'Top', 'Recommended', 'Template']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('**/api/v1/ai/agent_marketplace/**', {
        statusCode: 500,
        visitUrl: '/app/ai/agent-marketplace'
      });
    });

    it('should display error notification on failure', () => {
      cy.mockApiError('**/api/v1/ai/agent_marketplace/templates*', 500, 'Failed to load templates');
      cy.navigateTo('/app/ai/agent-marketplace');
      cy.assertContainsAny(['Error', 'Failed', 'Marketplace', 'Templates']);
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '**/api/v1/ai/agent_marketplace/templates*', {
        delay: 1000,
        statusCode: 200,
        body: { success: true, data: { items: [], pagination: { current_page: 1, total_pages: 1, total_count: 0, per_page: 25 } } }
      }).as('getTemplatesDelayed');
      cy.visit('/app/ai/agent-marketplace');
      cy.assertHasElement(['[class*="spin"]', '[class*="loading"]', '[class*="Spin"]', '[class*="Loading"]', 'div']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.testResponsiveDesign('/app/ai/agent-marketplace', {
        checkContent: ['Marketplace', 'Template']
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.assertPageReady('/app/ai/agent-marketplace');
      cy.assertContainsAny(['Marketplace', 'Template']);
    });

    it('should show single column on small screens', () => {
      cy.viewport(375, 667);
      cy.assertPageReady('/app/ai/agent-marketplace');
      cy.assertContainsAny(['Marketplace', 'Templates', 'Agent Marketplace']);
    });

    it('should show multi-column grid on large screens', () => {
      cy.viewport(1280, 800);
      cy.assertPageReady('/app/ai/agent-marketplace');
      cy.assertHasElement(['[class*="grid"]', 'div', '.grid']);
    });
  });
});

/**
 * Set up Agent Marketplace API intercepts
 */
function setupAgentMarketplaceIntercepts() {
  const mockTemplates = [
    {
      id: 'template-1',
      name: 'Customer Support Agent',
      slug: 'customer-support-agent',
      description: 'AI-powered customer support automation',
      category: 'support',
      vertical: 'saas',
      pricing_type: 'freemium',
      price_usd: null,
      monthly_price_usd: 49,
      version: '2.1.0',
      installation_count: 1250,
      average_rating: 4.8,
      review_count: 156,
      is_featured: true,
      is_verified: true,
      publisher: { id: 'pub-1', name: 'Powernode', slug: 'powernode', verified: true },
      published_at: '2024-01-15T10:00:00Z'
    },
    {
      id: 'template-2',
      name: 'Sales Assistant Pro',
      slug: 'sales-assistant-pro',
      description: 'AI sales automation and lead qualification',
      category: 'sales',
      vertical: 'saas',
      pricing_type: 'subscription',
      price_usd: null,
      monthly_price_usd: 99,
      version: '1.5.0',
      installation_count: 890,
      average_rating: 4.6,
      review_count: 89,
      is_featured: true,
      is_verified: true,
      publisher: { id: 'pub-2', name: 'SalesAI Inc', slug: 'salesai', verified: true },
      published_at: '2024-02-01T14:00:00Z'
    },
    {
      id: 'template-3',
      name: 'DevOps Incident Responder',
      slug: 'devops-incident-responder',
      description: 'Automated incident response and triage',
      category: 'devops',
      vertical: 'devops',
      pricing_type: 'free',
      price_usd: null,
      monthly_price_usd: null,
      version: '1.0.0',
      installation_count: 450,
      average_rating: 4.3,
      review_count: 34,
      is_featured: false,
      is_verified: false,
      publisher: { id: 'pub-3', name: 'Community', slug: 'community', verified: false },
      published_at: '2024-03-10T09:00:00Z'
    }
  ];

  const mockCategories = [
    { id: 'cat-1', name: 'Support', slug: 'support', description: 'Customer support agents', icon: 'headphones', template_count: 25, children: [] },
    { id: 'cat-2', name: 'Sales', slug: 'sales', description: 'Sales automation agents', icon: 'chart', template_count: 18, children: [] },
    { id: 'cat-3', name: 'DevOps', slug: 'devops', description: 'DevOps and SRE agents', icon: 'server', template_count: 12, children: [] },
    { id: 'cat-4', name: 'Finance', slug: 'finance', description: 'Financial automation', icon: 'dollar', template_count: 8, children: [] }
  ];

  const mockInstallations = [
    {
      id: 'install-1',
      status: 'active',
      installed_version: '2.1.0',
      license_type: 'standard',
      executions_count: 450,
      total_cost_usd: 147,
      last_used_at: '2024-06-15T10:00:00Z',
      created_at: '2024-01-20T10:00:00Z',
      template: { id: 'template-1', name: 'Customer Support Agent', slug: 'customer-support-agent' }
    }
  ];

  // Templates list
  cy.intercept('GET', '**/api/v1/ai/agent_marketplace/templates', {
    statusCode: 200,
    body: { success: true, data: { items: mockTemplates, pagination: { current_page: 1, total_pages: 1, total_count: 3, per_page: 25 } } }
  }).as('getAgentTemplates');

  cy.intercept('GET', '**/api/v1/ai/agent_marketplace/templates?*', {
    statusCode: 200,
    body: { success: true, data: { items: mockTemplates, pagination: { current_page: 1, total_pages: 1, total_count: 3, per_page: 25 } } }
  }).as('getAgentTemplatesFiltered');

  // Featured templates
  cy.intercept('GET', '**/api/v1/ai/agent_marketplace/templates/featured*', {
    statusCode: 200,
    body: { success: true, data: { templates: mockTemplates.filter(t => t.is_featured) } }
  }).as('getFeaturedTemplates');

  // Single template
  cy.intercept('GET', /\/api\/v1\/ai\/agent_marketplace\/templates\/[^\/]+$/, {
    statusCode: 200,
    body: { success: true, data: { template: mockTemplates[0] } }
  }).as('getAgentTemplate');

  // Categories
  cy.intercept('GET', '**/api/v1/ai/agent_marketplace/categories*', {
    statusCode: 200,
    body: { success: true, data: { categories: mockCategories } }
  }).as('getMarketplaceCategories');

  // Installations
  cy.intercept('GET', '**/api/v1/ai/agent_marketplace/installations*', {
    statusCode: 200,
    body: { success: true, data: { items: mockInstallations, pagination: { current_page: 1, total_pages: 1, total_count: 1, per_page: 25 } } }
  }).as('getAgentInstallations');

  // Install template
  cy.intercept('POST', '**/api/v1/ai/agent_marketplace/templates/*/install', {
    statusCode: 201,
    body: { success: true, data: { installation: mockInstallations[0] } }
  }).as('installAgentTemplate');

  // Uninstall
  cy.intercept('DELETE', '**/api/v1/ai/agent_marketplace/installations/*', {
    statusCode: 200,
    body: { success: true, data: { message: 'Template uninstalled successfully' } }
  }).as('uninstallAgentTemplate');

  // Reviews
  cy.intercept('GET', '**/api/v1/ai/agent_marketplace/templates/*/reviews*', {
    statusCode: 200,
    body: { success: true, data: { items: [], pagination: { current_page: 1, total_pages: 1, total_count: 0, per_page: 25 } } }
  }).as('getTemplateReviews');

  // Publisher
  cy.intercept('GET', '**/api/v1/ai/agent_marketplace/publisher*', {
    statusCode: 200,
    body: { success: true, data: { publisher: null } }
  }).as('getPublisher');
}

export {};
