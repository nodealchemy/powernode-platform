import { render, screen } from '@testing-library/react';
import { ChatWindowFloating } from '../ChatWindowFloating';
import { useChatWindow } from '../../context/ChatWindowContext';
import type { ChatWindowState } from '../../context/chatWindowTypes';

jest.mock('../../context/ChatWindowContext', () => ({
  useChatWindow: jest.fn(),
}));

jest.mock('../ChatWindow', () => ({
  ChatWindow: ({ onDragStart }: { onDragStart?: (e: React.PointerEvent) => void }) => (
    <div data-testid="chat-window" onPointerDown={onDragStart} />
  ),
}));

// Mock ResizeObserver
const mockObserve = jest.fn();
const mockDisconnect = jest.fn();

class MockResizeObserver {
  observe = mockObserve;
  unobserve = jest.fn();
  disconnect = mockDisconnect;
  constructor(_cb: ResizeObserverCallback) {
    // store callback if needed
  }
}

beforeAll(() => {
  global.ResizeObserver = MockResizeObserver as unknown as typeof ResizeObserver;
});

const mockedUseChatWindow = useChatWindow as jest.Mock;

const createMockState = (overrides: Partial<ChatWindowState> = {}): ChatWindowState => ({
  mode: 'floating',
  preferredOpenMode: 'floating',
  tabs: [],
  activeTabId: null,
  floatingPosition: { x: 200, y: 150 },
  floatingSize: { width: 420, height: 520 },
  showSidebar: true,
  panels: [{ id: 'panel-1', tabIds: [], activeTabId: null }],
  activePanelId: 'panel-1',
  panelSizes: [100],
  ...overrides,
});

describe('ChatWindowFloating', () => {
  beforeEach(() => {
    mockedUseChatWindow.mockReturnValue({
      state: createMockState(),
      dispatch: jest.fn(),
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

  it('renders with fixed positioning', () => {
    const { container } = render(<ChatWindowFloating />);
    const wrapper = container.firstChild as HTMLElement;
    expect(wrapper).toHaveClass('fixed');
  });

  it('contains ChatWindow component', () => {
    render(<ChatWindowFloating />);
    expect(screen.getByTestId('chat-window')).toBeInTheDocument();
  });

  it('has resize CSS property', () => {
    const { container } = render(<ChatWindowFloating />);
    const wrapper = container.firstChild as HTMLElement;
    expect(wrapper.style.resize).toBe('both');
  });

  it('applies position from state', () => {
    mockedUseChatWindow.mockReturnValue({
      state: createMockState({ floatingPosition: { x: 300, y: 250 } }),
      dispatch: jest.fn(),
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

    const { container } = render(<ChatWindowFloating />);
    const wrapper = container.firstChild as HTMLElement;
    expect(wrapper.style.left).toBe('300px');
    expect(wrapper.style.top).toBe('250px');
  });

  it('applies size from state', () => {
    const { container } = render(<ChatWindowFloating />);
    const wrapper = container.firstChild as HTMLElement;
    expect(wrapper.style.width).toBe('420px');
    expect(wrapper.style.height).toBe('520px');
  });

  it('sets up ResizeObserver', () => {
    render(<ChatWindowFloating />);
    expect(mockObserve).toHaveBeenCalled();
  });
});
