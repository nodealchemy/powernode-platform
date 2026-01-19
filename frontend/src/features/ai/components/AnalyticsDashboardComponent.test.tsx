import { render, screen, fireEvent, waitFor, act } from '@testing-library/react';
import { AnalyticsDashboardComponent } from './AnalyticsDashboardComponent';
import { analyticsApi } from '@/shared/services/ai';

// Mock analyticsApi
jest.mock('@/shared/services/ai', () => ({
  analyticsApi: {
    getDashboard: jest.fn(),
    getOverview: jest.fn(),
    getPerformance: jest.fn(),
    getCosts: jest.fn(),
    getUsage: jest.fn(),
    getInsights: jest.fn(),
    getRecommendations: jest.fn(),
    exportData: jest.fn()
  }
}));

// Mock useNotifications
const mockAddNotification = jest.fn();
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    addNotification: mockAddNotification
  })
}));

// Mock components
jest.mock('@/shared/components/layout/PageContainer', () => ({
  PageContainer: ({ children, title, description, actions }: any) => (
    <div data-testid="page-container" data-title={title}>
      <h1>{title}</h1>
      <p>{description}</p>
      {actions && (
        <div data-testid="actions">
          {actions.map((action: any) => (
            <button key={action.id} onClick={action.onClick} disabled={action.disabled}>
              {action.label}
            </button>
          ))}
        </div>
      )}
      {children}
    </div>
  )
}));

jest.mock('@/shared/components/ui/Card', () => ({
  Card: ({ children, className }: any) => (
    <div data-testid="card" className={className}>{children}</div>
  )
}));

jest.mock('@/shared/components/ui/Badge', () => ({
  Badge: ({ children, variant, size }: any) => (
    <span data-testid="badge" data-variant={variant} data-size={size}>{children}</span>
  )
}));

jest.mock('@/shared/components/ui/Select', () => ({
  Select: ({ value, onValueChange, options }: any) => (
    <select value={value} onChange={(e) => onValueChange(e.target.value)} data-testid="select">
      {options.map((opt: any) => (
        <option key={opt.value} value={opt.value}>{opt.label}</option>
      ))}
    </select>
  )
}));

jest.mock('@/shared/components/ui/LoadingSpinner', () => ({
  LoadingSpinner: ({ className }: any) => <div data-testid="loading-spinner" className={className}>Loading...</div>
}));

// Helper to wait for all async state updates to complete
const waitForLoadingComplete = async () => {
  await waitFor(() => {
    expect(screen.queryByTestId('loading-spinner')).not.toBeInTheDocument();
  });
  // Flush any remaining microtasks
  await act(async () => {
    await new Promise(resolve => setTimeout(resolve, 0));
  });
};

describe('AnalyticsDashboardComponent', () => {
  const mockDashboardData = {
    overview: {
      total_executions: 1000,
      successful_executions: 950,
      failed_executions: 50,
      total_cost_usd: 125.50
    },
    top_agents: [
      { id: 'agent-1', name: 'Support Agent', execution_count: 500, success_rate: 98.5 },
      { id: 'agent-2', name: 'Sales Agent', execution_count: 300, success_rate: 95.2 }
    ]
  };

  const mockOverviewData = {
    active_executions: 15,
    total_providers: 3,
    healthy_providers: 3,
    active_conversations: 8,
    provider_metrics: [
      { id: 'openai', name: 'OpenAI', health_status: 'healthy', success_rate: 99.2, avg_response_time: 450, total_requests: 800, cost_today: 85.00 },
      { id: 'anthropic', name: 'Anthropic', health_status: 'healthy', success_rate: 98.5, avg_response_time: 520, total_requests: 200, cost_today: 40.50 }
    ],
    agent_costs: { 'agent-1': 75.00, 'agent-2': 50.50 }
  };

  const mockPerformanceData = {
    error_rate: 0.05,
    throughput_per_hour: 150
  };

  const mockCostsData = {
    total_cost_usd: 125.50,
    cost_by_provider: { 'OpenAI': 85.00, 'Anthropic': 40.50 },
    optimization_potential_usd: 15.00,
    top_expensive_workflows: [
      { id: 'wf-1', name: 'Customer Support', total_cost_usd: 45.00 },
      { id: 'wf-2', name: 'Data Analysis', total_cost_usd: 30.00 }
    ]
  };

  const mockUsageData = {
    total_tokens_used: 250000
  };

  const mockInsightsData = [
    { title: 'High Error Rate', description: 'Error rate increased 15%', severity: 'warning', impact: 'Performance degradation' },
    { title: 'Cost Spike', description: 'Unusual cost increase detected', severity: 'critical', impact: 'Budget impact' }
  ];

  const mockRecommendationsData = [
    { id: 'rec-1', title: 'Cache Responses', description: 'Enable response caching', priority: 'high', potential_savings_usd: 10.00 },
    { id: 'rec-2', title: 'Optimize Prompts', description: 'Reduce token usage', priority: 'medium', potential_improvement_percentage: 15 }
  ];

  const setupMocks = () => {
    (analyticsApi.getDashboard as jest.Mock).mockResolvedValue(mockDashboardData);
    (analyticsApi.getOverview as jest.Mock).mockResolvedValue(mockOverviewData);
    (analyticsApi.getPerformance as jest.Mock).mockResolvedValue(mockPerformanceData);
    (analyticsApi.getCosts as jest.Mock).mockResolvedValue(mockCostsData);
    (analyticsApi.getUsage as jest.Mock).mockResolvedValue(mockUsageData);
    (analyticsApi.getInsights as jest.Mock).mockResolvedValue(mockInsightsData);
    (analyticsApi.getRecommendations as jest.Mock).mockResolvedValue(mockRecommendationsData);
  };

  beforeEach(() => {
    jest.clearAllMocks();
    setupMocks();
  });

  describe('loading state', () => {
    it('shows loading spinner initially', async () => {
      render(<AnalyticsDashboardComponent />);

      expect(screen.getByTestId('loading-spinner')).toBeInTheDocument();

      // Wait for all async operations to complete to avoid act() warnings
      await waitForLoadingComplete();
    });

    it('shows page title while loading', async () => {
      render(<AnalyticsDashboardComponent />);

      expect(screen.getByText('AI Analytics')).toBeInTheDocument();

      // Wait for all async operations to complete to avoid act() warnings
      await waitForLoadingComplete();
    });
  });

  describe('data display', () => {
    it('shows active executions count', async () => {
      render(<AnalyticsDashboardComponent />);

      await waitFor(() => {
        expect(screen.getByText('Active Executions')).toBeInTheDocument();
        expect(screen.getByText('15')).toBeInTheDocument();
      });
    });

    it('shows today executions count', async () => {
      render(<AnalyticsDashboardComponent />);

      await waitFor(() => {
        expect(screen.getByText("Today's Executions")).toBeInTheDocument();
        expect(screen.getByText('1000')).toBeInTheDocument();
      });
    });

    it('shows success rate', async () => {
      render(<AnalyticsDashboardComponent />);

      await waitFor(() => {
        expect(screen.getByText('Success Rate')).toBeInTheDocument();
        expect(screen.getByText('95%')).toBeInTheDocument();
      });
    });

    it('shows today cost', async () => {
      render(<AnalyticsDashboardComponent />);

      await waitFor(() => {
        expect(screen.getByText("Today's Cost")).toBeInTheDocument();
      });

      // Cost appears in multiple places, use getAllByText
      const costElements = screen.getAllByText('$125.50');
      expect(costElements.length).toBeGreaterThan(0);
    });
  });

  describe('provider performance', () => {
    it('shows Provider Performance section', async () => {
      render(<AnalyticsDashboardComponent />);

      await waitFor(() => {
        expect(screen.getByText('Provider Performance')).toBeInTheDocument();
      });
    });

    it('shows provider names', async () => {
      render(<AnalyticsDashboardComponent />);

      await waitFor(() => {
        expect(screen.getByText('Provider Performance')).toBeInTheDocument();
      });

      // Provider names may appear in multiple places (list + selector)
      expect(screen.getAllByText('OpenAI').length).toBeGreaterThan(0);
      expect(screen.getAllByText('Anthropic').length).toBeGreaterThan(0);
    });

    it('shows provider metrics', async () => {
      render(<AnalyticsDashboardComponent />);

      await waitFor(() => {
        expect(screen.getByText(/800 requests/)).toBeInTheDocument();
        expect(screen.getByText(/450ms avg/)).toBeInTheDocument();
      });
    });

    it('shows provider success rates', async () => {
      render(<AnalyticsDashboardComponent />);

      await waitFor(() => {
        expect(screen.getByText('Provider Performance')).toBeInTheDocument();
      });

      // Success rates are formatted with toFixed(1)
      expect(screen.getByText('99.2%')).toBeInTheDocument();
    });
  });

  describe('top agents', () => {
    it('shows Top Performing Agents section', async () => {
      render(<AnalyticsDashboardComponent />);

      await waitFor(() => {
        expect(screen.getByText('Top Performing Agents')).toBeInTheDocument();
      });
    });

    it('shows agent names', async () => {
      render(<AnalyticsDashboardComponent />);

      await waitFor(() => {
        expect(screen.getByText('Support Agent')).toBeInTheDocument();
        expect(screen.getByText('Sales Agent')).toBeInTheDocument();
      });
    });

    it('shows agent execution counts', async () => {
      render(<AnalyticsDashboardComponent />);

      await waitFor(() => {
        expect(screen.getByText('500 executions')).toBeInTheDocument();
        expect(screen.getByText('300 executions')).toBeInTheDocument();
      });
    });
  });

  describe('cost analytics', () => {
    it('shows Cost Analytics section', async () => {
      render(<AnalyticsDashboardComponent />);

      await waitFor(() => {
        expect(screen.getByText('Cost Analytics')).toBeInTheDocument();
      });
    });

    it('shows total cost', async () => {
      render(<AnalyticsDashboardComponent />);

      await waitFor(() => {
        expect(screen.getByText('Total Cost')).toBeInTheDocument();
        // Multiple $125.50 values exist (Today's Cost and Total Cost)
        const costValues = screen.getAllByText('$125.50');
        expect(costValues.length).toBeGreaterThan(0);
      });
    });

    it('shows optimization potential badge', async () => {
      render(<AnalyticsDashboardComponent />);

      await waitFor(() => {
        expect(screen.getByText(/\$15.00 savings potential/)).toBeInTheDocument();
      });
    });

    it('shows cost by provider', async () => {
      render(<AnalyticsDashboardComponent />);

      await waitFor(() => {
        expect(screen.getByText('Cost by Provider')).toBeInTheDocument();
      });
    });

    it('shows top expensive workflows', async () => {
      render(<AnalyticsDashboardComponent />);

      await waitFor(() => {
        expect(screen.getByText('Top Expensive Workflows')).toBeInTheDocument();
        expect(screen.getByText('Customer Support')).toBeInTheDocument();
      });
    });
  });

  describe('insights', () => {
    it('shows Insights section', async () => {
      render(<AnalyticsDashboardComponent />);

      await waitFor(() => {
        expect(screen.getByText('Insights')).toBeInTheDocument();
      });
    });

    it('shows insight titles', async () => {
      render(<AnalyticsDashboardComponent />);

      await waitFor(() => {
        expect(screen.getByText('High Error Rate')).toBeInTheDocument();
        expect(screen.getByText('Cost Spike')).toBeInTheDocument();
      });
    });

    it('shows insight descriptions', async () => {
      render(<AnalyticsDashboardComponent />);

      await waitFor(() => {
        expect(screen.getByText('Error rate increased 15%')).toBeInTheDocument();
      });
    });

    it('shows insight impact', async () => {
      render(<AnalyticsDashboardComponent />);

      await waitFor(() => {
        expect(screen.getByText('Impact: Performance degradation')).toBeInTheDocument();
      });
    });
  });

  describe('recommendations', () => {
    it('shows Recommendations section', async () => {
      render(<AnalyticsDashboardComponent />);

      await waitFor(() => {
        expect(screen.getByText('Recommendations')).toBeInTheDocument();
      });
    });

    it('shows recommendation titles', async () => {
      render(<AnalyticsDashboardComponent />);

      await waitFor(() => {
        expect(screen.getByText('Cache Responses')).toBeInTheDocument();
        expect(screen.getByText('Optimize Prompts')).toBeInTheDocument();
      });
    });

    it('shows recommendation priorities', async () => {
      render(<AnalyticsDashboardComponent />);

      await waitFor(() => {
        expect(screen.getByText('high')).toBeInTheDocument();
        expect(screen.getByText('medium')).toBeInTheDocument();
      });
    });

    it('shows potential savings', async () => {
      render(<AnalyticsDashboardComponent />);

      await waitFor(() => {
        expect(screen.getByText(/Save \$10.00/)).toBeInTheDocument();
      });
    });

    it('shows potential improvement', async () => {
      render(<AnalyticsDashboardComponent />);

      await waitFor(() => {
        expect(screen.getByText(/\+15% improvement/)).toBeInTheDocument();
      });
    });
  });

  describe('health status', () => {
    it('shows Healthy badge for low error rate', async () => {
      render(<AnalyticsDashboardComponent />);

      await waitForLoadingComplete();

      expect(screen.getByText('Provider Performance')).toBeInTheDocument();

      // Check for badge with success variant for healthy status
      const badges = screen.getAllByTestId('badge');
      const healthyBadge = badges.find(b => b.getAttribute('data-variant') === 'success');
      expect(healthyBadge).toBeInTheDocument();
    });

    it('shows Degraded badge for medium error rate', async () => {
      (analyticsApi.getPerformance as jest.Mock).mockResolvedValue({
        ...mockPerformanceData,
        error_rate: 0.10 // 10% - triggers degraded
      });

      render(<AnalyticsDashboardComponent />);

      await waitForLoadingComplete();

      expect(screen.getByText('Provider Performance')).toBeInTheDocument();

      // Check for badge with warning variant for degraded status
      const badges = screen.getAllByTestId('badge');
      const degradedBadge = badges.find(b => b.getAttribute('data-variant') === 'warning');
      expect(degradedBadge).toBeInTheDocument();
    });

    it('shows Unhealthy badge for high error rate', async () => {
      (analyticsApi.getPerformance as jest.Mock).mockResolvedValue({
        ...mockPerformanceData,
        error_rate: 0.20 // 20% - triggers unhealthy
      });

      render(<AnalyticsDashboardComponent />);

      await waitForLoadingComplete();

      expect(screen.getByText('Provider Performance')).toBeInTheDocument();

      // Check for badge with danger variant for unhealthy status
      const badges = screen.getAllByTestId('badge');
      const unhealthyBadge = badges.find(b => b.getAttribute('data-variant') === 'danger');
      expect(unhealthyBadge).toBeInTheDocument();
    });
  });

  describe('actions', () => {
    it('shows Refresh button', async () => {
      render(<AnalyticsDashboardComponent />);

      await waitFor(() => {
        expect(screen.getByText('Refresh')).toBeInTheDocument();
      });
    });

    it('shows Export button', async () => {
      render(<AnalyticsDashboardComponent />);

      await waitFor(() => {
        expect(screen.getByText('Export')).toBeInTheDocument();
      });
    });

    it('shows Real-time button', async () => {
      render(<AnalyticsDashboardComponent />);

      await waitFor(() => {
        expect(screen.getByText('Real-time')).toBeInTheDocument();
      });
    });

    it('calls refresh when Refresh clicked', async () => {
      render(<AnalyticsDashboardComponent />);

      await waitFor(() => {
        expect(screen.getByText('Refresh')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Refresh'));

      // Should call API again
      expect(analyticsApi.getDashboard).toHaveBeenCalledTimes(2);
    });

    it('shows notification when export clicked', async () => {
      (analyticsApi.exportData as jest.Mock).mockResolvedValue({
        download_url: 'https://example.com/export.csv'
      });

      // Mock window.open
      const originalOpen = window.open;
      window.open = jest.fn();

      render(<AnalyticsDashboardComponent />);

      await waitFor(() => {
        expect(screen.getByText('Export')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Export'));

      await waitFor(() => {
        expect(mockAddNotification).toHaveBeenCalledWith(
          expect.objectContaining({
            type: 'info',
            title: 'Exporting Data'
          })
        );
      });

      window.open = originalOpen;
    });
  });

  describe('filters', () => {
    it('shows time range selector', async () => {
      render(<AnalyticsDashboardComponent />);

      await waitFor(() => {
        const selects = screen.getAllByTestId('select');
        expect(selects.length).toBeGreaterThan(0);
      });
    });

    it('shows provider selector', async () => {
      render(<AnalyticsDashboardComponent />);

      await waitFor(() => {
        const selects = screen.getAllByTestId('select');
        expect(selects.length).toBe(2);
      });
    });
  });

  describe('error handling', () => {
    it('shows error state when API fails', async () => {
      (analyticsApi.getDashboard as jest.Mock).mockRejectedValue(new Error('API error'));

      render(<AnalyticsDashboardComponent />);

      await waitFor(() => {
        expect(screen.getByText('No Data Available')).toBeInTheDocument();
      });
    });

    it('shows error notification on API failure', async () => {
      (analyticsApi.getDashboard as jest.Mock).mockRejectedValue(new Error('API error'));

      render(<AnalyticsDashboardComponent />);

      await waitFor(() => {
        expect(mockAddNotification).toHaveBeenCalledWith(
          expect.objectContaining({
            type: 'error',
            title: 'Analytics Error'
          })
        );
      });
    });
  });

  describe('no insights/recommendations', () => {
    it('hides Insights section when empty', async () => {
      (analyticsApi.getInsights as jest.Mock).mockResolvedValue([]);

      render(<AnalyticsDashboardComponent />);

      await waitForLoadingComplete();

      expect(screen.getByText('Provider Performance')).toBeInTheDocument();
      expect(screen.queryByText('Insights')).not.toBeInTheDocument();
    });

    it('hides Recommendations section when empty', async () => {
      (analyticsApi.getRecommendations as jest.Mock).mockResolvedValue([]);

      render(<AnalyticsDashboardComponent />);

      await waitForLoadingComplete();

      expect(screen.getByText('Provider Performance')).toBeInTheDocument();
      expect(screen.queryByText('Recommendations')).not.toBeInTheDocument();
    });
  });
});
