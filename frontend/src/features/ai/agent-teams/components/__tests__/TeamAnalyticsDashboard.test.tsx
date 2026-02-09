import { render, screen, fireEvent } from '@testing-library/react';
import TeamAnalyticsDashboard from '../TeamAnalyticsDashboard';
import type { TeamAnalytics } from '@/shared/services/ai/TeamsApiService';

jest.mock('recharts', () => {
  const MC = ({ children, ...p }: any) => <div data-testid={p['data-testid'] || 'chart'}>{children}</div>;
  return { ResponsiveContainer: ({ children }: any) => <div data-testid="responsive-container">{children}</div>,
    AreaChart: MC, Area: MC, XAxis: MC, YAxis: MC, CartesianGrid: MC, Tooltip: MC,
    PieChart: MC, Pie: MC, Cell: MC, BarChart: MC, Bar: MC, ComposedChart: MC, Line: MC, Legend: MC };
});

jest.mock('@/shared/components/layout/TabContainer', () => ({
  TabContainer: ({ children, tabs, activeTab, onTabChange }: any) => (
    <div data-testid="tab-container">
      {tabs.map((t: any) => (
        <button key={t.id} data-testid={`tab-${t.id}`} onClick={() => onTabChange(t.id)} className={activeTab === t.id ? 'active' : ''}>
          {t.label}
        </button>
      ))}
      {children}
    </div>
  ),
  TabPanel: ({ children, tabId, activeTab }: any) => (
    activeTab === tabId ? <div data-testid={`panel-${tabId}`}>{children}</div> : null
  ),
}));

const mockAnalytics: TeamAnalytics = {
  period_days: 30, generated_at: '2026-02-01T00:00:00Z',
  overview: {
    total_executions: 25, completed_executions: 20, failed_executions: 3,
    cancelled_executions: 1, active_executions: 1, success_rate: 86.96,
    total_tasks: 150, completed_tasks: 130, failed_tasks: 10,
    total_messages: 500, total_tokens_used: 1250000, total_cost_usd: 12.5432,
    executions_by_day: { '2026-01-15': 3, '2026-01-16': 5 },
    cost_by_day: { '2026-01-15': 1.25, '2026-01-16': 2.50 },
  },
  performance: {
    avg_duration_ms: 45000, median_duration_ms: 42000, p95_duration_ms: 120000,
    min_duration_ms: 5000, max_duration_ms: 180000,
    avg_tasks_per_execution: 6.0, avg_messages_per_execution: 20.0, throughput_per_day: 0.83,
    status_breakdown: { completed: 20, failed: 3, cancelled: 1, running: 1 },
    termination_reasons: { completed: 20 },
    duration_by_day: { '2026-01-15': 40000, '2026-01-16': 50000 },
    slowest_executions: [{ id: '1', execution_id: 'exec-1', objective: 'Long task', duration_ms: 180000, tasks_total: 10, created_at: '2026-01-15T00:00:00Z' }],
  },
  cost: {
    total_cost_usd: 12.5432, total_tokens: 1250000,
    avg_cost_per_execution: 0.5017, avg_tokens_per_execution: 50000,
    cost_by_day: { '2026-01-15': 1.25, '2026-01-16': 2.50 },
    tokens_by_day: { '2026-01-15': 125000, '2026-01-16': 250000 },
    cost_by_status: { completed: 10.0, failed: 2.5 },
    tokens_by_status: { completed: 1000000, failed: 250000 },
    top_cost_executions: [{ id: '1', execution_id: 'exec-1', objective: 'Expensive task', cost_usd: 5.0, tokens: 500000, created_at: '2026-01-15T00:00:00Z' }],
    cost_per_task: 0.0836, cost_per_message: 0.0251,
  },
  agents: {
    role_stats: [
      { role_id: 'r1', role_name: 'Researcher', role_type: 'worker', agent_name: 'Agent A', tasks_total: 50, tasks_completed: 45, tasks_failed: 3, success_rate: 93.75, avg_duration_ms: 30000, total_tokens: 500000, total_cost_usd: 5.0, messages_sent: 100, messages_received: 80, tools_used: { search: 20 }, avg_retries: 0.5 },
      { role_id: 'r2', role_name: 'Writer', role_type: 'worker', agent_name: 'Agent B', tasks_total: 40, tasks_completed: 38, tasks_failed: 1, success_rate: 97.44, avg_duration_ms: 25000, total_tokens: 400000, total_cost_usd: 4.0, messages_sent: 80, messages_received: 60, tools_used: { write: 30 }, avg_retries: 0.2 },
    ],
    task_type_distribution: { execution: 80, review: 30 },
    workload_by_role: { Researcher: 50, Writer: 40 },
    unassigned_tasks: 5, top_tools: { search: 20, write: 30 },
  },
  communication: {
    total_messages: 500,
    message_type_distribution: { task_update: 200, question: 50 },
    priority_distribution: { normal: 400, high: 70 },
    escalation_count: 10, escalation_rate: 2.0,
    questions_asked: 50, questions_answered: 45, pending_responses: 5,
    response_rate: 90.0, avg_response_time_seconds: 12.5,
    messages_by_day: { '2026-01-15': 50, '2026-01-16': 70 },
    role_interactions: [{ from: 'Researcher', to: 'Writer', count: 30 }, { from: 'Writer', to: 'Researcher', count: 25 }],
    broadcasts_count: 20, high_priority_count: 100,
  },
  quality: {
    total_reviews: 30, approved_count: 22, rejected_count: 3,
    revision_requested_count: 4, pending_count: 1, approval_rate: 73.33,
    avg_quality_score: 78.5, quality_score_distribution: { '0-20': 1, '81-100': 12 },
    avg_review_duration_ms: 15000, avg_revision_count: 1.2,
    review_mode_breakdown: { blocking: 20, shadow: 10 },
    findings_by_severity: { low: 10, high: 2 },
    findings_by_category: { correctness: 8, style: 4 },
    learning: {
      total_learnings: 15, by_category: { pattern: 5, best_practice: 4 },
      by_extraction_method: { auto_success: 8, review: 5 },
      avg_importance: 0.72, avg_confidence: 0.85, avg_effectiveness: 0.68,
      total_injections: 42, positive_outcomes: 35, negative_outcomes: 7,
      injection_success_rate: 83.33, high_importance_count: 8,
    },
  },
};

const defaultProps = { analytics: mockAnalytics, onPeriodChange: jest.fn() };
const renderDashboard = (overrides: Partial<typeof defaultProps> = {}) =>
  render(<TeamAnalyticsDashboard {...defaultProps} {...overrides} />);

describe('TeamAnalyticsDashboard', () => {
  beforeEach(() => jest.clearAllMocks());

  describe('Period selector', () => {
    it('renders all 4 period buttons', () => {
      renderDashboard();
      expect(screen.getByText('7d')).toBeInTheDocument();
      expect(screen.getByText('14d')).toBeInTheDocument();
      expect(screen.getByText('30d')).toBeInTheDocument();
      expect(screen.getByText('90d')).toBeInTheDocument();
    });

    it('calls onPeriodChange with correct value on click', () => {
      const onPeriodChange = jest.fn();
      renderDashboard({ onPeriodChange });
      fireEvent.click(screen.getByText('7d'));
      expect(onPeriodChange).toHaveBeenCalledWith(7);
      fireEvent.click(screen.getByText('90d'));
      expect(onPeriodChange).toHaveBeenCalledWith(90);
    });

    it('highlights the active period button', () => {
      renderDashboard();
      expect(screen.getByText('30d').className).toContain('bg-theme-interactive-primary');
      expect(screen.getByText('7d').className).not.toContain('bg-theme-interactive-primary');
    });
  });

  describe('Generated timestamp', () => {
    it('shows the generated_at date', () => {
      renderDashboard();
      const formatted = new Date('2026-02-01T00:00:00Z').toLocaleString();
      expect(screen.getByText(new RegExp(formatted.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')))).toBeInTheDocument();
    });
  });

  describe('Tabs', () => {
    it('renders all 6 tabs', () => {
      renderDashboard();
      for (const [id, label] of [['overview','Overview'],['performance','Performance'],['cost','Cost'],['agents','Agents'],['communication','Communication'],['quality','Quality']]) {
        expect(screen.getByTestId(`tab-${id}`)).toHaveTextContent(label);
      }
    });
  });

  describe('Overview tab', () => {
    it('renders KPI cards with correct values', () => {
      renderDashboard();
      expect(screen.getByText('Total Executions')).toBeInTheDocument();
      expect(screen.getByText('25')).toBeInTheDocument();
      expect(screen.getByText('Success Rate')).toBeInTheDocument();
      expect(screen.getByText('86.96%')).toBeInTheDocument();
      expect(screen.getByText('Total Cost')).toBeInTheDocument();
    });
  });

  describe('Performance tab', () => {
    it('renders duration KPI cards', () => {
      renderDashboard();
      fireEvent.click(screen.getByTestId('tab-performance'));
      expect(screen.getByText('Avg Duration')).toBeInTheDocument();
      expect(screen.getByText('45.0s')).toBeInTheDocument();
      expect(screen.getByText('Median Duration')).toBeInTheDocument();
      expect(screen.getByText('42.0s')).toBeInTheDocument();
      expect(screen.getByText('P95 Duration')).toBeInTheDocument();
      expect(screen.getByText('2.0m')).toBeInTheDocument();
    });
  });

  describe('Cost tab', () => {
    it('renders cost KPI cards', () => {
      renderDashboard();
      fireEvent.click(screen.getByTestId('tab-cost'));
      expect(screen.getByText('Avg Cost/Execution')).toBeInTheDocument();
      expect(screen.getByText('Cost Per Task')).toBeInTheDocument();
      expect(screen.getByText('Cost Per Message')).toBeInTheDocument();
    });
  });

  describe('Agents tab', () => {
    it('renders agent role stats table', () => {
      renderDashboard();
      fireEvent.click(screen.getByTestId('tab-agents'));
      expect(screen.getByText('Researcher')).toBeInTheDocument();
      expect(screen.getByText('Writer')).toBeInTheDocument();
      expect(screen.getByText('Agent A')).toBeInTheDocument();
      expect(screen.getByText('Agent B')).toBeInTheDocument();
    });
  });

  describe('Communication tab', () => {
    it('renders message counts', () => {
      renderDashboard();
      fireEvent.click(screen.getByTestId('tab-communication'));
      expect(screen.getByText('Total Messages')).toBeInTheDocument();
      expect(screen.getByText('500')).toBeInTheDocument();
      expect(screen.getByText('Response Rate')).toBeInTheDocument();
      expect(screen.getByText('90%')).toBeInTheDocument();
      expect(screen.getByText('Escalations')).toBeInTheDocument();
    });
  });

  describe('Quality tab', () => {
    it('renders review metrics', () => {
      renderDashboard();
      fireEvent.click(screen.getByTestId('tab-quality'));
      expect(screen.getByText('Total Reviews')).toBeInTheDocument();
      expect(screen.getByText('30')).toBeInTheDocument();
      expect(screen.getByText('Approval Rate')).toBeInTheDocument();
      expect(screen.getByText('73.33%')).toBeInTheDocument();
      expect(screen.getByText('Avg Quality Score')).toBeInTheDocument();
    });
  });

  describe('Empty analytics', () => {
    it('renders without crashing when all values are zero or empty', () => {
      const empty: TeamAnalytics = {
        period_days: 7, generated_at: '2026-02-01T00:00:00Z',
        overview: { total_executions: 0, completed_executions: 0, failed_executions: 0, cancelled_executions: 0, active_executions: 0, success_rate: 0, total_tasks: 0, completed_tasks: 0, failed_tasks: 0, total_messages: 0, total_tokens_used: 0, total_cost_usd: 0, executions_by_day: {}, cost_by_day: {} },
        performance: { avg_duration_ms: null, median_duration_ms: null, p95_duration_ms: null, min_duration_ms: null, max_duration_ms: null, avg_tasks_per_execution: 0, avg_messages_per_execution: 0, throughput_per_day: 0, status_breakdown: {}, termination_reasons: {}, duration_by_day: {}, slowest_executions: [] },
        cost: { total_cost_usd: 0, total_tokens: 0, avg_cost_per_execution: 0, avg_tokens_per_execution: 0, cost_by_day: {}, tokens_by_day: {}, cost_by_status: {}, tokens_by_status: {}, top_cost_executions: [], cost_per_task: 0, cost_per_message: 0 },
        agents: { role_stats: [], task_type_distribution: {}, workload_by_role: {}, unassigned_tasks: 0, top_tools: {} },
        communication: { total_messages: 0, message_type_distribution: {}, priority_distribution: {}, escalation_count: 0, escalation_rate: 0, questions_asked: 0, questions_answered: 0, pending_responses: 0, response_rate: 0, avg_response_time_seconds: 0, messages_by_day: {}, role_interactions: [], broadcasts_count: 0, high_priority_count: 0 },
        quality: { total_reviews: 0, approved_count: 0, rejected_count: 0, revision_requested_count: 0, pending_count: 0, approval_rate: 0, avg_quality_score: 0, quality_score_distribution: {}, avg_review_duration_ms: 0, avg_revision_count: 0, review_mode_breakdown: {}, findings_by_severity: {}, findings_by_category: {}, learning: { total_learnings: 0, by_category: {}, by_extraction_method: {}, avg_importance: 0, avg_confidence: 0, avg_effectiveness: 0, total_injections: 0, positive_outcomes: 0, negative_outcomes: 0, injection_success_rate: 0, high_importance_count: 0 } },
      };
      const { container } = render(<TeamAnalyticsDashboard analytics={empty} onPeriodChange={jest.fn()} />);
      expect(container).toBeTruthy();
      expect(screen.getByTestId('tab-container')).toBeInTheDocument();
    });
  });
});
