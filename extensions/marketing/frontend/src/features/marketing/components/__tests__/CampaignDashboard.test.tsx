import { render, screen } from '@testing-library/react';
import { BrowserRouter } from 'react-router-dom';
import { CampaignDashboard } from '../CampaignDashboard';

// Mock the hooks
jest.mock('../../hooks/useCampaigns', () => ({
  useCampaigns: () => ({
    campaigns: [
      {
        id: '1',
        name: 'Test Campaign',
        description: 'A test campaign',
        campaign_type: 'email',
        status: 'active',
        channels: ['email'],
        scheduled_at: null,
        started_at: '2026-01-01T00:00:00Z',
        completed_at: null,
        budget_cents: 100000,
        spent_cents: 50000,
        target_audience: 'All users',
        tags: ['test'],
        created_by_id: 'u1',
        created_by_name: 'Test User',
        contents_count: 2,
        metrics_summary: {
          impressions: 5000,
          clicks: 250,
          conversions: 25,
          click_rate: 5.0,
          conversion_rate: 0.5,
          revenue_cents: 250000,
        },
        created_at: '2026-01-01T00:00:00Z',
        updated_at: '2026-01-01T00:00:00Z',
      },
    ],
    pagination: { current_page: 1, per_page: 20, total_pages: 1, total_count: 1 },
    loading: false,
    error: null,
    refresh: jest.fn(),
  }),
}));

jest.mock('../../services/campaignsApi', () => ({
  campaignsApi: {
    execute: jest.fn(),
    pause: jest.fn(),
    resume: jest.fn(),
    archive: jest.fn(),
    clone: jest.fn(),
    delete: jest.fn(),
  },
}));

jest.mock('../../../../shared/utils/logger', () => ({
  logger: { error: jest.fn(), info: jest.fn(), warn: jest.fn(), debug: jest.fn() },
}));

jest.mock('../../../../shared/components/ui/LoadingSpinner', () => ({
  LoadingSpinner: () => <div data-testid="loading-spinner">Loading...</div>,
}));

describe('CampaignDashboard', () => {
  it('renders campaign list without crashing', () => {
    render(
      <BrowserRouter>
        <CampaignDashboard />
      </BrowserRouter>
    );
    expect(screen.getByText('Test Campaign')).toBeInTheDocument();
  });

  it('displays campaign status badge', () => {
    render(
      <BrowserRouter>
        <CampaignDashboard />
      </BrowserRouter>
    );
    expect(screen.getByTestId('status-badge-active')).toBeInTheDocument();
  });

  it('shows stat cards', () => {
    render(
      <BrowserRouter>
        <CampaignDashboard />
      </BrowserRouter>
    );
    expect(screen.getByText('Total Campaigns')).toBeInTheDocument();
    expect(screen.getByText('Total Clicks')).toBeInTheDocument();
    expect(screen.getByText('Total Conversions')).toBeInTheDocument();
  });

  it('shows search and filter controls', () => {
    render(
      <BrowserRouter>
        <CampaignDashboard />
      </BrowserRouter>
    );
    expect(screen.getByPlaceholderText('Search campaigns...')).toBeInTheDocument();
  });
});
