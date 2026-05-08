import { render, screen, fireEvent, waitFor, act } from '@testing-library/react';
import { ProjectProvisioningChat } from './ProjectProvisioningChat';
import type { ProvisioningChatMessage } from './ProjectProvisioningChat';

const mockGet = jest.fn();
const mockPost = jest.fn();

jest.mock('@/shared/services/apiClient', () => ({
  __esModule: true,
  default: {
    get: (...args: unknown[]) => mockGet(...args),
    post: (...args: unknown[]) => mockPost(...args),
  },
  apiClient: {
    get: (...args: unknown[]) => mockGet(...args),
    post: (...args: unknown[]) => mockPost(...args),
  },
}));

interface SubscribeOptions {
  channel: string;
  params?: Record<string, unknown>;
  onMessage?: (data: unknown) => void;
  onError?: (err: string) => void;
}

const mockSubscribe = jest.fn<() => void, [SubscribeOptions]>(() => jest.fn());

jest.mock('@/shared/hooks/useWebSocket', () => ({
  useWebSocket: () => ({
    isConnected: true,
    error: null,
    lastConnected: new Date(),
    subscribe: mockSubscribe,
    sendMessage: jest.fn(),
  }),
}));

// Avoid pulling in remark-gfm/react-markdown ESM via the real ChatStreamingRenderer
jest.mock('@/features/ai/chat/components/ChatStreamingRenderer', () => ({
  ChatStreamingRenderer: ({ content }: { content: string }) => (
    <div data-testid="chat-streaming-renderer">{content}</div>
  ),
}));

// Avoid pulling in chatApi via the real ConciergeActionCard
jest.mock('@/features/ai/chat/components/ConciergeActionCard', () => ({
  ConciergeActionCard: ({ actionContext }: { actionContext: { action_type: string } }) => (
    <div data-testid="concierge-action-card">{actionContext.action_type}</div>
  ),
}));

const buildMessages = (msgs: ProvisioningChatMessage[]) => {
  mockGet.mockResolvedValue({ data: { data: { messages: msgs } } });
};

beforeEach(() => {
  mockGet.mockReset();
  mockPost.mockReset();
  mockSubscribe.mockClear();
});

describe('ProjectProvisioningChat', () => {
  it('fetches messages on mount and renders user + ai content', async () => {
    buildMessages([
      {
        id: 'm-1',
        sender_type: 'user',
        content: 'Provision an API',
        created_at: '2026-05-07T00:00:00Z',
      },
      {
        id: 'm-2',
        sender_type: 'ai',
        content: 'Got it — drafting a brief.',
        created_at: '2026-05-07T00:00:01Z',
      },
    ]);

    render(<ProjectProvisioningChat conversationId="conv-1" onOpenPlan={jest.fn()} />);

    await waitFor(() => {
      expect(mockGet).toHaveBeenCalledWith('/ai/conversations/conv-1/messages');
    });
    expect(await screen.findByText('Provision an API')).toBeInTheDocument();
    expect(await screen.findByText('Got it — drafting a brief.')).toBeInTheDocument();
  });

  it('subscribes to ConversationChannel and appends incoming messages', async () => {
    buildMessages([]);
    render(<ProjectProvisioningChat conversationId="conv-1" onOpenPlan={jest.fn()} />);

    await waitFor(() => expect(mockSubscribe).toHaveBeenCalled());
    const sub = mockSubscribe.mock.calls[0][0];
    expect(sub.channel).toBe('ConversationChannel');
    expect(sub.params).toEqual({ conversation_id: 'conv-1' });

    act(() => {
      sub.onMessage!({
        event: 'message_created',
        message: {
          id: 'm-99',
          sender_type: 'ai',
          content: 'Streamed reply',
          created_at: '2026-05-07T00:01:00Z',
        },
      });
    });

    expect(await screen.findByText('Streamed reply')).toBeInTheDocument();
  });

  it('renders 4 starter chips that pre-fill the input on click', async () => {
    buildMessages([]);
    render(<ProjectProvisioningChat conversationId="conv-1" onOpenPlan={jest.fn()} />);

    const chipsRoot = await screen.findByTestId('starter-chips');
    const chips = chipsRoot.querySelectorAll('button');
    expect(chips.length).toBe(4);

    fireEvent.click(screen.getByText('SaaS API'));
    const input = screen.getByTestId('chat-input') as HTMLTextAreaElement;
    expect(input.value).toMatch(/SaaS API/i);
  });

  it('renders ConciergeActionCard when AI message has provision_infrastructure action', async () => {
    buildMessages([
      {
        id: 'm-1',
        sender_type: 'ai',
        content: 'Ready to provision.',
        created_at: '2026-05-07T00:00:00Z',
        metadata: {
          concierge_action: 'provision_infrastructure',
          pending_action: { type: 'provision_infrastructure' },
          action_context: { action_type: 'provision_infrastructure', status: 'pending' },
          actions: [{ type: 'confirm', label: 'Confirm', style: 'primary' }],
          action_params: {},
        },
      },
    ]);

    render(<ProjectProvisioningChat conversationId="conv-1" onOpenPlan={jest.fn()} />);
    expect(await screen.findByTestId('concierge-action-card')).toHaveTextContent(
      'provision_infrastructure'
    );
  });

  it('renders Open Plan button on plan_ready and triggers callback', async () => {
    const onOpenPlan = jest.fn();
    buildMessages([
      {
        id: 'm-1',
        sender_type: 'ai',
        content: 'Plan ready',
        created_at: '2026-05-07T00:00:00Z',
        metadata: { plan_ready: { mission_id: 'mission-42' } },
      },
    ]);

    render(<ProjectProvisioningChat conversationId="conv-1" onOpenPlan={onOpenPlan} />);
    const btn = await screen.findByTestId('open-plan-button');
    fireEvent.click(btn);
    expect(onOpenPlan).toHaveBeenCalledWith('mission-42');
  });

  it('invokes renderBriefCard with latest brief_card metadata', async () => {
    buildMessages([
      {
        id: 'm-1',
        sender_type: 'ai',
        content: 'Brief',
        created_at: '2026-05-07T00:00:00Z',
        metadata: {
          action_metadata: {
            type: 'brief_card',
            title: 'Project Brief',
            summary: 'A SaaS API',
          },
        },
      },
    ]);

    const renderBriefCard = jest.fn(
      (data) => <div data-testid="brief-card-mount">{data?.title ?? 'none'}</div>
    );

    render(
      <ProjectProvisioningChat
        conversationId="conv-1"
        onOpenPlan={jest.fn()}
        renderBriefCard={renderBriefCard}
      />
    );

    expect(await screen.findByTestId('companion-rail')).toBeInTheDocument();
    expect(await screen.findByTestId('brief-card-mount')).toHaveTextContent('Project Brief');
  });

  it('sends a message via apiClient.post when the form is submitted', async () => {
    buildMessages([]);
    mockPost.mockResolvedValue({ data: { data: {} } });

    render(<ProjectProvisioningChat conversationId="conv-1" onOpenPlan={jest.fn()} />);

    const input = (await screen.findByTestId('chat-input')) as HTMLTextAreaElement;
    fireEvent.change(input, { target: { value: 'I want a static site' } });
    fireEvent.submit(input.closest('form')!);

    await waitFor(() =>
      expect(mockPost).toHaveBeenCalledWith('/ai/conversations/conv-1/messages', {
        message: { content: 'I want a static site' },
      })
    );
  });

  it('notifies parent of mission_id+phase changes via onMissionUpdate', async () => {
    const onMissionUpdate = jest.fn();
    buildMessages([
      {
        id: 'm-1',
        sender_type: 'ai',
        content: 'Phase update',
        created_at: '2026-05-07T00:00:00Z',
        metadata: { mission_id: 'mission-99', mission_phase: 'execute' },
      },
    ]);

    render(
      <ProjectProvisioningChat
        conversationId="conv-1"
        onOpenPlan={jest.fn()}
        onMissionUpdate={onMissionUpdate}
      />
    );

    await waitFor(() =>
      expect(onMissionUpdate).toHaveBeenCalledWith({ id: 'mission-99', phase: 'execute' })
    );
  });
});
