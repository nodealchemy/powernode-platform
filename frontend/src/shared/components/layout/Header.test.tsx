import { screen, fireEvent, waitFor } from '@testing-library/react';
import { Header } from './Header';
import { renderWithProviders, mockAuthenticatedState } from '@/shared/utils/test-utils';
import { PERMISSIONS } from '@/shared/constants/permissions';

// Mock WebSocketStatusIndicator
jest.mock('../ui/WebSocketStatusIndicator', () => ({
  WebSocketStatusIndicator: () => <div data-testid="websocket-status">WebSocket Status</div>,
}));

// Mock ThemeToggle
jest.mock('../ui/ThemeToggle', () => ({
  ThemeToggle: () => <button data-testid="theme-toggle">Theme Toggle</button>,
}));

// Mock getUserInitials
jest.mock('@/shared/utils/userUtils', () => ({
  getUserInitials: (user: { name?: string } | null) => {
    if (!user?.name) return '??';
    return user.name.split(' ').map(n => n[0]).join('').toUpperCase().slice(0, 2);
  },
}));

describe('Header', () => {
  const mockUser = {
    id: '123',
    email: 'test@example.com',
    name: 'John Doe',
    permissions: ['users.read', 'users.create'],
    roles: ['account.member'],
    status: 'active',
    email_verified: true,
    account: {
      id: '456',
      name: 'Test Company',
      status: 'active',
    },
  };

  const mockAdminUser = {
    ...mockUser,
    permissions: [...mockUser.permissions, PERMISSIONS.ADMIN.ACCESS],
  };

  const defaultProps = {
    user: mockUser,
    onLogout: jest.fn(),
    onToggleSidebar: jest.fn(),
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('rendering', () => {
    it('renders header element', () => {
      renderWithProviders(<Header {...defaultProps} />, {
        preloadedState: mockAuthenticatedState,
      });

      expect(screen.getByRole('banner')).toBeInTheDocument();
    });

    it('renders WebSocket status indicator', () => {
      renderWithProviders(<Header {...defaultProps} />, {
        preloadedState: mockAuthenticatedState,
      });

      expect(screen.getByTestId('websocket-status')).toBeInTheDocument();
    });

    it('renders theme toggle', () => {
      renderWithProviders(<Header {...defaultProps} />, {
        preloadedState: mockAuthenticatedState,
      });

      expect(screen.getByTestId('theme-toggle')).toBeInTheDocument();
    });

    it('renders user initials', () => {
      renderWithProviders(<Header {...defaultProps} />, {
        preloadedState: mockAuthenticatedState,
      });

      // User initials should be displayed (JD for John Doe)
      expect(screen.getAllByText('JD').length).toBeGreaterThan(0);
    });

    it('renders user name (hidden on mobile)', () => {
      renderWithProviders(<Header {...defaultProps} />, {
        preloadedState: mockAuthenticatedState,
      });

      // Name is hidden on mobile but present in DOM
      expect(screen.getByText('John Doe')).toBeInTheDocument();
    });

    it('renders account name', () => {
      renderWithProviders(<Header {...defaultProps} />, {
        preloadedState: mockAuthenticatedState,
      });

      expect(screen.getByText('Test Company')).toBeInTheDocument();
    });

    it('renders sidebar toggle button on mobile', () => {
      renderWithProviders(<Header {...defaultProps} />, {
        preloadedState: mockAuthenticatedState,
      });

      const toggleButton = screen.getByTitle('Toggle sidebar');
      expect(toggleButton).toBeInTheDocument();
    });
  });

  describe('sidebar toggle', () => {
    it('calls onToggleSidebar when toggle button clicked', () => {
      renderWithProviders(<Header {...defaultProps} />, {
        preloadedState: mockAuthenticatedState,
      });

      const toggleButton = screen.getByTitle('Toggle sidebar');
      fireEvent.click(toggleButton);

      expect(defaultProps.onToggleSidebar).toHaveBeenCalledTimes(1);
    });
  });

  describe('user menu', () => {
    it('does not show dropdown menu initially', () => {
      renderWithProviders(<Header {...defaultProps} />, {
        preloadedState: mockAuthenticatedState,
      });

      expect(screen.queryByText('My Profile')).not.toBeInTheDocument();
    });

    it('shows dropdown menu when user button clicked', () => {
      renderWithProviders(<Header {...defaultProps} />, {
        preloadedState: mockAuthenticatedState,
      });

      const userButton = screen.getByRole('button', { expanded: false });
      fireEvent.click(userButton);

      expect(screen.getByText('My Profile')).toBeInTheDocument();
      expect(screen.getByText('Account Settings')).toBeInTheDocument();
      expect(screen.getByText('Team Invitations')).toBeInTheDocument();
    });

    it('toggles dropdown menu on click', () => {
      renderWithProviders(<Header {...defaultProps} />, {
        preloadedState: mockAuthenticatedState,
      });

      const userButton = screen.getByRole('button', { expanded: false });

      // Open menu
      fireEvent.click(userButton);
      expect(screen.getByText('My Profile')).toBeInTheDocument();

      // Close menu
      fireEvent.click(userButton);
      expect(screen.queryByText('My Profile')).not.toBeInTheDocument();
    });

    it('displays user email in dropdown', () => {
      renderWithProviders(<Header {...defaultProps} />, {
        preloadedState: mockAuthenticatedState,
      });

      const userButton = screen.getByRole('button', { expanded: false });
      fireEvent.click(userButton);

      expect(screen.getByText('test@example.com')).toBeInTheDocument();
    });

    it('renders account section header', () => {
      renderWithProviders(<Header {...defaultProps} />, {
        preloadedState: mockAuthenticatedState,
      });

      const userButton = screen.getByRole('button', { expanded: false });
      fireEvent.click(userButton);

      expect(screen.getByText('Account')).toBeInTheDocument();
    });

    it('renders support section', () => {
      renderWithProviders(<Header {...defaultProps} />, {
        preloadedState: mockAuthenticatedState,
      });

      const userButton = screen.getByRole('button', { expanded: false });
      fireEvent.click(userButton);

      expect(screen.getByText('Support')).toBeInTheDocument();
      expect(screen.getByText('Help & Support')).toBeInTheDocument();
    });
  });

  describe('navigation links', () => {
    it('links to profile page', () => {
      renderWithProviders(<Header {...defaultProps} />, {
        preloadedState: mockAuthenticatedState,
      });

      const userButton = screen.getByRole('button', { expanded: false });
      fireEvent.click(userButton);

      const profileLink = screen.getByText('My Profile').closest('a');
      expect(profileLink).toHaveAttribute('href', '/app/account/profile');
    });

    it('links to account settings', () => {
      renderWithProviders(<Header {...defaultProps} />, {
        preloadedState: mockAuthenticatedState,
      });

      const userButton = screen.getByRole('button', { expanded: false });
      fireEvent.click(userButton);

      const settingsLink = screen.getByText('Account Settings').closest('a');
      expect(settingsLink).toHaveAttribute('href', '/app/account/settings');
    });

    it('links to team invitations', () => {
      renderWithProviders(<Header {...defaultProps} />, {
        preloadedState: mockAuthenticatedState,
      });

      const userButton = screen.getByRole('button', { expanded: false });
      fireEvent.click(userButton);

      const invitationsLink = screen.getByText('Team Invitations').closest('a');
      expect(invitationsLink).toHaveAttribute('href', '/app/account/invitations');
    });

    it('links to customer management', () => {
      renderWithProviders(<Header {...defaultProps} />, {
        preloadedState: mockAuthenticatedState,
      });

      const userButton = screen.getByRole('button', { expanded: false });
      fireEvent.click(userButton);

      const businessLink = screen.getByText('Customer Management').closest('a');
      expect(businessLink).toHaveAttribute('href', '/app/business');
    });
  });

  describe('admin access', () => {
    it('does not show admin section for non-admin users', () => {
      renderWithProviders(<Header {...defaultProps} />, {
        preloadedState: mockAuthenticatedState,
      });

      const userButton = screen.getByRole('button', { expanded: false });
      fireEvent.click(userButton);

      expect(screen.queryByText('Administration')).not.toBeInTheDocument();
      expect(screen.queryByText('Admin Settings')).not.toBeInTheDocument();
    });

    it('shows admin section for users with admin access', () => {
      const props = {
        ...defaultProps,
        user: mockAdminUser,
      };

      renderWithProviders(<Header {...props} />, {
        preloadedState: mockAuthenticatedState,
      });

      const userButton = screen.getByRole('button', { expanded: false });
      fireEvent.click(userButton);

      expect(screen.getByText('Administration')).toBeInTheDocument();
      expect(screen.getByText('Admin Settings')).toBeInTheDocument();
      expect(screen.getByText('Users')).toBeInTheDocument();
    });

    it('links to admin settings for admin users', () => {
      const props = {
        ...defaultProps,
        user: mockAdminUser,
      };

      renderWithProviders(<Header {...props} />, {
        preloadedState: mockAuthenticatedState,
      });

      const userButton = screen.getByRole('button', { expanded: false });
      fireEvent.click(userButton);

      const adminLink = screen.getByText('Admin Settings').closest('a');
      expect(adminLink).toHaveAttribute('href', '/app/system/admin');
    });

    it('links to users page for admin users', () => {
      const props = {
        ...defaultProps,
        user: mockAdminUser,
      };

      renderWithProviders(<Header {...props} />, {
        preloadedState: mockAuthenticatedState,
      });

      const userButton = screen.getByRole('button', { expanded: false });
      fireEvent.click(userButton);

      const usersLink = screen.getByText('Users').closest('a');
      expect(usersLink).toHaveAttribute('href', '/app/account/users');
    });
  });

  describe('logout', () => {
    it('renders sign out button', () => {
      renderWithProviders(<Header {...defaultProps} />, {
        preloadedState: mockAuthenticatedState,
      });

      const userButton = screen.getByRole('button', { expanded: false });
      fireEvent.click(userButton);

      expect(screen.getByText('Sign Out')).toBeInTheDocument();
    });

    it('calls onLogout when sign out clicked', () => {
      renderWithProviders(<Header {...defaultProps} />, {
        preloadedState: mockAuthenticatedState,
      });

      const userButton = screen.getByRole('button', { expanded: false });
      fireEvent.click(userButton);

      const signOutButton = screen.getByText('Sign Out');
      fireEvent.click(signOutButton);

      expect(defaultProps.onLogout).toHaveBeenCalledTimes(1);
    });

    it('closes menu when sign out clicked', () => {
      renderWithProviders(<Header {...defaultProps} />, {
        preloadedState: mockAuthenticatedState,
      });

      const userButton = screen.getByRole('button', { expanded: false });
      fireEvent.click(userButton);

      const signOutButton = screen.getByText('Sign Out');
      fireEvent.click(signOutButton);

      // Menu should be closed
      expect(screen.queryByText('My Profile')).not.toBeInTheDocument();
    });
  });

  describe('click outside behavior', () => {
    it('closes dropdown when clicking outside', async () => {
      renderWithProviders(
        <div>
          <Header {...defaultProps} />
          <div data-testid="outside">Outside</div>
        </div>,
        { preloadedState: mockAuthenticatedState }
      );

      // Open dropdown
      const userButton = screen.getByRole('button', { expanded: false });
      fireEvent.click(userButton);
      expect(screen.getByText('My Profile')).toBeInTheDocument();

      // Click outside
      fireEvent.mouseDown(screen.getByTestId('outside'));

      await waitFor(() => {
        expect(screen.queryByText('My Profile')).not.toBeInTheDocument();
      });
    });
  });

  describe('accessibility', () => {
    it('has aria-expanded attribute on user button', () => {
      renderWithProviders(<Header {...defaultProps} />, {
        preloadedState: mockAuthenticatedState,
      });

      const userButton = screen.getByRole('button', { expanded: false });
      expect(userButton).toHaveAttribute('aria-expanded', 'false');

      fireEvent.click(userButton);
      expect(userButton).toHaveAttribute('aria-expanded', 'true');
    });

    it('has aria-haspopup attribute on user button', () => {
      renderWithProviders(<Header {...defaultProps} />, {
        preloadedState: mockAuthenticatedState,
      });

      const userButton = screen.getByRole('button', { expanded: false });
      expect(userButton).toHaveAttribute('aria-haspopup', 'true');
    });
  });

  describe('null user handling', () => {
    it('handles null user gracefully', () => {
      const props = {
        ...defaultProps,
        user: null,
      };

      renderWithProviders(<Header {...props} />, {
        preloadedState: mockAuthenticatedState,
      });

      // Should still render header
      expect(screen.getByRole('banner')).toBeInTheDocument();
    });

    it('shows loading text for account when user has no account', () => {
      const userWithoutAccount = {
        ...mockUser,
        account: undefined,
      };

      const props = {
        ...defaultProps,
        user: userWithoutAccount as any,
      };

      renderWithProviders(<Header {...props} />, {
        preloadedState: mockAuthenticatedState,
      });

      expect(screen.getByText('Loading...')).toBeInTheDocument();
    });
  });

  describe('menu item interactions', () => {
    it('closes menu when navigation link clicked', () => {
      renderWithProviders(<Header {...defaultProps} />, {
        preloadedState: mockAuthenticatedState,
      });

      const userButton = screen.getByRole('button', { expanded: false });
      fireEvent.click(userButton);

      const profileLink = screen.getByText('My Profile');
      fireEvent.click(profileLink);

      // Menu should close after clicking a link
      expect(screen.queryByText('Account Settings')).not.toBeInTheDocument();
    });
  });
});
