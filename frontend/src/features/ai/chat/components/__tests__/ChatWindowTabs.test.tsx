import { render, screen, fireEvent } from '@testing-library/react';
import { ChatWindowTabs } from '../ChatWindowTabs';
import { useChatWindow } from '../../context/ChatWindowContext';
import type { ChatWindowState, ChatTab } from '../../context/chatWindowTypes';

jest.mock('../../context/ChatWindowContext', () => ({
  useChatWindow: jest.fn(),
}));

const mockedUseChatWindow = useChatWindow as jest.Mock;

const createMockTab = (overrides: Partial<ChatTab> = {}): ChatTab => ({
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

const setupMock = (stateOverrides: Partial<ChatWindowState> = {}) => {
  const mockSwitchTab = jest.fn<void, [string]>();
  const mockCloseTab = jest.fn<void, [string]>();
  mockedUseChatWindow.mockReturnValue({
    state: createMockState(stateOverrides),
    switchTab: mockSwitchTab,
    closeTab: mockCloseTab,
    dispatch: jest.fn(),
    openConversation: jest.fn(),
    setMode: jest.fn(),
    isDetachedMode: false,
  });
  return { mockSwitchTab, mockCloseTab };
};

// jsdom doesn't implement scrollIntoView
beforeAll(() => {
  Element.prototype.scrollIntoView = jest.fn();
});

describe('ChatWindowTabs', () => {
  const onNewTab = jest.fn();

  afterEach(() => {
    jest.clearAllMocks();
  });

  it('returns null when only 1 tab', () => {
    setupMock({ tabs: [createMockTab()] });
    const { container } = render(<ChatWindowTabs onNewTab={onNewTab} />);
    expect(container.firstChild).toBeNull();
  });

  it('renders tabs for multiple conversations', () => {
    const tabs = [
      createMockTab({ id: 'tab-1', title: 'Chat 1' }),
      createMockTab({ id: 'tab-2', title: 'Chat 2', conversationId: 'conv-2' }),
    ];
    setupMock({ tabs, activeTabId: 'tab-1' });

    render(<ChatWindowTabs onNewTab={onNewTab} />);
    expect(screen.getByText('Chat 1')).toBeInTheDocument();
    expect(screen.getByText('Chat 2')).toBeInTheDocument();
  });

  it('active tab has highlight class', () => {
    const tabs = [
      createMockTab({ id: 'tab-1', title: 'Chat 1' }),
      createMockTab({ id: 'tab-2', title: 'Chat 2', conversationId: 'conv-2' }),
    ];
    setupMock({ tabs, activeTabId: 'tab-1' });

    render(<ChatWindowTabs onNewTab={onNewTab} />);

    const activeButton = screen.getByText('Chat 1').closest('button');
    expect(activeButton).toHaveClass('bg-theme-background');

    const inactiveButton = screen.getByText('Chat 2').closest('button');
    expect(inactiveButton).not.toHaveClass('bg-theme-background');
  });

  it('clicking tab calls switchTab', () => {
    const tabs = [
      createMockTab({ id: 'tab-1', title: 'Chat 1' }),
      createMockTab({ id: 'tab-2', title: 'Chat 2', conversationId: 'conv-2' }),
    ];
    const { mockSwitchTab } = setupMock({ tabs, activeTabId: 'tab-1' });

    render(<ChatWindowTabs onNewTab={onNewTab} />);
    fireEvent.click(screen.getByText('Chat 2'));
    expect(mockSwitchTab).toHaveBeenCalledWith('tab-2');
  });

  it('close button calls closeTab', () => {
    const tabs = [
      createMockTab({ id: 'tab-1', title: 'Chat 1' }),
      createMockTab({ id: 'tab-2', title: 'Chat 2', conversationId: 'conv-2' }),
    ];
    const { mockCloseTab } = setupMock({ tabs, activeTabId: 'tab-1' });

    render(<ChatWindowTabs onNewTab={onNewTab} />);

    const closeButtons = screen.getAllByTitle('Close tab');
    fireEvent.click(closeButtons[0]);
    expect(mockCloseTab).toHaveBeenCalledWith('tab-1');
  });

  it('+ button calls onNewTab', () => {
    const tabs = [
      createMockTab({ id: 'tab-1', title: 'Chat 1' }),
      createMockTab({ id: 'tab-2', title: 'Chat 2', conversationId: 'conv-2' }),
    ];
    setupMock({ tabs, activeTabId: 'tab-1' });

    render(<ChatWindowTabs onNewTab={onNewTab} />);
    fireEvent.click(screen.getByTitle('New conversation'));
    expect(onNewTab).toHaveBeenCalled();
  });

  it('shows unread badge on tab', () => {
    const tabs = [
      createMockTab({ id: 'tab-1', title: 'Chat 1', unreadCount: 5 }),
      createMockTab({ id: 'tab-2', title: 'Chat 2', conversationId: 'conv-2' }),
    ];
    setupMock({ tabs, activeTabId: 'tab-2' });

    render(<ChatWindowTabs onNewTab={onNewTab} />);
    expect(screen.getByText('5')).toBeInTheDocument();
  });

  it('caps unread badge at 99+', () => {
    const tabs = [
      createMockTab({ id: 'tab-1', title: 'Chat 1', unreadCount: 150 }),
      createMockTab({ id: 'tab-2', title: 'Chat 2', conversationId: 'conv-2' }),
    ];
    setupMock({ tabs, activeTabId: 'tab-2' });

    render(<ChatWindowTabs onNewTab={onNewTab} />);
    expect(screen.getByText('99+')).toBeInTheDocument();
  });
});
