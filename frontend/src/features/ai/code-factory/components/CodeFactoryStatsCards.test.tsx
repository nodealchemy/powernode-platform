import { screen, within } from '@testing-library/react';
import { renderWithProviders } from '@/test-utils';
import type { HarnessGapMetrics } from '../types/codeFactory';
import { CodeFactoryStatsCards } from './CodeFactoryStatsCards';

// M1 tail: with no gap metrics there is no SLA measurement, and the card used
// to read `?? 100` — 100% compliance for a factory that reported nothing.

const metrics = (sla_compliance_rate: number): HarnessGapMetrics => ({
  total: 1,
  open: 1,
  in_progress: 0,
  closed: 0,
  sla_compliance_rate,
  by_severity: {},
});

const renderCards = (gapMetrics: HarnessGapMetrics | null) =>
  renderWithProviders(
    <CodeFactoryStatsCards contracts={[]} reviewStates={[]} harnessGaps={[]} gapMetrics={gapMetrics} slaCompliance={null} />
  );
const slaCard = () => screen.getByText('SLA Compliance').parentElement as HTMLElement;

describe('CodeFactoryStatsCards — SLA compliance', () => {
  it('no gap metrics reads "—", never 100%, and carries no alarm border', () => {
    renderCards(null);

    expect(within(slaCard()).getByText('—')).toBeInTheDocument();
    expect(within(slaCard()).queryByText(/%/)).not.toBeInTheDocument();
    expect(slaCard().className).not.toContain('border-theme-error-border');
  });

  it('a real 0% reads 0% with the alarm border — not a placeholder', () => {
    renderCards(metrics(0));

    expect(within(slaCard()).getByText('0%')).toBeInTheDocument();
    expect(slaCard().className).toContain('border-theme-error-border');
  });

  it('a healthy rate reads through with no alarm border', () => {
    renderCards(metrics(95));

    expect(within(slaCard()).getByText('95%')).toBeInTheDocument();
    expect(slaCard().className).not.toContain('border-theme-error-border');
  });
});
