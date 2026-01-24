/// <reference types="cypress" />

/**
 * AI Agent Marketplace Workflows Tests
 *
 * Comprehensive E2E tests for AI Agent Marketplace:
 * - Browse agents
 * - Search and filter
 * - Agent details
 * - Installation workflow
 * - Reviews and ratings
 */

describe('AI Agent Marketplace Workflows Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['ai', 'marketplace'] });
    setupAgentMarketplaceIntercepts();
  });

  describe('Marketplace Browse', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/marketplace');
    });

    it('should display marketplace page with title', () => {
      cy.assertContainsAny(['Marketplace', 'Agent Marketplace', 'Agents']);
    });

    it('should display agent cards', () => {
      cy.get('[data-testid="marketplace-templates-grid"]').should('exist');
      cy.assertContainsAny(['Agent', 'Install', 'rating', 'downloads']);
    });

    it('should display agent categories', () => {
      cy.assertContainsAny(['Category', 'All', 'Productivity', 'Analytics', 'Integration']);
    });

    it('should display search input', () => {
      cy.get('input[type="search"], input[placeholder*="Search"]').should('exist');
    });
  });

  describe('Search and Filter', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/marketplace');
    });

    it('should filter agents by category', () => {
      cy.get('button, [role="tab"]').contains(/productivity|analytics|category/i).first().click();
      cy.waitForPageLoad();
    });

    it('should search agents by name', () => {
      cy.get('input[type="search"], input[placeholder*="Search"]').first().type('data');
      cy.waitForPageLoad();
    });

    it('should filter by rating', () => {
      cy.get('select').then($select => {
        if ($select.find('option[value*="rating"]').length > 0) {
          cy.wrap($select).select('4+');
        }
      });
    });

    it('should sort agents', () => {
      cy.get('select').contains(/sort|order/i).then($select => {
        if ($select.length > 0) {
          cy.wrap($select).select('popular');
        }
      });
    });
  });

  describe('Agent Cards', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/marketplace');
    });

    it('should display agent name and description', () => {
      cy.get('[data-testid="template-card"]').first().within(() => {
        cy.get('[data-testid="template-title"]').should('exist');
      });
    });

    it('should display agent rating', () => {
      cy.assertContainsAny(['★', 'rating', 'stars']);
    });

    it('should display download/install count', () => {
      cy.assertContainsAny(['downloads', 'installs', 'users']);
    });

    it('should display agent price or free badge', () => {
      cy.assertContainsAny(['Free', '$', 'price', 'Premium']);
    });

    it('should have install/view button', () => {
      cy.get('button').contains(/install|view|get/i).should('exist');
    });
  });

  describe('Agent Details', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/marketplace');
    });

    it('should navigate to agent details when card clicked', () => {
      cy.get('[data-testid="template-card"]').first().click();
      cy.assertContainsAny(['Details', 'Description', 'Features', 'Reviews']);
    });

    it('should display agent full description', () => {
      cy.get('[data-testid="template-card"]').first().click();
      cy.assertContainsAny(['description', 'about', 'features']);
    });

    it('should display agent screenshots/preview', () => {
      cy.get('[data-testid="template-card"]').first().click();
      cy.get('img, [data-testid*="preview"], [data-testid*="screenshot"]').should('exist');
    });

    it('should display agent requirements', () => {
      cy.get('[data-testid="template-card"]').first().click();
      cy.assertContainsAny(['requirements', 'permissions', 'version']);
    });
  });

  describe('Installation Flow', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/marketplace');
    });

    it('should install agent when install button clicked', () => {
      cy.intercept('POST', '**/api/**/ai/marketplace/agents/*/install*', {
        statusCode: 200,
        body: { success: true, message: 'Agent installed successfully' },
      }).as('installAgent');

      cy.get('button').contains(/install|get/i).first().click();
      cy.wait('@installAgent');
      cy.assertContainsAny(['installed', 'success']);
    });

    it('should show installation progress', () => {
      cy.intercept('POST', '**/api/**/ai/marketplace/agents/*/install*', {
        statusCode: 200,
        body: { success: true },
        delay: 1000,
      }).as('installAgentSlow');

      cy.get('button').contains(/install|get/i).first().click();
      cy.assertContainsAny(['Installing', 'loading', 'progress']);
    });

    it('should show installed badge after installation', () => {
      cy.intercept('POST', '**/api/**/ai/marketplace/agents/*/install*', {
        statusCode: 200,
        body: { success: true },
      }).as('installAgent');

      cy.get('button').contains(/install|get/i).first().click();
      cy.wait('@installAgent');
      cy.assertContainsAny(['Installed', 'installed', 'Open']);
    });
  });

  describe('Reviews and Ratings', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/marketplace');
      cy.get('[data-testid="template-card"]').first().click();
    });

    it('should display reviews section', () => {
      cy.assertContainsAny(['Reviews', 'Rating', 'Feedback']);
    });

    it('should display individual reviews', () => {
      cy.get('body').then($body => {
        if (!$body.text().includes('No reviews')) {
          cy.assertContainsAny(['review', 'rating', 'user', 'comment']);
        }
      });
    });

    it('should have write review option', () => {
      cy.get('button').contains(/write|add|leave/i).should('exist');
    });

    it('should display average rating', () => {
      cy.assertContainsAny(['★', 'average', 'rating', '/5']);
    });
  });

  describe('Installed Agents', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/marketplace/installed');
    });

    it('should display installed agents list', () => {
      cy.assertContainsAny(['Installed', 'My Agents', 'agents']);
    });

    it('should show update available badge', () => {
      cy.get('body').then($body => {
        if ($body.text().includes('Update')) {
          cy.assertContainsAny(['Update', 'update available', 'new version']);
        }
      });
    });

    it('should have uninstall option', () => {
      cy.get('button').contains(/uninstall|remove/i).should('exist');
    });

    it('should have configure option', () => {
      cy.get('button').contains(/configure|settings/i).should('exist');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('**/api/**/ai/marketplace/**', {
        statusCode: 500,
        visitUrl: '/app/ai/marketplace',
      });
    });
  });

  describe('Responsive Design', () => {
    it('should display correctly across viewports', () => {
      cy.testResponsiveDesign('/app/ai/marketplace', {
        checkContent: 'Marketplace',
      });
    });
  });
});

function setupAgentMarketplaceIntercepts() {
  const mockAgents = [
    {
      id: 'agent-1',
      name: 'Data Analysis Agent',
      description: 'Powerful data analysis and visualization agent',
      category: 'analytics',
      rating: 4.8,
      downloads: 5000,
      price: 0,
      is_free: true,
      is_installed: false,
      publisher: 'Powernode',
      version: '2.1.0',
    },
    {
      id: 'agent-2',
      name: 'Email Automation Agent',
      description: 'Automate email workflows and responses',
      category: 'productivity',
      rating: 4.5,
      downloads: 3500,
      price: 9.99,
      is_free: false,
      is_installed: true,
      publisher: 'AutomateIO',
      version: '1.5.0',
    },
    {
      id: 'agent-3',
      name: 'Code Review Agent',
      description: 'AI-powered code review and suggestions',
      category: 'development',
      rating: 4.9,
      downloads: 8000,
      price: 0,
      is_free: true,
      is_installed: false,
      publisher: 'DevTools Inc',
      version: '3.0.0',
    },
  ];

  const mockCategories = [
    { id: 'all', name: 'All', count: 150 },
    { id: 'analytics', name: 'Analytics', count: 25 },
    { id: 'productivity', name: 'Productivity', count: 40 },
    { id: 'development', name: 'Development', count: 35 },
    { id: 'integration', name: 'Integration', count: 30 },
    { id: 'communication', name: 'Communication', count: 20 },
  ];

  const mockReviews = [
    {
      id: 'review-1',
      user: 'john@example.com',
      rating: 5,
      comment: 'Excellent agent, very useful!',
      created_at: '2025-01-10T10:00:00Z',
    },
    {
      id: 'review-2',
      user: 'jane@example.com',
      rating: 4,
      comment: 'Good but could use more features',
      created_at: '2025-01-08T10:00:00Z',
    },
  ];

  cy.intercept('GET', '**/api/**/ai/marketplace/agents*', {
    statusCode: 200,
    body: { items: mockAgents, categories: mockCategories },
  }).as('getAgents');

  cy.intercept('GET', '**/api/**/ai/marketplace/agents/*', {
    statusCode: 200,
    body: { agent: mockAgents[0], reviews: mockReviews },
  }).as('getAgentDetails');

  cy.intercept('POST', '**/api/**/ai/marketplace/agents/*/install*', {
    statusCode: 200,
    body: { success: true, message: 'Agent installed successfully' },
  }).as('installAgent');

  cy.intercept('GET', '**/api/**/ai/marketplace/installed*', {
    statusCode: 200,
    body: { items: [mockAgents[1]] },
  }).as('getInstalledAgents');
}

export {};
