import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { Provider } from 'react-redux';
import { BrowserRouter } from 'react-router-dom';
import { configureStore } from '@reduxjs/toolkit';
import { Sidebar } from './Sidebar';
import authReducer from '@/shared/services/slices/authSlice';
import uiReducer from '@/shared/services/slices/uiSlice';

// Mock navigation context
const mockUpdateState = jest.fn();
let mockIsCollapsed = false;

const mockNavigationConfig = {
  items: [
    { id: 'dashboard', label: 'Dashboard', href: '/app/dashboard', icon: () => <span>D</span>, order: 1 },
    { id: 'users', label: 'Users', href: '/app/users', icon: () => <span>U</span>, order: 2 },
  ],
  sections: [
    {
      id: 'admin',
      label: 'Administration',
      items: [
        { id: 'settings', label: 'Settings', href: '/app/settings' },
      ],
      order: 10,
    },
  ],
};

jest.mock('@/shared/hooks/NavigationContext', () => ({
  useNavigation: () => ({
    config: mockNavigationConfig,
    state: {
      isCollapsed: mockIsCollapsed,
      activeItemId: null,
      expandedSections: [],
    },
    updateState: mockUpdateState,
  }),
}));

// Mock NavigationItem
jest.mock('./NavigationItem', () => ({
  NavigationItem: ({ item, isCollapsed }: { item: { label: string; id: string }; isCollapsed: boolean }) => (
    <div data-testid={`nav-item-${item.id}`} data-collapsed={isCollapsed}>
      {item.label}
    </div>
  ),
}));

// Mock NavigationSection
jest.mock('./NavigationSection', () => ({
  NavigationSection: ({ section, isCollapsed }: { section: { label: string; id: string }; isCollapsed: boolean }) => (
    <div data-testid={`nav-section-${section.id}`} data-collapsed={isCollapsed}>
      {section.label}
    </div>
  ),
}));

// Mock VersionDisplay
jest.mock('../ui/VersionDisplay', () => ({
  VersionDisplay: () => <span data-testid="version-display">v1.0.0</span>,
}));

// Mock settingsApi
const mockGetCopyright = jest.fn();
jest.mock('@/shared/services/settingsApi', () => ({
  settingsApi: {
    getCopyright: () => mockGetCopyright(),
  },
}));

// Create test store
const createTestStore = () => {
  return configureStore({
    reducer: {
      auth: authReducer,
      ui: uiReducer,
    },
    preloadedState: {
      auth: {
        user: null,
        access_token: null,
        refresh_token: null,
        isLoading: false,
        isAuthenticated: false,
        error: null,
        resendingVerification: false,
        resendVerificationSuccess: false,
        resendCooldown: 0,
        impersonation: {
          isImpersonating: false,
          originalUser: null,
          impersonatedUser: null,
          sessionId: null,
          startedAt: null,
          expiresAt: null,
        },
      },
      ui: {
        sidebarOpen: true,
        sidebarCollapsed: false,
        theme: 'light' as const,
        loading: false,
        notifications: [],
      },
    },
  });
};

// Custom render function for Sidebar
const renderSidebar = (props = { isOpen: true, onToggle: jest.fn() }) => {
  const store = createTestStore();
  return {
    ...render(
      <Provider store={store}>
        <BrowserRouter
          future={{
            v7_startTransition: true,
            v7_relativeSplatPath: true,
          }}
        >
          <Sidebar {...props} />
        </BrowserRouter>
      </Provider>
    ),
    store,
  };
};

describe('Sidebar', () => {
  const defaultProps = {
    isOpen: true,
    onToggle: jest.fn(),
  };

  beforeEach(() => {
    jest.clearAllMocks();
    mockGetCopyright.mockResolvedValue('© 2025 Test Company');
    mockIsCollapsed = false;
  });

  describe('rendering', () => {
    it('renders sidebar with logo', () => {
      renderSidebar(defaultProps);

      expect(screen.getByText('P')).toBeInTheDocument();
      expect(screen.getByText('Powernode')).toBeInTheDocument();
    });

    it('renders navigation items', () => {
      renderSidebar(defaultProps);

      expect(screen.getByTestId('nav-item-dashboard')).toBeInTheDocument();
      expect(screen.getByTestId('nav-item-users')).toBeInTheDocument();
    });

    it('renders navigation sections', () => {
      renderSidebar(defaultProps);

      expect(screen.getByTestId('nav-section-admin')).toBeInTheDocument();
    });

    it('renders version display in footer', () => {
      renderSidebar(defaultProps);

      expect(screen.getByTestId('version-display')).toBeInTheDocument();
    });
  });

  describe('copyright text', () => {
    it('loads and displays copyright text', async () => {
      renderSidebar(defaultProps);

      await waitFor(() => {
        expect(screen.getByText('© 2025 Test Company')).toBeInTheDocument();
      });
    });

    it('displays fallback copyright on API error', async () => {
      mockGetCopyright.mockRejectedValue(new Error('API Error'));

      renderSidebar(defaultProps);

      await waitFor(() => {
        expect(screen.getByText(/© \d{4} Everett C. Haimes III/)).toBeInTheDocument();
      });
    });
  });

  describe('open/closed state', () => {
    it('applies translate-x-0 when open', () => {
      const { container } = renderSidebar(defaultProps);

      const sidebar = container.querySelector('.translate-x-0');
      expect(sidebar).toBeInTheDocument();
    });

    it('applies -translate-x-full when closed', () => {
      const props = { ...defaultProps, isOpen: false };

      const { container } = renderSidebar(props);

      const sidebar = container.querySelector('.-translate-x-full');
      expect(sidebar).toBeInTheDocument();
    });

    it('shows mobile overlay when open', () => {
      const { container } = renderSidebar(defaultProps);

      const overlay = container.querySelector('.bg-black.bg-opacity-50');
      expect(overlay).toBeInTheDocument();
    });

    it('hides mobile overlay when closed', () => {
      const props = { ...defaultProps, isOpen: false };

      const { container } = renderSidebar(props);

      const overlay = container.querySelector('.bg-black.bg-opacity-50');
      expect(overlay).not.toBeInTheDocument();
    });
  });

  describe('mobile interactions', () => {
    it('calls onToggle when overlay clicked', () => {
      const onToggle = jest.fn();
      const { container } = renderSidebar({ ...defaultProps, onToggle });

      const overlay = container.querySelector('.bg-black.bg-opacity-50');
      if (overlay) {
        fireEvent.click(overlay);
        expect(onToggle).toHaveBeenCalledTimes(1);
      }
    });
  });

  describe('collapse toggle', () => {
    it('renders collapse toggle button', () => {
      renderSidebar(defaultProps);

      const collapseButton = screen.getByTitle('Collapse sidebar');
      expect(collapseButton).toBeInTheDocument();
    });

    it('calls updateState when collapse button clicked', () => {
      renderSidebar(defaultProps);

      const collapseButton = screen.getByTitle('Collapse sidebar');
      fireEvent.click(collapseButton);

      expect(mockUpdateState).toHaveBeenCalledWith({ isCollapsed: true });
    });
  });

  describe('collapsed state', () => {
    beforeEach(() => {
      mockIsCollapsed = true;
    });

    it('applies w-16 class when collapsed', () => {
      const { container } = renderSidebar(defaultProps);

      const sidebar = container.querySelector('.w-16');
      expect(sidebar).toBeInTheDocument();
    });

    it('hides Powernode text when collapsed', () => {
      renderSidebar(defaultProps);

      expect(screen.queryByText('Powernode')).not.toBeInTheDocument();
    });

    it('hides footer when collapsed', () => {
      renderSidebar(defaultProps);

      expect(screen.queryByTestId('version-display')).not.toBeInTheDocument();
    });

    it('passes isCollapsed to navigation items', () => {
      renderSidebar(defaultProps);

      const navItem = screen.getByTestId('nav-item-dashboard');
      expect(navItem).toHaveAttribute('data-collapsed', 'true');
    });

    it('passes isCollapsed to navigation sections', () => {
      renderSidebar(defaultProps);

      const navSection = screen.getByTestId('nav-section-admin');
      expect(navSection).toHaveAttribute('data-collapsed', 'true');
    });

    it('shows "Expand sidebar" title when collapsed', () => {
      renderSidebar(defaultProps);

      const expandButton = screen.getByTitle('Expand sidebar');
      expect(expandButton).toBeInTheDocument();
    });
  });

  describe('expanded state', () => {
    it('applies w-64 class when expanded', () => {
      const { container } = renderSidebar(defaultProps);

      const sidebar = container.querySelector('.w-64');
      expect(sidebar).toBeInTheDocument();
    });

    it('shows Powernode text when expanded', () => {
      renderSidebar(defaultProps);

      expect(screen.getByText('Powernode')).toBeInTheDocument();
    });

    it('passes isCollapsed=false to navigation items', () => {
      renderSidebar(defaultProps);

      const navItem = screen.getByTestId('nav-item-dashboard');
      expect(navItem).toHaveAttribute('data-collapsed', 'false');
    });
  });

  describe('keyboard shortcuts', () => {
    it('toggles collapse on Ctrl+B', () => {
      renderSidebar(defaultProps);

      fireEvent.keyDown(window, { key: 'b', ctrlKey: true });

      expect(mockUpdateState).toHaveBeenCalledWith({ isCollapsed: true });
    });

    it('toggles collapse on Cmd+B (Mac)', () => {
      renderSidebar(defaultProps);

      fireEvent.keyDown(window, { key: 'b', metaKey: true });

      expect(mockUpdateState).toHaveBeenCalledWith({ isCollapsed: true });
    });

    it('does not toggle collapse on regular B key', () => {
      renderSidebar(defaultProps);

      fireEvent.keyDown(window, { key: 'b' });

      expect(mockUpdateState).not.toHaveBeenCalled();
    });
  });

  describe('navigation item ordering', () => {
    it('sorts navigation items by order', () => {
      renderSidebar(defaultProps);

      const dashboardItem = screen.getByTestId('nav-item-dashboard');
      const usersItem = screen.getByTestId('nav-item-users');

      // Dashboard (order: 1) should appear before Users (order: 2)
      expect(dashboardItem.compareDocumentPosition(usersItem)).toBe(
        Node.DOCUMENT_POSITION_FOLLOWING
      );
    });
  });

  describe('logo', () => {
    it('renders logo icon', () => {
      renderSidebar(defaultProps);

      const logoIcon = screen.getByText('P');
      expect(logoIcon).toBeInTheDocument();
      expect(logoIcon).toHaveClass('text-white', 'font-bold');
    });
  });
});
