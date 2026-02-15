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

jest.mock('../NewConversationTab', () => ({
  NewConversationTab: ({ onComplete }: { onComplete: () => void }) => (
    <div data-testid="new-conversation-tab">
      <button data-testid="complete-btn" onClick={onComplete}>Done</button>
    </div>
  ),
}));

jest.mock('../ChatWindowSidebar', () => ({
  ChatWindowSidebar: () => <div data-testid="chat-sidebar" />,
}));

jest.mock('../SplitPanelContainer', () => ({
  SplitPanelContainer: () => <div data-testid="split-panel-container" />,
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
  preferredOpenMode: 'floating',
  tabs: [createMockTab()],
  activeTabId: 'tab-1',
  floatingPosition: { x: 100, y: 100 },
  floatingSize: { width: 420, height: 520 },
  showSidebar: false,
  panels: [{ id: 'panel-1', tabIds: ['tab-1'], activeTabId: 'tab-1' }],
  activePanelId: 'panel-1',
  panelSizes: [100],
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
      openConversationMaximized: jest.fn(),
      closeTab: jest.fn(),
      switchTab: jest.fn(),
      setMode: jest.fn(),
      toggleSidebar: jest.fn(),
      createSplit: jest.fn(),
      moveTabToPanel: jest.fn(),
      closePanel: jest.fn(),
      setActivePanelId: jest.fn(),
      setPanelSizes: jest.fn(),
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

  it('renders header', () => {
    render(<ChatWindow />);
    expect(screen.getByTestId('chat-header')).toBeInTheDocument();
  });

  it('shows NewConversationTab when no tabs', () => {
    mockedUseChatWindow.mockReturnValue({
      state: createMockState({ tabs: [], activeTabId: null }),
      dispatch: mockDispatch,
      openConversation: jest.fn(),
      openConversationMaximized: jest.fn(),
      closeTab: jest.fn(),
      switchTab: jest.fn(),
      setMode: jest.fn(),
      toggleSidebar: jest.fn(),
      createSplit: jest.fn(),
      moveTabToPanel: jest.fn(),
      closePanel: jest.fn(),
      setActivePanelId: jest.fn(),
      setPanelSizes: jest.fn(),
      isDetachedMode: false,
    });

    render(<ChatWindow />);
    expect(screen.getByTestId('new-conversation-tab')).toBeInTheDocument();
  });

  it('dispatches INCREMENT_UNREAD when onNewMessage fires', () => {
    render(<ChatWindow />);
    fireEvent.click(screen.getByTestId('new-message-btn'));
    expect(mockDispatch).toHaveBeenCalledWith({ type: 'INCREMENT_UNREAD', payload: 'tab-1' });
  });

  it('shows sidebar when showSidebar is true', () => {
    mockedUseChatWindow.mockReturnValue({
      state: createMockState({ showSidebar: true }),
      dispatch: mockDispatch,
      openConversation: jest.fn(),
      openConversationMaximized: jest.fn(),
      closeTab: jest.fn(),
      switchTab: jest.fn(),
      setMode: jest.fn(),
      toggleSidebar: jest.fn(),
      createSplit: jest.fn(),
      moveTabToPanel: jest.fn(),
      closePanel: jest.fn(),
      setActivePanelId: jest.fn(),
      setPanelSizes: jest.fn(),
      isDetachedMode: false,
    });

    render(<ChatWindow />);
    expect(screen.getByTestId('chat-sidebar')).toBeInTheDocument();
  });

  it('hides sidebar when showSidebar is false', () => {
    render(<ChatWindow />);
    expect(screen.queryByTestId('chat-sidebar')).not.toBeInTheDocument();
  });

  it('shows sidebar in floating mode when showSidebar is true', () => {
    mockedUseChatWindow.mockReturnValue({
      state: createMockState({ mode: 'floating', showSidebar: true }),
      dispatch: mockDispatch,
      openConversation: jest.fn(),
      openConversationMaximized: jest.fn(),
      closeTab: jest.fn(),
      switchTab: jest.fn(),
      setMode: jest.fn(),
      toggleSidebar: jest.fn(),
      createSplit: jest.fn(),
      moveTabToPanel: jest.fn(),
      closePanel: jest.fn(),
      setActivePanelId: jest.fn(),
      setPanelSizes: jest.fn(),
      isDetachedMode: false,
    });

    render(<ChatWindow />);
    expect(screen.getByTestId('chat-sidebar')).toBeInTheDocument();
  });

  it('renders SplitPanelContainer in maximized mode', () => {
    mockedUseChatWindow.mockReturnValue({
      state: createMockState({ mode: 'maximized' }),
      dispatch: mockDispatch,
      openConversation: jest.fn(),
      openConversationMaximized: jest.fn(),
      closeTab: jest.fn(),
      switchTab: jest.fn(),
      setMode: jest.fn(),
      toggleSidebar: jest.fn(),
      createSplit: jest.fn(),
      moveTabToPanel: jest.fn(),
      closePanel: jest.fn(),
      setActivePanelId: jest.fn(),
      setPanelSizes: jest.fn(),
      isDetachedMode: false,
    });

    render(<ChatWindow />);
    expect(screen.getByTestId('split-panel-container')).toBeInTheDocument();
  });
});
