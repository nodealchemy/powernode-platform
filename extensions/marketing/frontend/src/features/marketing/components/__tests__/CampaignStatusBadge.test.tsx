import { render, screen } from '@testing-library/react';
import { CampaignStatusBadge } from '../CampaignStatusBadge';

describe('CampaignStatusBadge', () => {
  it('renders draft status', () => {
    render(<CampaignStatusBadge status="draft" />);
    expect(screen.getByText('Draft')).toBeInTheDocument();
    expect(screen.getByTestId('status-badge-draft')).toBeInTheDocument();
  });

  it('renders active status', () => {
    render(<CampaignStatusBadge status="active" />);
    expect(screen.getByText('Active')).toBeInTheDocument();
    expect(screen.getByTestId('status-badge-active')).toBeInTheDocument();
  });

  it('renders paused status', () => {
    render(<CampaignStatusBadge status="paused" />);
    expect(screen.getByText('Paused')).toBeInTheDocument();
    expect(screen.getByTestId('status-badge-paused')).toBeInTheDocument();
  });

  it('renders completed status', () => {
    render(<CampaignStatusBadge status="completed" />);
    expect(screen.getByText('Completed')).toBeInTheDocument();
    expect(screen.getByTestId('status-badge-completed')).toBeInTheDocument();
  });

  it('renders scheduled status', () => {
    render(<CampaignStatusBadge status="scheduled" />);
    expect(screen.getByText('Scheduled')).toBeInTheDocument();
    expect(screen.getByTestId('status-badge-scheduled')).toBeInTheDocument();
  });

  it('renders archived status', () => {
    render(<CampaignStatusBadge status="archived" />);
    expect(screen.getByText('Archived')).toBeInTheDocument();
    expect(screen.getByTestId('status-badge-archived')).toBeInTheDocument();
  });

  it('applies custom className', () => {
    render(<CampaignStatusBadge status="active" className="mt-4" />);
    const badge = screen.getByTestId('status-badge-active');
    expect(badge.className).toContain('mt-4');
  });
});
