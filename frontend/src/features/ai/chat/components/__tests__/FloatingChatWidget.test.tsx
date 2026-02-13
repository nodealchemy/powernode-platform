import { render, screen, fireEvent } from '@testing-library/react';
import { Provider } from 'react-redux';
import { configureStore } from '@reduxjs/toolkit';
import { FloatingChatWidget } from '../FloatingChatWidget';
import { useChatWindow } from '../../context/ChatWindowContext';
import type { ChatWindowState, ChatWindowMode } from '../../context/chatWindowTypes';

jest.mock('../../context/ChatWindowContext', () => ({
  useChatWindow: jest.fn(),
}));

const mockedUseChatWindow = useChatWindow as jest.Mock;

interface MockUser {
  permissions: string[];
}

const createMockStore = (user: MockUser = { permissions: ['ai.conversations.create'] }) =>
  configureStore({
    reducer: {
      auth: () => ({ user }),
    },
  });

const createMockState = (overrides: Partial<ChatWindowState> = {}): ChatWindowState => ({
  mode: 'closed',
  tabs: [],
  activeTabId: null,
  floatingPosition: { x: -1, y: -1 },
  floatingSize: { width: 420, height: 520 },
  showSidebar: true,
  panels: [{ id: 'panel-1', tabIds: [], activeTabId: null }],
  activePanelId: 'panel-1',
  panelSizes: [100],
  ...overrides,
});

const renderWidget = (
  stateOverrides: Partial<ChatWindowState> = {},
  user?: MockUser
) => {
  const mockSetMode = jest.fn<void, [ChatWindowMode]>();
  mockedUseChatWindow.mockReturnValue({
    state: createMockState(stateOverrides),
    setMode: mockSetMode,
    dispatch: jest.fn(),
    openConversation: jest.fn(),
    openConversationMaximized: jest.fn(),
    closeTab: jest.fn(),
    switchTab: jest.fn(),
    toggleSidebar: jest.fn(),
    createSplit: jest.fn(),
    moveTabToPanel: jest.fn(),
    closePanel: jest.fn(),
    setActivePanelId: jest.fn(),
    setPanelSizes: jest.fn(),
    isDetachedMode: false,
  });

  const store = createMockStore(user);
  const result = render(
    <Provider store={store}>
      <FloatingChatWidget />
    </Provider>
  );

  return { ...result, mockSetMode };
};

describe('FloatingChatWidget', () => {
  afterEach(() => {
    jest.clearAllMocks();
  });

  it('renders when user has permission and mode is closed', () => {
    renderWidget({ mode: 'closed' });
    expect(screen.getByLabelText('Open AI Chat')).toBeInTheDocument();
  });

  it('hidden when missing permission', () => {
    renderWidget({ mode: 'closed' }, { permissions: [] });
    expect(screen.queryByLabelText('Open AI Chat')).not.toBeInTheDocument();
  });

  it('hidden when mode is floating', () => {
    renderWidget({ mode: 'floating' });
    expect(screen.queryByLabelText('Open AI Chat')).not.toBeInTheDocument();
  });

  it('hidden when mode is maximized', () => {
    renderWidget({ mode: 'maximized' });
    expect(screen.queryByLabelText('Open AI Chat')).not.toBeInTheDocument();
  });

  it('click calls setMode("floating")', () => {
    const { mockSetMode } = renderWidget({ mode: 'closed' });
    fireEvent.click(screen.getByLabelText('Open AI Chat'));
    expect(mockSetMode).toHaveBeenCalledWith('floating');
  });

  it('shows unread badge with count', () => {
    const tabs = [
      {
        id: 'tab-1',
        conversationId: 'conv-1',
        agentId: 'agent-1',
        agentName: 'Agent',
        title: 'Chat',
        unreadCount: 3,
        createdAt: Date.now(),
      },
      {
        id: 'tab-2',
        conversationId: 'conv-2',
        agentId: 'agent-2',
        agentName: 'Agent 2',
        title: 'Chat 2',
        unreadCount: 5,
        createdAt: Date.now(),
      },
    ];

    renderWidget({ mode: 'closed', tabs });
    expect(screen.getByText('8')).toBeInTheDocument();
  });

  it('badge caps at 99+', () => {
    const tabs = [
      {
        id: 'tab-1',
        conversationId: 'conv-1',
        agentId: 'agent-1',
        agentName: 'Agent',
        title: 'Chat',
        unreadCount: 100,
        createdAt: Date.now(),
      },
    ];

    renderWidget({ mode: 'closed', tabs });
    expect(screen.getByText('99+')).toBeInTheDocument();
  });

  it('no badge when unread count is 0', () => {
    renderWidget({ mode: 'closed', tabs: [] });
    const badge = screen.queryByText('0');
    expect(badge).not.toBeInTheDocument();
  });
});
