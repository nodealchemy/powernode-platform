import { render, screen, fireEvent } from '@testing-library/react';
import { EscalationsTab } from './EscalationsTab';
import {
  EscalationDecision,
  EscalationRollup,
  EscalationBenefit,
  EscalationBenefitSummary,
  EscalationBenefitAdvisory
} from '@/shared/services/ai/ModelRouterApiService';

const summary: EscalationBenefitSummary = {
  matched_buckets: 1,
  total_buckets: 2,
  escalated_measured: 12,
  standard_measured: 30,
  escalated_success_rate: 91.67,
  standard_success_rate: 83.33,
  success_rate_delta: 8.34,
  avg_cost_delta: 0.001234,
  avg_latency_delta: 420.5
};

const advisory: EscalationBenefitAdvisory = {
  recommend_tightening: false,
  status: 'beneficial',
  threshold: 10,
  escalated_measured: 12,
  success_rate_delta: 8.34,
  message: 'Escalated selections show a positive success-rate delta over comparable standard-tier selections.'
};

const rollup: EscalationRollup = {
  period_days: 7,
  total_decisions: 200,
  escalated_decisions: 25,
  selections: { frontier: 18, reasoning: 7, high_effort: 40 },
  top_rationale_categories: {
    by_complexity_level: { very_high: 15, high: 10 },
    by_task_type: { architecture: 12, debugging: 8 },
    by_decision_kind: { escalate: 25, hold: 175 }
  },
  spend: { total_usd: 12.5, escalated_usd: 5.25, escalated_share_pct: 42.0 },
  benefit: summary,
  advisory
};

const benefit: EscalationBenefit = {
  task_type_filter: null,
  buckets: [
    {
      task_type: 'architecture',
      complexity_level: 'very_high',
      escalated: { decisions: 15, measured: 12, success_rate: 91.67, avg_cost_usd: 0.21, avg_latency_ms: 8000 },
      standard: { decisions: 35, measured: 30, success_rate: 83.33, avg_cost_usd: 0.04, avg_latency_ms: 4200 },
      matched: true,
      deltas: { success_rate: 8.34, avg_cost_usd: 0.17, avg_latency_ms: 3800 }
    }
  ],
  summary,
  advisory
};

const escalation: EscalationDecision = {
  id: 'esc-1',
  created_at: '2026-07-01T12:00:00Z',
  model_tier: 'frontier',
  delivered_model: 'test-frontier-model',
  baseline_tier: 'standard',
  effort: 'high',
  task_type: 'architecture',
  complexity_level: 'very_high',
  complexity_score: 0.92,
  agent_id: 'agent-1',
  agent_type: 'Ai::Agent',
  rationale_summary: 'Escalated: very high complexity architecture task',
  top_signals: ['multi_file', 'cross_service'],
  outcome: 'succeeded',
  cost_usd: 0.2145,
  latency_ms: 8123,
  tokens_used: 55000,
  quality_score: 0.9
};

const baseProps = {
  escalations: [escalation],
  rollup,
  benefit,
  loading: false,
  tierFilter: 'all' as const,
  timeRange: '7d' as const,
  onTierChange: jest.fn(),
  onTimeRangeChange: jest.fn()
};

describe('EscalationsTab', () => {
  beforeEach(() => jest.clearAllMocks());

  it('renders rollup cards with counts and spend share', () => {
    render(<EscalationsTab {...baseProps} />);
    expect(screen.getByText('Escalated Decisions')).toBeInTheDocument();
    expect(screen.getAllByText('25').length).toBeGreaterThan(0);
    expect(screen.getByText('Frontier Selections')).toBeInTheDocument();
    expect(screen.getByText('18')).toBeInTheDocument();
    expect(screen.getByText('High-Effort Selections')).toBeInTheDocument();
    expect(screen.getByText('40')).toBeInTheDocument();
    expect(screen.getByText('Escalated Spend Share')).toBeInTheDocument();
    expect(screen.getByText('42.00%')).toBeInTheDocument();
  });

  it('renders the escalation decisions table', () => {
    render(<EscalationsTab {...baseProps} />);
    expect(screen.getByText('test-frontier-model')).toBeInTheDocument();
    expect(screen.getByText('frontier')).toBeInTheDocument();
    expect(screen.getByText('from standard')).toBeInTheDocument();
    expect(screen.getByText('Escalated: very high complexity architecture task')).toBeInTheDocument();
    expect(screen.getByText('succeeded')).toBeInTheDocument();
    expect(screen.getByText('$0.2145')).toBeInTheDocument();
  });

  it('renders top rationale categories', () => {
    render(<EscalationsTab {...baseProps} />);
    expect(screen.getByText('Top Rationale Categories')).toBeInTheDocument();
    expect(screen.getByText('very high')).toBeInTheDocument();
    expect(screen.getByText('debugging')).toBeInTheDocument();
    expect(screen.getByText('escalate')).toBeInTheDocument();
  });

  it('renders the benefit-delta summary', () => {
    render(<EscalationsTab {...baseProps} />);
    expect(screen.getByText('Escalation Benefit')).toBeInTheDocument();
    expect(screen.getByText('Success Rate Delta')).toBeInTheDocument();
    expect(screen.getAllByText('+8.34%').length).toBe(2); // summary card + bucket row
    expect(screen.getByText('+$0.170000')).toBeInTheDocument();
  });

  it('does not show the advisory banner when tightening is not recommended', () => {
    render(<EscalationsTab {...baseProps} />);
    expect(screen.queryByText('Escalation tightening recommended')).not.toBeInTheDocument();
  });

  it('shows the advisory banner on recommend_tightening', () => {
    const tighten: EscalationBenefitAdvisory = {
      ...advisory,
      recommend_tightening: true,
      status: 'non_positive_benefit',
      success_rate_delta: -2.5,
      message: 'Escalated selections show no measurable benefit. Consider tightening escalation thresholds.'
    };
    render(
      <EscalationsTab
        {...baseProps}
        rollup={{ ...rollup, advisory: tighten }}
        benefit={{ ...benefit, advisory: tighten }}
      />
    );
    expect(screen.getByText('Escalation tightening recommended')).toBeInTheDocument();
    expect(
      screen.getByText('Escalated selections show no measurable benefit. Consider tightening escalation thresholds.')
    ).toBeInTheDocument();
  });

  it('fires filter callbacks', () => {
    render(<EscalationsTab {...baseProps} />);
    fireEvent.change(screen.getByLabelText('Filter by tier'), { target: { value: 'frontier' } });
    expect(baseProps.onTierChange).toHaveBeenCalledWith('frontier');
    fireEvent.change(screen.getByLabelText('Filter by time range'), { target: { value: '30d' } });
    expect(baseProps.onTimeRangeChange).toHaveBeenCalledWith('30d');
  });

  it('shows the empty state when there are no escalations', () => {
    render(<EscalationsTab {...baseProps} escalations={[]} rollup={null} benefit={null} />);
    expect(screen.getByText('No escalations')).toBeInTheDocument();
  });

  it('shows a loading spinner while loading', () => {
    render(<EscalationsTab {...baseProps} loading />);
    expect(screen.getByText('Loading escalation data...')).toBeInTheDocument();
    expect(screen.queryByText('Escalation Benefit')).not.toBeInTheDocument();
  });
});
