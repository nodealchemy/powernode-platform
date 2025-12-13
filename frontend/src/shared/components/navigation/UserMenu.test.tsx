import { render, screen, fireEvent } from '@testing-library/react';
import { Provider } from 'react-redux';
import { BrowserRouter } from 'react-router-dom';
import { configureStore } from '@reduxjs/toolkit';
import { UserMenu } from './UserMenu';

// Mock navigation context
const mockUserMenuItems = [
  { id: 'profile', name: 'Profile', href: '/app/settings/profile', icon: 'P', description: 'Manage your profile' },
  { id: 'security', name: 'Security', href: '/app/settings/security', icon: 'S' },
  { id: 'billing', name: 'Billing', href: '/app/settings/billing', icon: 'B' },
  { id: 'help', name: 'Help Center', href: 'https://help.example.com', icon: 'H', isExternal: true },
  { id: 'logout', name: 'Sign Out', href: '#', icon: 'L' }
];

jest.mock('@/shared/hooks/NavigationContext', () => ({
  useNavigation: () => ({
    config: {
      userMenuItems: mockUserMenuItems
    }
  })
}));

// Mock userUtils
jest.mock('@/shared/utils/userUtils', () => ({
  getUserInitials: (user: any) => user?.name ? user.name.charAt(0).toUpperCase() : '?'
}));

describe('UserMenu', () => {
  const mockUser = {
    id: '1',
    name: 'John Doe',
    email: 'john@example.com',
    account: {
      name: 'Acme Corp'
    }
  };

  const createStore = (user = mockUser) => configureStore({
    reducer: {
      auth: (state = { user }) => state
    }
  });

  const renderComponent = (user = mockUser, props = {}) => {
    return render(
      <Provider store={createStore(user)}>
        <BrowserRouter>
          <UserMenu {...props} />
        </BrowserRouter>
      </Provider>
    );
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('rendering', () => {
    it('renders user initials', () => {
      renderComponent();

      expect(screen.getByText('J')).toBeInTheDocument();
    });

    it('renders user name on desktop', () => {
      renderComponent();

      expect(screen.getByText('John Doe')).toBeInTheDocument();
    });

    it('renders account name', () => {
      renderComponent();

      expect(screen.getByText('Acme Corp')).toBeInTheDocument();
    });

    it('renders dropdown toggle button', () => {
      renderComponent();

      const button = screen.getByRole('button', { expanded: false });
      expect(button).toBeInTheDocument();
    });

    it('applies custom className', () => {
      const { container } = renderComponent(mockUser, { className: 'custom-class' });

      expect(container.firstChild).toHaveClass('custom-class');
    });

    it('shows online status indicator', () => {
      const { container } = renderComponent();

      const statusIndicator = container.querySelector('.bg-theme-success');
      expect(statusIndicator).toBeInTheDocument();
    });
  });

  describe('dropdown behavior', () => {
    it('dropdown is closed by default', () => {
      renderComponent();

      expect(screen.queryByText('Account')).not.toBeInTheDocument();
    });

    it('opens dropdown when button clicked', () => {
      renderComponent();

      const button = screen.getByRole('button');
      fireEvent.click(button);

      expect(screen.getByText('Account')).toBeInTheDocument();
    });

    it('closes dropdown when button clicked again', () => {
      renderComponent();

      const button = screen.getByRole('button');
      fireEvent.click(button); // Open
      fireEvent.click(button); // Close

      expect(screen.queryByText('Account')).not.toBeInTheDocument();
    });

    it('shows user email in dropdown', () => {
      renderComponent();

      const button = screen.getByRole('button');
      fireEvent.click(button);

      expect(screen.getByText('john@example.com')).toBeInTheDocument();
    });

    it('closes dropdown when clicking outside', () => {
      renderComponent();

      const button = screen.getByRole('button');
      fireEvent.click(button);

      expect(screen.getByText('Account')).toBeInTheDocument();

      // Click outside
      fireEvent.mouseDown(document.body);

      expect(screen.queryByText('Account')).not.toBeInTheDocument();
    });
  });

  describe('menu items', () => {
    it('renders profile menu item', () => {
      renderComponent();

      const button = screen.getByRole('button');
      fireEvent.click(button);

      expect(screen.getByText('Profile')).toBeInTheDocument();
    });

    it('renders security menu item', () => {
      renderComponent();

      const button = screen.getByRole('button');
      fireEvent.click(button);

      expect(screen.getByText('Security')).toBeInTheDocument();
    });

    it('renders billing menu item', () => {
      renderComponent();

      const button = screen.getByRole('button');
      fireEvent.click(button);

      expect(screen.getByText('Billing')).toBeInTheDocument();
    });

    it('renders menu item descriptions when provided', () => {
      renderComponent();

      const button = screen.getByRole('button');
      fireEvent.click(button);

      expect(screen.getByText('Manage your profile')).toBeInTheDocument();
    });

    it('renders Support section header', () => {
      renderComponent();

      const button = screen.getByRole('button');
      fireEvent.click(button);

      expect(screen.getByText('Support')).toBeInTheDocument();
    });

    it('renders Sign Out button', () => {
      renderComponent();

      const button = screen.getByRole('button');
      fireEvent.click(button);

      expect(screen.getByText('Sign Out')).toBeInTheDocument();
    });
  });

  describe('menu links', () => {
    it('renders internal links with Link component', () => {
      renderComponent();

      const button = screen.getByRole('button');
      fireEvent.click(button);

      const profileLink = screen.getByText('Profile').closest('a');
      expect(profileLink).toHaveAttribute('href', '/app/settings/profile');
    });

    it('closes dropdown when internal link clicked', () => {
      renderComponent();

      const button = screen.getByRole('button');
      fireEvent.click(button);

      const profileLink = screen.getByText('Profile').closest('a');
      fireEvent.click(profileLink!);

      expect(screen.queryByText('Account')).not.toBeInTheDocument();
    });
  });

  describe('accessibility', () => {
    it('has aria-expanded attribute', () => {
      renderComponent();

      const button = screen.getByRole('button');
      expect(button).toHaveAttribute('aria-expanded', 'false');

      fireEvent.click(button);
      expect(button).toHaveAttribute('aria-expanded', 'true');
    });

    it('has aria-haspopup attribute', () => {
      renderComponent();

      const button = screen.getByRole('button');
      expect(button).toHaveAttribute('aria-haspopup', 'true');
    });
  });

  describe('dropdown arrow', () => {
    it('rotates arrow when dropdown is open', () => {
      const { container } = renderComponent();

      const button = screen.getByRole('button');
      const arrow = container.querySelector('svg');

      expect(arrow).not.toHaveClass('rotate-180');

      fireEvent.click(button);

      expect(arrow).toHaveClass('rotate-180');
    });
  });

  describe('user avatar', () => {
    it('displays user initials in avatar', () => {
      renderComponent();

      const button = screen.getByRole('button');
      fireEvent.click(button);

      // Should have initials in both button avatar and dropdown avatar
      const initials = screen.getAllByText('J');
      expect(initials.length).toBeGreaterThanOrEqual(1);
    });

    it('uses gradient background for avatar', () => {
      const { container } = renderComponent();

      const avatar = container.querySelector('.bg-gradient-to-br');
      expect(avatar).toBeInTheDocument();
    });
  });

  describe('theming', () => {
    it('uses theme-aware classes for surface', () => {
      renderComponent();

      const button = screen.getByRole('button');
      fireEvent.click(button);

      const dropdown = screen.getByText('Account').closest('.bg-theme-surface');
      expect(dropdown).toBeInTheDocument();
    });

    it('uses theme-aware text colors', () => {
      renderComponent();

      const nameText = screen.getByText('John Doe');
      expect(nameText).toHaveClass('text-theme-primary');
    });
  });
});
