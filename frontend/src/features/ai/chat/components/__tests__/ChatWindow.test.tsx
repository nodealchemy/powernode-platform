import { render, screen, fireEvent } from '@testing-library/react';
import { ChatWindow } from '../ChatWindow';
import { useChatWindow } from '../../context/ChatWindowContext';
import type { ChatWindowState, ChatWindowAction } from '../../context/chatWindowTypes';

jest.mock('../../context/ChatWindowContext', () => ({
  useChatWindow: jest.fn(),
}));

jest.mock('@/features/ai/components/AgentConversationComponent', () => ({
  AgentConversationComponent: ({ conversation, onNewMessage }: { conversation: { id: string }; onNewMessage: () => void }) => (
    <div data-testid={`conversation-${conversation.id}`}>
      <button data-testid="new-message-btn" onClick={onNewMessage}>Trigger</button>
    </div>
  ),
}));

jest.mock('../ChatWindowHeader', () => ({
  ChatWindowHeader: ({ onPointerDown }: { onPointerDown?: (e: React.PointerEvent) => void }) => (
    <div data-testid="chat-header" onPointerDown={onPointerDown} />
  ),
}));

jest.mock('../ChatWindowTabs', () => ({
  ChatWindowTabs: ({ onNewTab }: { onNewTab: () => void }) => (
    <div data-testid="chat-tabs">
      <button data-testid="new-tab-btn" onClick={onNewTab}>+</button>
    </div>
  ),
}));

jest.mock('../NewConversationTab', () => ({
  NewConversationTab: ({ onComplete }: { onComplete: () => void }) => (
    <div data-testid="new-conversation-tab">
      <button data-testid="complete-btn" onClick={onComplete}>Done</button>
    </div>
  ),
}));

const mockedUseChatWindow = useChatWindow as jest.Mock;

const createMockTab = (overrides: Partial<{ id: string; conversationId: string; agentId: string; agentName: string; title: string; unreadCount: number; createdAt: number }> = {}) => ({
  id: 'tab-1',
  conversationId: 'conv-1',
  agentId: 'agent-1',
  agentName: 'Agent 1',
  title: 'Chat 1',
  unreadCount: 0,
  createdAt: Date.now(),
  ...overrides,
});

const createMockState = (overrides: Partial<ChatWindowState> = {}): ChatWindowState => ({
  mode: 'floating',
  tabs: [createMockTab()],
  activeTabId: 'tab-1',
  floatingPosition: { x: 100, y: 100 },
  floatingSize: { width: 420, height: 520 },
  ...overrides,
});

describe('ChatWindow', () => {
  let mockDispatch: jest.Mock<void, [ChatWindowAction]>;

  beforeEach(() => {
    mockDispatch = jest.fn();
    mockedUseChatWindow.mockReturnValue({
      state: createMockState(),
      dispatch: mockDispatch,
      openConversation: jest.fn(),
      closeTab: jest.fn(),
      switchTab: jest.fn(),
      setMode: jest.fn(),
      isDetachedMode: false,
    });
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  it('renders active tab conversation component', () => {
    render(<ChatWindow />);
    expect(screen.getByTestId('conversation-conv-1')).toBeInTheDocument();
  });

  it('renders header and tabs', () => {
    render(<ChatWindow />);
    expect(screen.getByTestId('chat-header')).toBeInTheDocument();
    expect(screen.getByTestId('chat-tabs')).toBeInTheDocument();
  });

  it('shows NewConversationTab when no tabs', () => {
    mockedUseChatWindow.mockReturnValue({
      state: createMockState({ tabs: [], activeTabId: null }),
      dispatch: mockDispatch,
      openConversation: jest.fn(),
      closeTab: jest.fn(),
      switchTab: jest.fn(),
      setMode: jest.fn(),
      isDetachedMode: false,
    });

    render(<ChatWindow />);
    expect(screen.getByTestId('new-conversation-tab')).toBeInTheDocument();
  });

  it('toggles new conversation overlay when + button clicked', () => {
    render(<ChatWindow />);

    // Initially no new conversation tab (has tabs, showNewTab is false)
    expect(screen.queryByTestId('new-conversation-tab')).not.toBeInTheDocument();

    // Click + to show new tab overlay
    fireEvent.click(screen.getByTestId('new-tab-btn'));
    expect(screen.getByTestId('new-conversation-tab')).toBeInTheDocument();
  });

  it('hides new conversation overlay when onComplete is called', () => {
    render(<ChatWindow />);

    // Open the overlay
    fireEvent.click(screen.getByTestId('new-tab-btn'));
    expect(screen.getByTestId('new-conversation-tab')).toBeInTheDocument();

    // Complete dismisses it
    fireEvent.click(screen.getByTestId('complete-btn'));
    expect(screen.queryByTestId('new-conversation-tab')).not.toBeInTheDocument();
  });

  it('dispatches INCREMENT_UNREAD when onNewMessage fires', () => {
    render(<ChatWindow />);
    fireEvent.click(screen.getByTestId('new-message-btn'));
    expect(mockDispatch).toHaveBeenCalledWith({ type: 'INCREMENT_UNREAD', payload: 'tab-1' });
  });

  it('hides inactive tabs', () => {
    const tabs = [
      createMockTab({ id: 'tab-1', conversationId: 'conv-1' }),
      createMockTab({ id: 'tab-2', conversationId: 'conv-2', agentName: 'Agent 2', title: 'Chat 2' }),
    ];
    mockedUseChatWindow.mockReturnValue({
      state: createMockState({ tabs, activeTabId: 'tab-1' }),
      dispatch: mockDispatch,
      openConversation: jest.fn(),
      closeTab: jest.fn(),
      switchTab: jest.fn(),
      setMode: jest.fn(),
      isDetachedMode: false,
    });

    render(<ChatWindow />);
    const activeConv = screen.getByTestId('conversation-conv-1');
    const inactiveConv = screen.getByTestId('conversation-conv-2');

    expect(activeConv.parentElement).toHaveClass('h-full');
    expect(inactiveConv.parentElement).toHaveClass('hidden');
  });
});
