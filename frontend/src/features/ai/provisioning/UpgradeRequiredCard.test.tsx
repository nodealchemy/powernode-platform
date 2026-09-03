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

  // The backend contract always SENDS cap / upgrade_url, null when unknown.
  // A default parameter does not fire on null, so this is the shape that
  // silently produced an <a> with no href.
  it('falls back to /checkout when the backend sends an explicit null upgrade_url', () => {
    render(<UpgradeRequiredCard reason="no_subscription" upgradeUrl={null} cap={null} />);

    expect(screen.getByTestId('upgrade-required-cta')).toHaveAttribute('href', '/checkout');
  });

  // The cost-cap copy formats spent/cap as currency. The denial contract sends
  // those keys as explicit null when unknown, so the formatter must not be
  // handed a null it cannot format.
  it('renders the cost-cap variant without crashing when spent and cap are null', () => {
    render(<UpgradeRequiredCard reason="llm_cost_cap_exceeded" spent={null} cap={null} />);

    const card = screen.getByTestId('upgrade-required-card');
    expect(card.textContent).toContain('$0.00');
  });

  describe('quota_check_unavailable (BillingBridge failed CLOSED)', () => {
    it('says the check failed rather than claiming a plan limit was hit', () => {
      render(<UpgradeRequiredCard reason="quota_check_unavailable" />);

      expect(screen.getByText(/couldn't check your plan limits/i)).toBeInTheDocument();
      expect(screen.queryByText(/plan's limit/i)).not.toBeInTheDocument();
    });

    it('renders no upgrade CTA — buying a plan cannot fix an unreachable billing check', () => {
      render(<UpgradeRequiredCard reason="quota_check_unavailable" />);

      expect(screen.queryByTestId('upgrade-required-cta')).not.toBeInTheDocument();
    });

    it('still renders the CTA for real plan-limit reasons', () => {
      render(<UpgradeRequiredCard reason="max_active_instances_exceeded" />);

      expect(screen.getByTestId('upgrade-required-cta')).toBeInTheDocument();
    });
  });
});
