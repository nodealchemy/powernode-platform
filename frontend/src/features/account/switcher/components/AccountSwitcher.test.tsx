import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { Provider } from 'react-redux';
import { configureStore } from '@reduxjs/toolkit';
import { AccountSwitcher } from './AccountSwitcher';

// Mock the notifications hook
const mockShowNotification = jest.fn();
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    showNotification: mockShowNotification
  })
}));

// Mock heroicons
jest.mock('@heroicons/react/24/outline', () => ({
  BuildingOfficeIcon: () => <span data-testid="building-icon">Building</span>,
  ChevronUpDownIcon: () => <span data-testid="chevron-icon">Chevron</span>,
  CheckIcon: () => <span data-testid="check-icon">Check</span>,
  ArrowPathIcon: () => <span data-testid="arrow-icon">Arrow</span>,
  HomeIcon: () => <span data-testid="home-icon">Home</span>
}));

// Mock the API
const mockGetAccessibleAccounts = jest.fn();
const mockSwitchAccount = jest.fn();
const mockSwitchToPrimary = jest.fn();

jest.mock('../services/accountSwitcherApi', () => ({
  accountSwitcherApi: {
    getAccessibleAccounts: (...args: any[]) => mockGetAccessibleAccounts(...args),
    switchAccount: (...args: any[]) => mockSwitchAccount(...args),
    switchToPrimary: (...args: any[]) => mockSwitchToPrimary(...args)
  }
}));

describe('AccountSwitcher', () => {
  const mockUser = {
    id: 'user-1',
    name: 'John Doe',
    account: {
      id: 'account-1',
      name: 'Primary Company'
    }
  };

  const mockAccounts = [
    {
      id: 'account-1',
      name: 'Primary Company',
      role: 'owner',
      is_current: true,
      is_primary: true,
      subscription: { plan_name: 'Pro' }
    },
    {
      id: 'account-2',
      name: 'Partner Company',
      role: 'delegated',
      is_current: false,
      is_primary: false,
      subscription: { plan_name: 'Enterprise' },
      delegation: { expires_at: '2025-06-15T00:00:00Z' }
    }
  ];

  const createStore = (user = mockUser) => configureStore({
    reducer: {
      auth: (state = { user }) => state
    }
  });

  const renderComponent = (user = mockUser, props = {}) => {
    return render(
      <Provider store={createStore(user)}>
        <AccountSwitcher {...props} />
      </Provider>
    );
  };

  beforeEach(() => {
    jest.clearAllMocks();
    mockGetAccessibleAccounts.mockResolvedValue({
      accounts: mockAccounts,
      current_account_id: 'account-1',
      primary_account_id: 'account-1'
    });
  });

  describe('rendering', () => {
    it('renders switcher button', () => {
      renderComponent();

      expect(screen.getByRole('button')).toBeInTheDocument();
    });

    it('displays current account name', () => {
      renderComponent();

      expect(screen.getByText('Primary Company')).toBeInTheDocument();
    });

    it('renders building office icon', () => {
      renderComponent();

      expect(screen.getByTestId('building-icon')).toBeInTheDocument();
    });

    it('renders chevron icon', () => {
      renderComponent();

      expect(screen.getByTestId('chevron-icon')).toBeInTheDocument();
    });

    it('applies custom className', () => {
      const { container } = renderComponent(mockUser, { className: 'custom-class' });

      expect(container.firstChild).toHaveClass('custom-class');
    });
  });

  describe('dropdown behavior', () => {
    it('dropdown is closed by default', () => {
      renderComponent();

      expect(screen.queryByText('Switch Account')).not.toBeInTheDocument();
    });

    it('opens dropdown when button clicked', async () => {
      renderComponent();

      fireEvent.click(screen.getByRole('button'));

      await waitFor(() => {
        expect(screen.getByText('Switch Account')).toBeInTheDocument();
      });
    });

    it('closes dropdown when clicking outside', async () => {
      renderComponent();

      fireEvent.click(screen.getByRole('button'));

      await waitFor(() => {
        expect(screen.getByText('Switch Account')).toBeInTheDocument();
      });

      fireEvent.mouseDown(document.body);

      expect(screen.queryByText('Switch Account')).not.toBeInTheDocument();
    });

    it('loads accounts when dropdown opens', async () => {
      renderComponent();

      fireEvent.click(screen.getByRole('button'));

      await waitFor(() => {
        expect(mockGetAccessibleAccounts).toHaveBeenCalled();
      });
    });
  });

  describe('account list', () => {
    it('displays all accessible accounts', async () => {
      renderComponent();

      fireEvent.click(screen.getByRole('button'));

      await waitFor(() => {
        expect(screen.getByText('Partner Company')).toBeInTheDocument();
      });
    });

    it('shows role badges', async () => {
      renderComponent();

      fireEvent.click(screen.getByRole('button'));

      await waitFor(() => {
        expect(screen.getByText('owner')).toBeInTheDocument();
      });
      expect(screen.getByText('delegated')).toBeInTheDocument();
    });

    it('shows subscription plan', async () => {
      renderComponent();

      fireEvent.click(screen.getByRole('button'));

      await waitFor(() => {
        expect(screen.getByText('Pro')).toBeInTheDocument();
      });
      expect(screen.getByText('Enterprise')).toBeInTheDocument();
    });

    it('shows check icon for current account', async () => {
      renderComponent();

      fireEvent.click(screen.getByRole('button'));

      await waitFor(() => {
        expect(screen.getByTestId('check-icon')).toBeInTheDocument();
      });
    });

    it('shows delegation expiry date', async () => {
      renderComponent();

      fireEvent.click(screen.getByRole('button'));

      await waitFor(() => {
        expect(screen.getByText(/Expires:/)).toBeInTheDocument();
      });
    });
  });

  describe('switching accounts', () => {
    it('calls switchAccount API when account selected', async () => {
      mockSwitchAccount.mockResolvedValue({
        access_token: 'new-token',
        refresh_token: 'new-refresh'
      });

      renderComponent();

      fireEvent.click(screen.getByRole('button'));

      await waitFor(() => {
        expect(screen.getByText('Partner Company')).toBeInTheDocument();
      });

      // Click on the partner company account button
      const partnerButton = screen.getByText('Partner Company').closest('button');
      fireEvent.click(partnerButton!);

      await waitFor(() => {
        expect(mockSwitchAccount).toHaveBeenCalledWith('account-2');
      });
    });

    it('updates localStorage tokens on successful switch', async () => {
      const setItemSpy = jest.spyOn(Storage.prototype, 'setItem');
      mockSwitchAccount.mockResolvedValue({
        access_token: 'new-access-token',
        refresh_token: 'new-refresh-token'
      });

      renderComponent();

      fireEvent.click(screen.getByRole('button'));

      await waitFor(() => {
        expect(screen.getByText('Partner Company')).toBeInTheDocument();
      });

      const partnerButton = screen.getByText('Partner Company').closest('button');
      fireEvent.click(partnerButton!);

      await waitFor(() => {
        expect(setItemSpy).toHaveBeenCalledWith('access_token', 'new-access-token');
        expect(setItemSpy).toHaveBeenCalledWith('refresh_token', 'new-refresh-token');
      });

      setItemSpy.mockRestore();
    });

    it('shows success notification on switch', async () => {
      mockSwitchAccount.mockResolvedValue({
        access_token: 'token',
        refresh_token: 'refresh'
      });

      renderComponent();

      fireEvent.click(screen.getByRole('button'));

      await waitFor(() => {
        expect(screen.getByText('Partner Company')).toBeInTheDocument();
      });

      const partnerButton = screen.getByText('Partner Company').closest('button');
      fireEvent.click(partnerButton!);

      await waitFor(() => {
        expect(mockShowNotification).toHaveBeenCalledWith('Switched to Partner Company', 'success');
      });
    });

    it('does not switch when clicking current account', async () => {
      renderComponent();

      fireEvent.click(screen.getByRole('button'));

      await waitFor(() => {
        // Find the Primary Company button (the one with check icon)
        expect(screen.getByTestId('check-icon')).toBeInTheDocument();
      });

      // The Primary Company row is the current account
      const primaryButton = screen.getAllByRole('button').find(btn =>
        btn.textContent?.includes('Primary Company') && btn.textContent?.includes('owner')
      );

      if (primaryButton) {
        fireEvent.click(primaryButton);
      }

      expect(mockSwitchAccount).not.toHaveBeenCalled();
    });
  });

  describe('delegated access', () => {
    it('shows delegated access indicator when on delegated account', async () => {
      mockGetAccessibleAccounts.mockResolvedValue({
        accounts: mockAccounts,
        current_account_id: 'account-2',
        primary_account_id: 'account-1'
      });

      renderComponent();

      fireEvent.click(screen.getByRole('button'));

      await waitFor(() => {
        expect(screen.getByText('Delegated Access')).toBeInTheDocument();
      });
    });

    it('shows Return to Primary button when on delegated account', async () => {
      mockGetAccessibleAccounts.mockResolvedValue({
        accounts: mockAccounts,
        current_account_id: 'account-2',
        primary_account_id: 'account-1'
      });

      renderComponent();

      fireEvent.click(screen.getByRole('button'));

      await waitFor(() => {
        expect(screen.getByText('Return to Primary Account')).toBeInTheDocument();
      });
    });

    it('calls switchToPrimary when Return to Primary clicked', async () => {
      mockGetAccessibleAccounts.mockResolvedValue({
        accounts: mockAccounts,
        current_account_id: 'account-2',
        primary_account_id: 'account-1'
      });
      mockSwitchToPrimary.mockResolvedValue({
        access_token: 'primary-token',
        refresh_token: 'primary-refresh'
      });

      renderComponent();

      fireEvent.click(screen.getByRole('button'));

      await waitFor(() => {
        expect(screen.getByText('Return to Primary Account')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Return to Primary Account'));

      await waitFor(() => {
        expect(mockSwitchToPrimary).toHaveBeenCalled();
      });
    });
  });

  describe('loading state', () => {
    it('shows loading indicator while fetching accounts', async () => {
      mockGetAccessibleAccounts.mockImplementation(() =>
        new Promise(resolve => setTimeout(() => resolve({
          accounts: mockAccounts,
          current_account_id: 'account-1',
          primary_account_id: 'account-1'
        }), 100))
      );

      renderComponent();

      fireEvent.click(screen.getByRole('button'));

      expect(screen.getByText('Loading accounts...')).toBeInTheDocument();
    });
  });

  describe('empty state', () => {
    it('shows message when no other accounts available', async () => {
      mockGetAccessibleAccounts.mockResolvedValue({
        accounts: [],
        current_account_id: 'account-1',
        primary_account_id: 'account-1'
      });

      renderComponent();

      fireEvent.click(screen.getByRole('button'));

      await waitFor(() => {
        expect(screen.getByText('No other accounts available')).toBeInTheDocument();
      });
    });
  });

  describe('error handling', () => {
    it('shows error notification on load failure', async () => {
      mockGetAccessibleAccounts.mockRejectedValue(new Error('Failed'));

      renderComponent();

      fireEvent.click(screen.getByRole('button'));

      await waitFor(() => {
        expect(mockShowNotification).toHaveBeenCalledWith('Failed to load accessible accounts', 'error');
      });
    });

    it('shows error notification on switch failure', async () => {
      mockSwitchAccount.mockRejectedValue(new Error('Switch failed'));

      renderComponent();

      fireEvent.click(screen.getByRole('button'));

      await waitFor(() => {
        expect(screen.getByText('Partner Company')).toBeInTheDocument();
      });

      const partnerButton = screen.getByText('Partner Company').closest('button');
      fireEvent.click(partnerButton!);

      await waitFor(() => {
        expect(mockShowNotification).toHaveBeenCalledWith('Failed to switch account', 'error');
      });
    });
  });
});
