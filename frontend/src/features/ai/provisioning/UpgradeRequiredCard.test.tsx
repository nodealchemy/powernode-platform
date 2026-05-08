import { render, screen } from '@testing-library/react';
import { UpgradeRequiredCard } from './UpgradeRequiredCard';

describe('UpgradeRequiredCard', () => {
  it('renders the instance-cap variant with the dedicated heading', () => {
    render(<UpgradeRequiredCard reason="max_active_instances_exceeded" />);

    const card = screen.getByTestId('upgrade-required-card');
    expect(card).toBeInTheDocument();
    expect(card).toHaveAttribute('data-reason', 'max_active_instances_exceeded');
    expect(screen.getByText(/instance cap/i)).toBeInTheDocument();
  });

  it('renders the free-hours-exhausted variant', () => {
    render(<UpgradeRequiredCard reason="free_hours_exhausted" />);

    expect(screen.getByText(/out of free runtime/i)).toBeInTheDocument();
  });

  it('renders the no-subscription variant', () => {
    render(<UpgradeRequiredCard reason="no_subscription" />);

    expect(screen.getByText(/add a plan/i)).toBeInTheDocument();
  });

  it('renders the LLM cost-cap variant with formatted spent / cap values', () => {
    render(<UpgradeRequiredCard reason="llm_cost_cap_exceeded" spent={0.42} cap={0.5} />);

    expect(screen.getByText(/today's AI spend cap/i)).toBeInTheDocument();
    // Numbers are split across spans, so we have to scan the card text content.
    const card = screen.getByTestId('upgrade-required-card');
    expect(card.textContent).toContain('$0.42');
    expect(card.textContent).toContain('$0.50');
  });

  it('falls back to a generic message for unknown reasons', () => {
    render(<UpgradeRequiredCard reason="some_future_reason" />);

    expect(screen.getByText(/plan's limit/i)).toBeInTheDocument();
  });

  it("links the CTA to /checkout by default and accepts an override", () => {
    const { rerender } = render(<UpgradeRequiredCard reason="no_subscription" />);
    const cta = screen.getByTestId('upgrade-required-cta');
    expect(cta).toHaveAttribute('href', '/checkout');

    rerender(<UpgradeRequiredCard reason="no_subscription" upgradeUrl="/billing/plans" />);
    expect(screen.getByTestId('upgrade-required-cta')).toHaveAttribute('href', '/billing/plans');
  });
});
