import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { SessionMessages } from '../SessionMessages';

jest.mock('@/shared/services/ai', () => ({
  chatChannelsApi: {
    getSessionMessages: jest.fn(),
    getTypingStatus: jest.fn(),
  },
}));

import { chatChannelsApi } from '@/shared/services/ai';

const mockedGetSessionMessages = chatChannelsApi.getSessionMessages as jest.Mock;
const mockedGetTypingStatus = chatChannelsApi.getTypingStatus as jest.Mock;

const mockMessages = [
  {
    id: 'msg-1',
    direction: 'inbound',
    content: 'Hello from user',
    delivery_status: 'delivered',
    created_at: '2026-02-01T10:00:00Z',
  },
  {
    id: 'msg-2',
    direction: 'outbound',
    content: 'Hello from agent',
    delivery_status: 'delivered',
    created_at: '2026-02-01T10:01:00Z',
  },
  {
    id: 'msg-3',
    direction: 'outbound',
    content: 'Follow up',
    delivery_status: 'pending',
    created_at: '2026-02-01T10:02:00Z',
  },
  {
    id: 'msg-4',
    direction: 'outbound',
    content: 'Failed message',
    delivery_status: 'failed',
    created_at: '2026-02-01T10:03:00Z',
  },
];

const defaultProps = {
  sessionId: 'session-1',
  onBack: jest.fn(),
};

describe('SessionMessages', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockedGetSessionMessages.mockResolvedValue({ items: mockMessages });
    mockedGetTypingStatus.mockResolvedValue({ typing: null });
    // Mock scrollIntoView
    Element.prototype.scrollIntoView = jest.fn();
  });

  it('fetches messages on mount', async () => {
    render(<SessionMessages {...defaultProps} />);
    await waitFor(() => {
      expect(mockedGetSessionMessages).toHaveBeenCalledWith('session-1', { per_page: 100 });
    });
  });

  it('renders messages after loading', async () => {
    render(<SessionMessages {...defaultProps} />);
    await waitFor(() => {
      expect(screen.getByText('Hello from user')).toBeInTheDocument();
    });
    expect(screen.getByText('Hello from agent')).toBeInTheDocument();
    expect(screen.getByText('Follow up')).toBeInTheDocument();
    expect(screen.getByText('Failed message')).toBeInTheDocument();
  });

  it('renders inbound messages with left alignment', async () => {
    render(<SessionMessages {...defaultProps} />);
    await waitFor(() => {
      expect(screen.getByText('Hello from user')).toBeInTheDocument();
    });
    const inboundMsg = screen.getByText('Hello from user').closest('[class*="flex"]');
    expect(inboundMsg?.className).toContain('justify-start');
  });

  it('renders outbound messages with right alignment', async () => {
    render(<SessionMessages {...defaultProps} />);
    await waitFor(() => {
      expect(screen.getByText('Hello from agent')).toBeInTheDocument();
    });
    const outboundMsg = screen.getByText('Hello from agent').closest('[class*="flex justify"]');
    expect(outboundMsg?.className).toContain('justify-end');
  });

  it('shows delivery status badges on outbound messages', async () => {
    render(<SessionMessages {...defaultProps} />);
    await waitFor(() => {
      expect(screen.getByText('Hello from agent')).toBeInTheDocument();
    });
    expect(screen.getAllByText('Delivered').length).toBeGreaterThanOrEqual(1);
    expect(screen.getByText('Pending')).toBeInTheDocument();
    expect(screen.getByText('Failed')).toBeInTheDocument();
  });

  it('shows message count', async () => {
    render(<SessionMessages {...defaultProps} />);
    await waitFor(() => {
      expect(screen.getByText('(4 messages)')).toBeInTheDocument();
    });
  });

  it('shows loading state', () => {
    mockedGetSessionMessages.mockReturnValue(new Promise(() => {}));
    render(<SessionMessages {...defaultProps} />);
    // Should show a loading indicator (no messages yet, loading=true)
    expect(screen.queryByText('Message History')).not.toBeInTheDocument();
  });

  it('shows empty state when no messages', async () => {
    mockedGetSessionMessages.mockResolvedValue({ items: [] });
    render(<SessionMessages {...defaultProps} />);
    await waitFor(() => {
      expect(screen.getByText('No messages')).toBeInTheDocument();
    });
  });

  it('shows error on failure', async () => {
    mockedGetSessionMessages.mockRejectedValue(new Error('Network error'));
    render(<SessionMessages {...defaultProps} />);
    await waitFor(() => {
      expect(screen.getByText('Network error')).toBeInTheDocument();
    });
  });

  it('has back button that calls onBack', async () => {
    render(<SessionMessages {...defaultProps} />);
    await waitFor(() => {
      expect(screen.getByText('Hello from user')).toBeInTheDocument();
    });

    // The back button contains the ArrowLeft icon - find the first ghost button
    const buttons = screen.getAllByRole('button');
    const backButton = buttons[0]; // First button is the back button
    fireEvent.click(backButton);
    expect(defaultProps.onBack).toHaveBeenCalled();
  });

  it('shows Message History header', async () => {
    render(<SessionMessages {...defaultProps} />);
    await waitFor(() => {
      expect(screen.getByText('Message History')).toBeInTheDocument();
    });
  });

  it('drops a typing-status response that resolves after switching sessions', async () => {
    // Regression test for review F2 (review-lane4-c8.md): a shared
    // "cancelled" boolean reset by the next generation's setup effect would
    // let an in-flight request from a stale session write into the new
    // session's UI. This asserts the fix (a per-generation counter) blocks
    // that write, the way the original effect-scoped `cancelled` flag did.
    let resolveSessionOneTyping: (value: { typing: { session_id: string; agent_name: string; is_typing: boolean; timestamp: string } }) => void;
    const sessionOneTypingPromise = new Promise<{
      typing: { session_id: string; agent_name: string; is_typing: boolean; timestamp: string };
    }>((resolve) => {
      resolveSessionOneTyping = resolve;
    });

    mockedGetTypingStatus.mockImplementation((sessionId: string) => {
      if (sessionId === 'session-1') return sessionOneTypingPromise;
      return Promise.resolve({ typing: null });
    });

    const { rerender } = render(
      <SessionMessages {...defaultProps} sessionId="session-1" sessionStatus="active" />
    );

    await waitFor(() => {
      expect(mockedGetTypingStatus).toHaveBeenCalledWith('session-1');
    });

    // Switch sessions while session-1's typing request is still in flight.
    rerender(<SessionMessages {...defaultProps} sessionId="session-2" sessionStatus="active" />);

    await waitFor(() => {
      expect(mockedGetTypingStatus).toHaveBeenCalledWith('session-2');
    });

    // The stale session-1 response resolves after the switch, claiming an
    // agent is typing. It must not land in session-2's UI.
    resolveSessionOneTyping!({
      typing: { session_id: 'session-1', agent_name: 'Agent A', is_typing: true, timestamp: '2026-02-01T10:00:00Z' },
    });

    // Flush the microtask queue so the stale .then() has a chance to run.
    await new Promise((r) => setTimeout(r, 0));

    expect(screen.queryByText(/is typing/)).not.toBeInTheDocument();
  });
});
