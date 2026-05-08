import { render, screen } from '@testing-library/react';
import { CostBreakdown } from './CostBreakdown';
import type { CostEstimate } from './types';

const baseEstimate: CostEstimate = {
  monthly_usd: 425.5,
  one_time_usd: 75,
  confidence: 'high',
  by_resource: [
    { resource_type: 'compute.vm', name: 'web', monthly_usd: 200, count: 2 },
    { resource_type: 'volume.ssd', name: 'data', monthly_usd: 75, count: 1 },
    { resource_type: 'cache.redis', name: 'cache', monthly_usd: 50.5, count: 1 },
    { resource_type: 'network.gateway', name: 'gw', monthly_usd: 100, count: 1 }
  ],
  last_priced_at: '2026-05-07T12:00:00Z'
};

describe('CostBreakdown', () => {
  it('renders category buckets aggregated from by_resource', () => {
    render(<CostBreakdown estimate={baseEstimate} />);
    expect(screen.getByTestId('cost-breakdown')).toBeInTheDocument();
    expect(screen.getByTestId('cost-category-compute')).toHaveTextContent('Compute');
    expect(screen.getByTestId('cost-category-compute')).toHaveTextContent('$200/mo');
    expect(screen.getByTestId('cost-category-storage')).toHaveTextContent('$75/mo');
    expect(screen.getByTestId('cost-category-cache')).toHaveTextContent('$50.5/mo');
    expect(screen.getByTestId('cost-category-network')).toHaveTextContent('$100/mo');
  });

  it('shows compute instance count next to the Compute label', () => {
    render(<CostBreakdown estimate={baseEstimate} />);
    expect(screen.getByTestId('cost-category-compute')).toHaveTextContent('2 instances');
  });

  it('renders monthly + one-time totals', () => {
    render(<CostBreakdown estimate={baseEstimate} />);
    expect(screen.getByTestId('cost-total-monthly')).toHaveTextContent('$425.5/mo');
    expect(screen.getByTestId('cost-total-onetime')).toHaveTextContent('$75');
  });

  it('renders the confidence pill with the matching label and pricing-sync title', () => {
    render(<CostBreakdown estimate={baseEstimate} />);
    const pill = screen.getByTestId('cost-confidence-pill');
    expect(pill).toHaveTextContent('High confidence');
    expect(pill).toHaveAttribute('title', expect.stringContaining('Last priced:'));
  });

  it('falls back to a placeholder pricing-sync hint when last_priced_at is missing', () => {
    render(
      <CostBreakdown
        estimate={{ ...baseEstimate, last_priced_at: null }}
      />
    );
    expect(screen.getByTestId('cost-confidence-pill')).toHaveAttribute(
      'title',
      'Pricing sync timestamp unavailable'
    );
  });

  it('switches to Medium / Low labels for med + low confidence', () => {
    const { rerender } = render(
      <CostBreakdown estimate={{ ...baseEstimate, confidence: 'med' }} />
    );
    expect(screen.getByTestId('cost-confidence-pill')).toHaveTextContent('Medium confidence');

    rerender(<CostBreakdown estimate={{ ...baseEstimate, confidence: 'low' }} />);
    expect(screen.getByTestId('cost-confidence-pill')).toHaveTextContent('Low confidence');
  });

  it('renders the previous estimate column when previousEstimate is provided', () => {
    const previous: CostEstimate = {
      ...baseEstimate,
      monthly_usd: 600,
      one_time_usd: 50,
      by_resource: []
    };
    render(<CostBreakdown estimate={baseEstimate} previousEstimate={previous} />);
    expect(screen.getByTestId('cost-previous')).toHaveTextContent('$600/mo');
    expect(screen.getByTestId('cost-current')).toHaveTextContent('After');
    expect(screen.getByTestId('cost-delta')).toHaveTextContent('savings');
  });

  it('surfaces the increase delta when the new plan costs more', () => {
    const previous: CostEstimate = { ...baseEstimate, monthly_usd: 100, by_resource: [] };
    render(<CostBreakdown estimate={baseEstimate} previousEstimate={previous} />);
    expect(screen.getByTestId('cost-delta')).toHaveTextContent('increase');
  });

  it('shows an empty-state row when by_resource is empty', () => {
    render(
      <CostBreakdown estimate={{ ...baseEstimate, by_resource: [] }} />
    );
    expect(screen.getByText('No itemized breakdown.')).toBeInTheDocument();
  });
});
