import React from 'react';
import { render, screen } from '@testing-library/react';
import { PipelineStatsCards } from '../components/PipelineStatsCards';
import type { PipelineStats } from '../types';

// Mock lucide-react icons used by component
jest.mock('lucide-react', () => ({
  Play: () => <span data-testid="icon-play" />,
  Clock: () => <span data-testid="icon-clock" />,
  TrendingUp: () => <span data-testid="icon-trending" />,
  Activity: () => <span data-testid="icon-activity" />,
}));

describe('PipelineStatsCards', () => {
  const mockStats: PipelineStats = {
    total_runs: 100,
    success_count: 85,
    failed_count: 10,
    cancelled_count: 5,
    success_rate: 89.47,
    avg_duration_seconds: 180,
    runs_today: 5,
    runs_this_week: 25,
    active_runs: 3,
  };

  it('renders all stat cards', () => {
    render(<PipelineStatsCards stats={mockStats} loading={false} />);

    expect(screen.getByText('Total Runs')).toBeInTheDocument();
    expect(screen.getByText('100')).toBeInTheDocument();
  });

  it('displays success rate when provided', () => {
    render(<PipelineStatsCards stats={mockStats} loading={false} />);

    expect(screen.getByText('Success Rate')).toBeInTheDocument();
    expect(screen.getByText('89.47%')).toBeInTheDocument();
  });

  it('displays active runs count', () => {
    render(<PipelineStatsCards stats={mockStats} loading={false} />);

    expect(screen.getByText('Active Runs')).toBeInTheDocument();
    expect(screen.getByText('3')).toBeInTheDocument();
  });

  it('displays average duration', () => {
    render(<PipelineStatsCards stats={mockStats} loading={false} />);

    expect(screen.getByText('Avg Duration')).toBeInTheDocument();
    // 180 seconds = 3m
    expect(screen.getByText('3m')).toBeInTheDocument();
  });

  it('shows loading spinner when loading', () => {
    render(<PipelineStatsCards stats={null} loading={true} />);

    // Should show loading state with text
    expect(screen.getByText('Loading stats...')).toBeInTheDocument();
  });

  it('handles null stats gracefully', () => {
    render(<PipelineStatsCards stats={null} loading={false} />);

    // Should display 0 or - for missing values
    expect(screen.getByText('Total Runs')).toBeInTheDocument();
    // Multiple cards will show 0 (Total Runs and Active Runs)
    const zeros = screen.getAllByText('0');
    expect(zeros.length).toBeGreaterThanOrEqual(1);
  });

  it('uses correct icons', () => {
    render(<PipelineStatsCards stats={mockStats} loading={false} />);

    expect(screen.getByTestId('icon-play')).toBeInTheDocument();
    expect(screen.getByTestId('icon-trending')).toBeInTheDocument();
    expect(screen.getByTestId('icon-clock')).toBeInTheDocument();
    expect(screen.getByTestId('icon-activity')).toBeInTheDocument();
  });
});
