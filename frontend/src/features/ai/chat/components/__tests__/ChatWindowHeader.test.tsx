import { render, screen, fireEvent } from '@testing-library/react';
import { ChatWindowHeader } from '../ChatWindowHeader';
import { useChatWindow } from '../../context/ChatWindowContext';
import type { ChatWindowState, ChatWindowMode } from '../../context/chatWindowTypes';

jest.mock('../../context/ChatWindowContext', () => ({
  useChatWindow: jest.fn(),
}));

jest.mock('@/shared/services/ai', () => ({
  conversationsApi: {
    pinConversation: jest.fn(),
    unpinConversation: jest.fn(),
    archiveConversation: jest.fn(),
    deleteConversation: jest.fn(),
  },
}));

jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: jest.fn() }),
}));

const mockedUseChatWindow = useChatWindow as jest.Mock;

const createMockTab = (overrides: Partial<{ id: string; conversationId: string; agentId: string; agentName: string; title: string; unreadCount: number; createdAt: number }> = {}) => ({
  id: 'tab-1',
  conversationId: 'conv-1',
  agentId: 'agent-1',
  agentName: 'Test Agent',
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
  showSidebar: true,
  panels: [{ id: 'panel-1', tabIds: ['tab-1'], activeTabId: 'tab-1' }],
  activePanelId: 'panel-1',
  panelSizes: [100],
  ...overrides,
});

const setupMock = (
  stateOverrides: Partial<ChatWindowState> = {},
  options: { isDetachedMode?: boolean } = {}
) => {
  const mockSetMode = jest.fn<void, [ChatWindowMode]>();
  mockedUseChatWindow.mockReturnValue({
    state: createMockState(stateOverrides),
    setMode: mockSetMode,
    isDetachedMode: options.isDetachedMode ?? false,
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
  });
  return { mockSetMode };
};

describe('ChatWindowHeader', () => {
  afterEach(() => {
    jest.clearAllMocks();
  });

  it('renders agent name from active tab', () => {
    setupMock();
    render(<ChatWindowHeader />);
    expect(screen.getByText('Test Agent')).toBeInTheDocument();
  });

  it('shows "AI Chat" when no active tab', () => {
    setupMock({ tabs: [], activeTabId: null });
    render(<ChatWindowHeader />);
    expect(screen.getByText('AI Chat')).toBeInTheDocument();
  });

  it('shows maximize button in floating mode', () => {
    setupMock({ mode: 'floating' });
    render(<ChatWindowHeader />);
    expect(screen.getByTitle('Maximize')).toBeInTheDocument();
  });

  it('clicking maximize calls setMode("maximized")', () => {
    const { mockSetMode } = setupMock({ mode: 'floating' });
    render(<ChatWindowHeader />);
    fireEvent.click(screen.getByTitle('Maximize'));
    expect(mockSetMode).toHaveBeenCalledWith('maximized');
  });

  it('shows restore button in maximized mode', () => {
    setupMock({ mode: 'maximized' });
    render(<ChatWindowHeader />);
    expect(screen.getByTitle('Restore')).toBeInTheDocument();
  });

  it('clicking restore calls setMode("floating")', () => {
    const { mockSetMode } = setupMock({ mode: 'maximized' });
    render(<ChatWindowHeader />);
    fireEvent.click(screen.getByTitle('Restore'));
    expect(mockSetMode).toHaveBeenCalledWith('floating');
  });

  it('shows pop-out button in non-detached modes', () => {
    setupMock({ mode: 'floating' });
    render(<ChatWindowHeader />);
    expect(screen.getByTitle('Pop out')).toBeInTheDocument();
  });

  it('clicking pop-out calls setMode("detached")', () => {
    const { mockSetMode } = setupMock({ mode: 'floating' });
    render(<ChatWindowHeader />);
    fireEvent.click(screen.getByTitle('Pop out'));
    expect(mockSetMode).toHaveBeenCalledWith('detached');
  });

  it('close button calls setMode("closed")', () => {
    const { mockSetMode } = setupMock({ mode: 'floating' });
    render(<ChatWindowHeader />);
    fireEvent.click(screen.getByTitle('Close'));
    expect(mockSetMode).toHaveBeenCalledWith('closed');
  });

  it('in detached mode shows dock button that calls setMode("floating")', () => {
    const { mockSetMode } = setupMock({ mode: 'floating' }, { isDetachedMode: true });
    render(<ChatWindowHeader />);

    const dockBtn = screen.getByTitle('Dock to main window');
    expect(dockBtn).toBeInTheDocument();

    fireEvent.click(dockBtn);
    expect(mockSetMode).toHaveBeenCalledWith('floating');
  });

  it('in detached mode does not show maximize or pop-out buttons', () => {
    setupMock({ mode: 'floating' }, { isDetachedMode: true });
    render(<ChatWindowHeader />);

    expect(screen.queryByTitle('Maximize')).not.toBeInTheDocument();
    expect(screen.queryByTitle('Pop out')).not.toBeInTheDocument();
  });

  it('renders online indicator dot', () => {
    setupMock();
    const { container } = render(<ChatWindowHeader />);
    const dot = container.querySelector('.bg-theme-success');
    expect(dot).toBeInTheDocument();
  });
});
