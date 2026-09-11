import { screen, within } from '@testing-library/react';
import { renderWithProviders } from '@/test-utils';
import type { ConversationMetrics } from '@/shared/types/monitoring';
import { ConversationAnalytics } from './ConversationAnalytics';

// M1 tail. Nothing measures a conversation's health or success rate today, and
// the page used to hand this list a literal 100 for both. Absent now reads
// "—", and the summary averages only the conversations that were measured.
jest.mock('@/shared/components/ui/Progress', () => ({
  Progress: ({ value }: { value: unknown }) => <div data-testid="progress" data-value={String(value)} />,
}));

const conversation = (id: string, health_score: number | null, success_rate: number | null): ConversationMetrics => ({
  id,
  title: `Conversation ${id}`,
  status: 'active',
  health_score,
  performance: { avg_response_time: 0, message_throughput: 3, success_rate },
  usage: { messages_count: 3, total_tokens: 10, total_cost: 0 },
  participants: { human_messages: 1, ai_messages: 2, system_messages: 0 },
  agent_usage: [],
  alerts: [],
  last_activity: null,
  created_at: '2026-09-11T00:00:00Z',
  updated_at: '2026-09-11T00:00:00Z',
});

const renderList = (conversations: ConversationMetrics[]) =>
  renderWithProviders(<ConversationAnalytics conversations={conversations} isLoading={false} timeRange="24h" onRefresh={jest.fn()} />);
const box = (label: string) => screen.getByText(label).parentElement as HTMLElement;
const meterValues = () => screen.queryAllByTestId('progress').map((m) => m.getAttribute('data-value'));

describe('ConversationAnalytics — unmeasured figures', () => {
  it('an unmeasured conversation reads "—" for health and in the summary, with no meter', () => {
    renderList([conversation('c1', null, null)]);

    expect(within(box('Success Rate')).getByText('—')).toBeInTheDocument();
    expect(within(box('Health Score')).getByText('—')).toBeInTheDocument();
    expect(meterValues()).not.toContain('null');
  });

  it('the summary averages only the measured conversations', () => {
    renderList([conversation('c1', null, 80), conversation('c2', null, null)]);

    expect(within(box('Success Rate')).getByText('80.0%')).toBeInTheDocument();
  });

  it('a measured health score reads through with its meter', () => {
    renderList([conversation('c1', 92, 95)]);

    expect(within(box('Health Score')).getByText('92.0%')).toBeInTheDocument();
    expect(meterValues()).toContain('92');
  });
});
