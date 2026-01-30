import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import { ProviderHealthDashboard } from './ProviderHealthDashboard';
import { ProviderMetrics } from '@/shared/types/monitoring';

// Mock provider data
const mockProviders: ProviderMetrics[] = [
  {
    id: 'provider-1',
    name: 'OpenAI',
    slug: 'openai',
    status: 'healthy',
    health_score: 98.5,
    circuit_breaker: {
      state: 'closed',
      failure_count: 0,
      success_threshold: 5,
      timeout: 60,
      last_failure: null,
      stats: {
        total_requests: 1000,
        successful_requests: 995,
        failed_requests: 5,
        avg_response_time: 250,
      },
    },
    load_balancing: {
      current_load: 45,
      weight: 1.0,
      utilization: 0.45,
    },
    performance: {
      success_rate: 99.5,
      avg_response_time: 250,
      throughput: 10.5,
      error_rate: 0.5,
    },
    usage: {
      executions_count: 1000,
      tokens_consumed: 500000,
      cost: 25.50,
    },
    alerts: [],
    credentials: [
      {
        id: 'cred-1',
        name: 'Production API Key',
        is_active: true,
        last_tested: '2026-01-30T10:00:00Z',
        status: 'valid',
      },
    ],
    last_execution: '2026-01-30T10:00:00Z',
  },
  {
    id: 'provider-2',
    name: 'Anthropic',
    slug: 'anthropic',
    status: 'degraded',
    health_score: 75.0,
    circuit_breaker: {
      state: 'half_open',
      failure_count: 3,
      success_threshold: 5,
      timeout: 60,
      last_failure: '2026-01-30T09:55:00Z',
      stats: {
        total_requests: 500,
        successful_requests: 450,
        failed_requests: 50,
        avg_response_time: 500,
      },
    },
    load_balancing: {
      current_load: 30,
      weight: 0.8,
      utilization: 0.30,
    },
    performance: {
      success_rate: 90.0,
      avg_response_time: 500,
      throughput: 5.2,
      error_rate: 10.0,
    },
    usage: {
      executions_count: 500,
      tokens_consumed: 200000,
      cost: 15.25,
    },
    alerts: [
      {
        id: 'alert-1',
        severity: 'high',
        component: 'provider',
        title: 'High Error Rate',
        message: 'Error rate exceeded 5% threshold',
        metadata: {},
        acknowledged: false,
        acknowledged_at: null,
        acknowledged_by: null,
        resolved: false,
        resolved_at: null,
        resolved_by: null,
        created_at: '2026-01-30T09:50:00Z',
      },
    ],
    credentials: [
      {
        id: 'cred-2',
        name: 'Production API Key',
        is_active: true,
        last_tested: '2026-01-30T09:00:00Z',
        status: 'valid',
      },
    ],
    last_execution: '2026-01-30T09:55:00Z',
  },
];

describe('ProviderHealthDashboard', () => {
  const defaultProps = {
    providers: mockProviders,
    isLoading: false,
    timeRange: '24h',
    onRefresh: jest.fn(),
  };

  it('renders dashboard title', () => {
    render(<ProviderHealthDashboard {...defaultProps} />);

    expect(screen.getByText('Provider Health Dashboard')).toBeInTheDocument();
  });

  it('displays aggregate statistics', () => {
    render(<ProviderHealthDashboard {...defaultProps} />);

    // Average health score
    expect(screen.getByText('86.8%')).toBeInTheDocument(); // (98.5 + 75) / 2

    // Total executions
    expect(screen.getByText('1,500')).toBeInTheDocument(); // 1000 + 500

    // Total cost
    expect(screen.getByText('$40.75')).toBeInTheDocument(); // 25.50 + 15.25
  });

  it('shows status overview counts', () => {
    render(<ProviderHealthDashboard {...defaultProps} />);

    // Healthy count
    expect(screen.getByText(/Healthy/)).toBeInTheDocument();

    // Degraded count
    expect(screen.getByText(/Degraded/)).toBeInTheDocument();
  });

  it('renders all provider cards', () => {
    render(<ProviderHealthDashboard {...defaultProps} />);

    expect(screen.getByText('OpenAI')).toBeInTheDocument();
    expect(screen.getByText('Anthropic')).toBeInTheDocument();
  });

  it('shows provider health scores', () => {
    render(<ProviderHealthDashboard {...defaultProps} />);

    // OpenAI health score
    expect(screen.getByText('98.5%')).toBeInTheDocument();

    // Anthropic health score
    expect(screen.getByText('75.0%')).toBeInTheDocument();
  });

  it('displays circuit breaker states', () => {
    render(<ProviderHealthDashboard {...defaultProps} />);

    expect(screen.getByText('closed')).toBeInTheDocument();
    expect(screen.getByText('half open')).toBeInTheDocument();
  });

  it('shows active alerts indicator', () => {
    render(<ProviderHealthDashboard {...defaultProps} />);

    expect(screen.getByText(/1 active alert/)).toBeInTheDocument();
  });

  it('calls onRefresh when refresh button clicked', () => {
    const onRefresh = jest.fn();
    render(<ProviderHealthDashboard {...defaultProps} onRefresh={onRefresh} />);

    fireEvent.click(screen.getByRole('button', { name: /Refresh/i }));

    expect(onRefresh).toHaveBeenCalled();
  });

  it('calls onTestProvider when test button clicked', () => {
    const onTestProvider = jest.fn();
    render(<ProviderHealthDashboard {...defaultProps} onTestProvider={onTestProvider} />);

    const testButtons = screen.getAllByRole('button', { name: /Test/i });
    fireEvent.click(testButtons[0]);

    expect(onTestProvider).toHaveBeenCalledWith('provider-1', {});
  });

  it('shows provider details when card is clicked', () => {
    render(<ProviderHealthDashboard {...defaultProps} />);

    // Click on OpenAI card
    const openaiCard = screen.getByText('OpenAI').closest('[class*="cursor-pointer"]');
    fireEvent.click(openaiCard!);

    // Details panel should appear
    expect(screen.getByText('OpenAI - Detailed Metrics')).toBeInTheDocument();
  });

  it('shows performance tab by default in details', () => {
    render(<ProviderHealthDashboard {...defaultProps} />);

    // Click on provider card
    const card = screen.getByText('OpenAI').closest('[class*="cursor-pointer"]');
    fireEvent.click(card!);

    // Performance metrics should be visible - use getAllByText since there may be multiple
    expect(screen.getAllByText(/Success Rate/i).length).toBeGreaterThanOrEqual(1);
  });

  it('switches to circuit breaker tab', () => {
    render(<ProviderHealthDashboard {...defaultProps} />);

    // Click on provider card
    const card = screen.getByText('Anthropic').closest('[class*="cursor-pointer"]');
    fireEvent.click(card!);

    // Switch to circuit breaker tab using button
    const circuitBreakerBtn = screen.getByRole('button', { name: /Circuit Breaker/i });
    fireEvent.click(circuitBreakerBtn);

    // Circuit breaker details should be visible
    expect(screen.getByText(/Failure Count/i)).toBeInTheDocument();
  });

  it('shows alerts in alerts tab', () => {
    render(<ProviderHealthDashboard {...defaultProps} />);

    // Click on Anthropic card (has alerts)
    const card = screen.getByText('Anthropic').closest('[class*="cursor-pointer"]');
    fireEvent.click(card!);

    // Switch to alerts tab using button
    const alertsBtn = screen.getByRole('button', { name: /Alerts/i });
    fireEvent.click(alertsBtn);

    // Alert should be visible
    expect(screen.getByText('High Error Rate')).toBeInTheDocument();
    expect(screen.getByText(/Error rate exceeded 5% threshold/)).toBeInTheDocument();
  });

  it('closes details panel when close button clicked', () => {
    render(<ProviderHealthDashboard {...defaultProps} />);

    // Open details
    const card = screen.getByText('OpenAI').closest('[class*="cursor-pointer"]');
    fireEvent.click(card!);

    expect(screen.getByText('OpenAI - Detailed Metrics')).toBeInTheDocument();

    // Close details
    fireEvent.click(screen.getByRole('button', { name: /Close/i }));

    expect(screen.queryByText('OpenAI - Detailed Metrics')).not.toBeInTheDocument();
  });

  describe('loading state', () => {
    it('shows loading indicator when loading and no data', () => {
      render(<ProviderHealthDashboard {...defaultProps} providers={[]} isLoading={true} />);

      expect(screen.getByText(/Loading provider health data/i)).toBeInTheDocument();
    });

    it('disables refresh button while loading', () => {
      render(<ProviderHealthDashboard {...defaultProps} isLoading={true} />);

      const refreshButton = screen.getByRole('button', { name: /Refresh/i });
      expect(refreshButton).toBeDisabled();
    });
  });

  describe('empty state', () => {
    it('shows empty state when no providers', () => {
      render(<ProviderHealthDashboard {...defaultProps} providers={[]} isLoading={false} />);

      expect(screen.getByText(/No Providers Found/i)).toBeInTheDocument();
    });
  });

  describe('time range display', () => {
    it('shows current time range', () => {
      render(<ProviderHealthDashboard {...defaultProps} timeRange="7d" />);

      expect(screen.getByText('7d')).toBeInTheDocument();
    });
  });
});
