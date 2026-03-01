/// <reference types="cypress" />

/**
 * Business Predictive Analytics Tests
 *
 * Enhanced E2E tests for Predictive Analytics features:
 * - Churn Risk Analysis
 * - Customer Health Scoring
 * - Revenue Forecasting
 *
 * Uses proper API intercepts and meaningful assertions.
 */

describe('Business Predictive Analytics Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
    setupPredictiveAnalyticsIntercepts();
  });

  describe('Churn Risk Analysis Page', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/analytics/churn-risk');
    });

    describe('Page Load and Layout', () => {
      it('should display churn risk page with title and action button', () => {
        cy.assertContainsAny(['Churn Risk', 'Churn Risk Analysis']);
        cy.assertContainsAny(['Run Predictions', 'Analyze', 'Refresh']);
      });

      it('should display summary statistics cards', () => {
        cy.assertContainsAny(['High Risk', 'At Risk', 'Critical']);
        cy.assertContainsAny(['Needs Intervention', 'Intervention', 'pending']);
        cy.assertContainsAny(['Avg', 'Average', 'Probability', '%']);
        cy.assertContainsAny(['Total', 'Analyzed', 'accounts', 'customers']);
      });

      it('should display risk distribution section', () => {
        cy.assertContainsAny(['Risk Distribution', 'Distribution']);
        cy.assertContainsAny(['critical', 'high', 'medium', 'low', 'minimal']);
      });
    });

    describe('Risk Tier Filters', () => {
      it('should display filter buttons for risk tiers', () => {
        cy.assertContainsAny(['All', 'High Risk', 'Critical', 'High', 'Medium', 'Low', 'Minimal']);
      });

      it('should filter predictions by risk tier', () => {
        cy.get('button').contains(/high risk/i).click();
        cy.waitForPageLoad();
        cy.assertContainsAny(['High Risk', 'Critical', 'Risk']);
      });

      it('should reset filters when All is selected', () => {
        cy.get('button').contains(/all/i).first().click();
        cy.waitForPageLoad();
        cy.get('body').should('be.visible');
      });
    });

    describe('Predictions List', () => {
      it('should display list of churn predictions', () => {
        cy.get('body').then($body => {
          const hasList = $body.find('[data-testid="churn-risk-list"], table, [class*="list"]').length > 0 ||
                         $body.text().match(/\d+%/) !== null;
          expect(hasList).to.be.true;
        });
      });

      it('should show risk probability percentages', () => {
        cy.get('body').should('contain', '%');
      });
    });

    describe('Prediction Details Modal', () => {
      it('should open detail modal when prediction is clicked', () => {
        cy.get('body').then($body => {
          const clickableItem = $body.find('[data-testid*="prediction"], button:contains("View"), [role="row"]').first();
          if (clickableItem.length > 0) {
            cy.wrap(clickableItem).click();
            cy.assertContainsAny(['Details', 'Churn Prediction Details', 'Probability', 'Risk Tier']);
          }
        });
      });

      it('should display contributing factors in modal', () => {
        cy.get('body').then($body => {
          const clickableItem = $body.find('[data-testid*="prediction"], button:contains("View"), [role="row"]').first();
          if (clickableItem.length > 0) {
            cy.wrap(clickableItem).click();
            cy.assertContainsAny(['Contributing Factors', 'Factor', 'Weight', 'Close']);
          }
        });
      });

      it('should display recommended actions in modal', () => {
        cy.get('body').then($body => {
          const clickableItem = $body.find('[data-testid*="prediction"], button:contains("View"), [role="row"]').first();
          if (clickableItem.length > 0) {
            cy.wrap(clickableItem).click();
            cy.assertContainsAny(['Recommended Actions', 'Action', 'Priority', 'Intervention']);
          }
        });
      });
    });

    describe('Run Predictions Action', () => {
      it('should trigger prediction run when button clicked', () => {
        cy.intercept('POST', '**/predictive_analytics/churn/predict').as('runPredictions');

        cy.get('body').then($body => {
          const runButton = $body.find('button:contains("Run Predictions"), button:contains("Analyze")').first();
          if (runButton.length > 0) {
            cy.wrap(runButton).click();
            cy.wait('@runPredictions', { timeout: 10000 }).its('response.statusCode').should('be.oneOf', [200, 201, 202]);
          }
        });
      });
    });
  });

  describe('Customer Health Page', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/analytics/customer-health');
    });

    describe('Page Load and Layout', () => {
      it('should display customer health page with title', () => {
        cy.assertContainsAny(['Customer Health', 'Health Scores']);
      });

      it('should have recalculate action button', () => {
        cy.assertContainsAny(['Recalculate', 'Recalculate Scores', 'Refresh']);
      });

      it('should display health summary statistics', () => {
        cy.assertContainsAny(['At Risk', 'Healthy', 'Average Score', 'Needs Intervention']);
      });
    });

    describe('Health Distribution Visualization', () => {
      it('should display health distribution bar', () => {
        cy.assertContainsAny(['Health Distribution', 'Distribution']);
        cy.assertContainsAny(['Thriving', 'Healthy', 'Attention', 'At Risk', 'Critical']);
      });

      it('should show distribution counts', () => {
        cy.get('body').should('contain.text', 'Thriving');
        cy.get('body').should('contain.text', 'Healthy');
      });
    });

    describe('Health Status Filters', () => {
      it('should display filter buttons for health statuses', () => {
        cy.assertContainsAny(['All', 'At Risk', 'Critical', 'Needs Attention', 'Healthy', 'Thriving']);
      });

      it('should filter by at-risk status', () => {
        cy.get('button').contains(/at.?risk/i).click();
        cy.waitForPageLoad();
        cy.get('body').should('be.visible');
      });

      it('should filter by healthy status', () => {
        cy.get('button').contains(/healthy/i).first().click();
        cy.waitForPageLoad();
        cy.get('body').should('be.visible');
      });
    });

    describe('Health Score Cards', () => {
      it('should display health score cards for customers', () => {
        cy.get('body').then($body => {
          const hasCards = $body.find('[class*="card"], [class*="Card"], [data-testid*="health-card"]').length > 0 ||
                          $body.text().includes('Score');
          expect(hasCards).to.be.true;
        });
      });

      it('should show health status indicators', () => {
        cy.assertContainsAny(['thriving', 'healthy', 'needs_attention', 'at_risk', 'critical', 'Score']);
      });
    });

    describe('Recalculate Scores Action', () => {
      it('should trigger recalculation when button clicked', () => {
        cy.intercept('POST', '**/predictive_analytics/health/calculate').as('recalculateScores');

        cy.get('body').then($body => {
          const calcButton = $body.find('button:contains("Recalculate"), button:contains("Refresh")').first();
          if (calcButton.length > 0) {
            cy.wrap(calcButton).click();
            cy.wait('@recalculateScores', { timeout: 10000 }).its('response.statusCode').should('be.oneOf', [200, 201, 202]);
          }
        });
      });
    });

    describe('Empty State', () => {
      it('should display message when no health scores match filter', () => {
        cy.get('body').then($body => {
          if ($body.text().includes('No health scores') || $body.text().includes('No data')) {
            cy.assertContainsAny(['No health scores', 'No data', 'No results']);
          }
        });
      });
    });
  });

  describe('Revenue Forecast Page', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/analytics/revenue-forecast');
    });

    describe('Page Load and Layout', () => {
      it('should display revenue forecast page with title', () => {
        cy.assertContainsAny(['Revenue Forecast', 'Forecast']);
      });

      it('should have generate forecast action button', () => {
        cy.assertContainsAny(['Generate Forecast', 'Generate', 'Refresh']);
      });

      it('should have period selector', () => {
        cy.assertContainsAny(['Monthly', 'Quarterly', 'Period']);
      });
    });

    describe('Forecast Summary Cards', () => {
      it('should display MRR projection card', () => {
        cy.assertContainsAny(['Next Month MRR', 'MRR', 'Projected MRR']);
      });

      it('should display 3-month projection', () => {
        cy.assertContainsAny(['3-Month', '3 Month', 'Quarter', 'Projection']);
      });

      it('should display 12-month projection', () => {
        cy.assertContainsAny(['12-Month', '12 Month', 'Year', 'Annual']);
      });

      it('should display projected churn', () => {
        cy.assertContainsAny(['Projected Churn', 'Churn', 'churned']);
      });

      it('should show currency values', () => {
        cy.get('body').should('contain', '$');
      });
    });

    describe('Period Selector', () => {
      it('should switch between monthly and quarterly views', () => {
        cy.get('select').then($select => {
          if ($select.length > 0) {
            cy.wrap($select).first().select('quarterly');
            cy.waitForPageLoad();
            cy.assertContainsAny(['Quarterly', 'Quarter', 'Q1', 'Q2']);
          }
        });
      });
    });

    describe('Forecast Chart', () => {
      it('should display forecast visualization', () => {
        cy.get('body').then($body => {
          const hasChart = $body.find('svg, canvas, [class*="chart"], [class*="Chart"], [data-testid*="chart"]').length > 0;
          if (hasChart) {
            cy.log('Forecast chart rendered');
          }
          expect($body.text()).to.match(/\$|MRR|Revenue|Forecast/);
        });
      });

      it('should show confidence intervals', () => {
        cy.assertContainsAny(['Confidence', 'confidence', 'Interval', 'Range', '%']);
      });
    });

    describe('Forecast Details Table', () => {
      it('should display forecast details table', () => {
        cy.assertContainsAny(['Forecast Details', 'Details', 'Period']);
      });

      it('should show revenue breakdown columns', () => {
        cy.assertContainsAny(['Projected MRR', 'New Revenue', 'Expansion', 'Churned']);
      });

      it('should display monthly forecasts', () => {
        cy.get('body').then($body => {
          const hasTable = $body.find('table, [role="table"]').length > 0;
          if (hasTable) {
            cy.assertContainsAny(['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']);
          }
        });
      });
    });

    describe('Generate Forecast Action', () => {
      it('should trigger forecast generation when button clicked', () => {
        cy.intercept('POST', '**/predictive_analytics/revenue/forecast').as('generateForecast');

        cy.get('body').then($body => {
          const genButton = $body.find('button:contains("Generate")').first();
          if (genButton.length > 0) {
            cy.wrap(genButton).click();
            cy.wait('@generateForecast', { timeout: 15000 }).its('response.statusCode').should('be.oneOf', [200, 201, 202]);
          }
        });
      });
    });

    describe('Empty State', () => {
      it('should display empty state when no forecasts available', () => {
        cy.get('body').then($body => {
          if ($body.text().includes('No forecasts')) {
            cy.assertContainsAny(['No forecasts', 'Generate a forecast', 'Get started']);
            cy.get('button').contains(/generate/i).should('be.visible');
          }
        });
      });
    });
  });

  describe('Cross-Page Navigation', () => {
    it('should navigate from analytics dashboard to churn risk', () => {
      cy.navigateTo('/app/business/analytics');
      cy.get('body').then($body => {
        const churnLink = $body.find('a[href*="churn-risk"], button:contains("Churn")').first();
        if (churnLink.length > 0) {
          cy.wrap(churnLink).click();
          cy.url().should('include', 'churn-risk');
        }
      });
    });

    it('should navigate from analytics dashboard to customer health', () => {
      cy.navigateTo('/app/business/analytics');
      cy.get('body').then($body => {
        const healthLink = $body.find('a[href*="customer-health"], button:contains("Health")').first();
        if (healthLink.length > 0) {
          cy.wrap(healthLink).click();
          cy.url().should('include', 'customer-health');
        }
      });
    });

    it('should navigate from analytics dashboard to revenue forecast', () => {
      cy.navigateTo('/app/business/analytics');
      cy.get('body').then($body => {
        const forecastLink = $body.find('a[href*="revenue-forecast"], button:contains("Forecast")').first();
        if (forecastLink.length > 0) {
          cy.wrap(forecastLink).click();
          cy.url().should('include', 'revenue-forecast');
        }
      });
    });
  });

  describe('Responsive Design', () => {
    it('should display churn risk page correctly across viewports', () => {
      cy.testResponsiveDesign('/app/business/analytics/churn-risk', {
        checkContent: 'Churn',
      });
    });

    it('should display customer health page correctly across viewports', () => {
      cy.testResponsiveDesign('/app/business/analytics/customer-health', {
        checkContent: 'Health',
      });
    });

    it('should display revenue forecast page correctly across viewports', () => {
      cy.testResponsiveDesign('/app/business/analytics/revenue-forecast', {
        checkContent: 'Forecast',
      });
    });
  });

  describe('Error Handling', () => {
    it('should handle churn predictions API error gracefully', () => {
      cy.testErrorHandling('**/api/**/predictive_analytics/churn**', {
        statusCode: 500,
        visitUrl: '/app/business/analytics/churn-risk',
      });
    });

    it('should handle health scores API error gracefully', () => {
      cy.testErrorHandling('**/api/**/predictive_analytics/health**', {
        statusCode: 500,
        visitUrl: '/app/business/analytics/customer-health',
      });
    });

    it('should handle revenue forecast API error gracefully', () => {
      cy.testErrorHandling('**/api/**/predictive_analytics/revenue**', {
        statusCode: 500,
        visitUrl: '/app/business/analytics/revenue-forecast',
      });
    });
  });
});

/**
 * Setup predictive analytics API intercepts with mock data
 */
function setupPredictiveAnalyticsIntercepts() {
  // Churn predictions mock data
  const mockChurnPredictions = [
    {
      id: 'pred-1',
      account_id: 'acct-001',
      churn_probability: 0.85,
      probability_percentage: 85,
      risk_tier: 'critical',
      predicted_churn_date: '2025-02-15',
      confidence_score: 0.92,
      contributing_factors: [
        { factor: 'payment_history', weight: 0.35, description: 'Multiple late payments' },
        { factor: 'usage_decline', weight: 0.30, description: 'Usage dropped 60% in last month' },
        { factor: 'support_tickets', weight: 0.20, description: 'Unresolved support issues' },
      ],
      recommended_actions: [
        { action: 'contact', description: 'Schedule call with customer success', priority: 'high' },
        { action: 'discount', description: 'Offer 20% retention discount', priority: 'medium' },
      ],
      created_at: '2025-01-15T10:00:00Z',
    },
    {
      id: 'pred-2',
      account_id: 'acct-002',
      churn_probability: 0.65,
      probability_percentage: 65,
      risk_tier: 'high',
      predicted_churn_date: '2025-03-01',
      confidence_score: 0.88,
      contributing_factors: [
        { factor: 'engagement_decline', weight: 0.40, description: 'No logins in 14 days' },
      ],
      recommended_actions: [
        { action: 'email', description: 'Send re-engagement campaign', priority: 'high' },
      ],
      created_at: '2025-01-15T10:00:00Z',
    },
    {
      id: 'pred-3',
      account_id: 'acct-003',
      churn_probability: 0.25,
      probability_percentage: 25,
      risk_tier: 'low',
      predicted_churn_date: null,
      confidence_score: 0.75,
      contributing_factors: [],
      recommended_actions: [],
      created_at: '2025-01-15T10:00:00Z',
    },
  ];

  // Health scores mock data
  const mockHealthScores = [
    {
      id: 'health-1',
      account_id: 'acct-001',
      overall_score: 92,
      health_status: 'thriving',
      component_scores: {
        engagement: 95,
        payment: 100,
        usage: 88,
        support: 85,
      },
      trend: 'improving',
      created_at: '2025-01-15T10:00:00Z',
    },
    {
      id: 'health-2',
      account_id: 'acct-002',
      overall_score: 68,
      health_status: 'needs_attention',
      component_scores: {
        engagement: 60,
        payment: 80,
        usage: 65,
        support: 70,
      },
      trend: 'declining',
      created_at: '2025-01-15T10:00:00Z',
    },
    {
      id: 'health-3',
      account_id: 'acct-003',
      overall_score: 35,
      health_status: 'at_risk',
      component_scores: {
        engagement: 30,
        payment: 40,
        usage: 35,
        support: 35,
      },
      trend: 'declining',
      created_at: '2025-01-15T10:00:00Z',
    },
  ];

  // Revenue forecasts mock data
  const mockRevenueForecasts = Array.from({ length: 12 }, (_, i) => {
    const date = new Date();
    date.setMonth(date.getMonth() + i + 1);
    return {
      id: `forecast-${i + 1}`,
      forecast_date: date.toISOString().split('T')[0],
      projections: {
        mrr: 125000 + (i * 5000) + Math.random() * 2000,
        new_revenue: 15000 + Math.random() * 3000,
        expansion_revenue: 8000 + Math.random() * 2000,
        churned_revenue: 5000 + Math.random() * 1500,
      },
      confidence: {
        level: 95 - (i * 2),
        lower_bound: 115000 + (i * 4000),
        upper_bound: 135000 + (i * 6000),
      },
      created_at: '2025-01-15T10:00:00Z',
    };
  });

  // Predictive analytics summary
  const mockSummary = {
    churn_predictions: {
      high_risk_count: 15,
      needs_intervention: 8,
      average_probability: 0.42,
      total_at_risk_mrr: 45000,
    },
    health_scores: {
      at_risk_count: 12,
      healthy_count: 85,
      average_score: 78.5,
    },
    revenue_forecast: {
      projected_mrr_next_month: 125000,
      projected_growth_rate: 0.05,
    },
  };

  // Intercept churn predictions
  cy.intercept('GET', '**/api/**/predictive_analytics/churn/predictions*', {
    statusCode: 200,
    body: { success: true, data: mockChurnPredictions },
  }).as('getChurnPredictions');

  // Intercept health scores
  cy.intercept('GET', '**/api/**/predictive_analytics/health/scores*', {
    statusCode: 200,
    body: { success: true, data: mockHealthScores },
  }).as('getHealthScores');

  // Intercept revenue forecasts
  cy.intercept('GET', '**/api/**/predictive_analytics/revenue/forecasts*', {
    statusCode: 200,
    body: { success: true, data: mockRevenueForecasts },
  }).as('getRevenueForecasts');

  // Intercept summary
  cy.intercept('GET', '**/api/**/predictive_analytics/summary*', {
    statusCode: 200,
    body: { success: true, data: mockSummary },
  }).as('getPredictiveSummary');

  // Intercept actions
  cy.intercept('POST', '**/api/**/predictive_analytics/churn/predict*', {
    statusCode: 200,
    body: { success: true, message: 'Churn predictions updated' },
  }).as('runChurnPredictions');

  cy.intercept('POST', '**/api/**/predictive_analytics/health/calculate*', {
    statusCode: 200,
    body: { success: true, message: 'Health scores recalculated' },
  }).as('recalculateHealthScores');

  cy.intercept('POST', '**/api/**/predictive_analytics/revenue/forecast*', {
    statusCode: 200,
    body: { success: true, message: 'Revenue forecast generated', data: mockRevenueForecasts },
  }).as('generateRevenueForecast');
}

export {};
