import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { Provider } from 'react-redux';
import { configureStore } from '@reduxjs/toolkit';
import { UserManagement } from './UserManagement';

// Mock admin settings API
const mockGetUsers = jest.fn();
jest.mock('../services/adminSettingsApi', () => ({
  adminSettingsApi: {
    getUsers: (...args: any[]) => mockGetUsers(...args)
  }
}));

// Create mock store
const createMockStore = (permissions: string[] = []) => configureStore({
  reducer: {
    auth: () => ({
      user: {
        id: 'user-1',
        email: 'admin@example.com',
        permissions
      }
    })
  }
});

const renderWithProviders = (component: React.ReactElement, permissions: string[] = []) => {
  const store = createMockStore(permissions);
  return render(
    <Provider store={store}>
      {component}
    </Provider>
  );
};

describe('UserManagement', () => {
  const mockUsersData = {
    users: [
      {
        id: 'user-1',
        email: 'john@example.com',
        full_name: 'John Doe',
        name: 'John',
        roles: ['account.manager', 'billing.manager'],
        account: { status: 'active' }
      },
      {
        id: 'user-2',
        email: 'jane@example.com',
        full_name: 'Jane Smith',
        name: 'Jane',
        roles: ['account.member'],
        account: { status: 'active' }
      },
      {
        id: 'user-3',
        email: 'bob@example.com',
        full_name: null,
        name: 'Bob Wilson',
        roles: [],
        account: { status: 'suspended' }
      }
    ],
    pagination: {
      current_page: 1,
      per_page: 20,
      total_count: 50,
      total_pages: 3
    }
  };

  beforeEach(() => {
    jest.clearAllMocks();
    mockGetUsers.mockResolvedValue(mockUsersData);
  });

  describe('rendering', () => {
    it('renders title', async () => {
      renderWithProviders(<UserManagement />);

      expect(screen.getByText('User Management')).toBeInTheDocument();
    });

    it('renders status filter', async () => {
      renderWithProviders(<UserManagement />);

      expect(screen.getByLabelText('Filter by Status')).toBeInTheDocument();
    });

    it('renders filter options', () => {
      renderWithProviders(<UserManagement />);

      expect(screen.getByText('All')).toBeInTheDocument();
      expect(screen.getByText('Active')).toBeInTheDocument();
      expect(screen.getByText('Inactive')).toBeInTheDocument();
    });
  });

  describe('user list', () => {
    it('loads users on mount', async () => {
      renderWithProviders(<UserManagement />);

      await waitFor(() => {
        expect(mockGetUsers).toHaveBeenCalledWith({
          page: 1,
          per_page: 20,
          status: undefined
        });
      });
    });

    it('displays user emails', async () => {
      renderWithProviders(<UserManagement />);

      await waitFor(() => {
        expect(screen.getByText('john@example.com')).toBeInTheDocument();
      });
      expect(screen.getByText('jane@example.com')).toBeInTheDocument();
      expect(screen.getByText('bob@example.com')).toBeInTheDocument();
    });

    it('displays user names', async () => {
      renderWithProviders(<UserManagement />);

      await waitFor(() => {
        expect(screen.getByText('John Doe')).toBeInTheDocument();
      });
      expect(screen.getByText('Jane Smith')).toBeInTheDocument();
      expect(screen.getByText('Bob Wilson')).toBeInTheDocument();
    });

    it('displays user roles', async () => {
      renderWithProviders(<UserManagement />);

      await waitFor(() => {
        expect(screen.getByText('account.manager')).toBeInTheDocument();
      });
      expect(screen.getByText('billing.manager')).toBeInTheDocument();
      expect(screen.getByText('account.member')).toBeInTheDocument();
    });

    it('displays account status', async () => {
      renderWithProviders(<UserManagement />);

      // Wait for user data to load by checking for a specific user email
      await waitFor(() => {
        expect(screen.getByText('bob@example.com')).toBeInTheDocument();
      });

      // Now check for status - "Active" appears multiple times (2 users + select option)
      const activeStatuses = screen.getAllByText('Active');
      expect(activeStatuses.length).toBeGreaterThan(1); // At least select option + active users
      expect(screen.getByText('Suspended')).toBeInTheDocument();
    });
  });

  describe('status filtering', () => {
    it('filters by active status', async () => {
      renderWithProviders(<UserManagement />);

      await waitFor(() => {
        expect(mockGetUsers).toHaveBeenCalled();
      });

      const filterSelect = screen.getByLabelText('Filter by Status');
      fireEvent.change(filterSelect, { target: { value: 'active' } });

      await waitFor(() => {
        expect(mockGetUsers).toHaveBeenCalledWith({
          page: 1,
          per_page: 20,
          status: 'active'
        });
      });
    });

    it('filters by inactive status', async () => {
      renderWithProviders(<UserManagement />);

      await waitFor(() => {
        expect(mockGetUsers).toHaveBeenCalled();
      });

      const filterSelect = screen.getByLabelText('Filter by Status');
      fireEvent.change(filterSelect, { target: { value: 'inactive' } });

      await waitFor(() => {
        expect(mockGetUsers).toHaveBeenCalledWith({
          page: 1,
          per_page: 20,
          status: 'inactive'
        });
      });
    });

    it('resets to page 1 when filter changes', async () => {
      mockGetUsers.mockResolvedValueOnce({
        ...mockUsersData,
        pagination: { ...mockUsersData.pagination, current_page: 2 }
      });

      renderWithProviders(<UserManagement />);

      await waitFor(() => {
        expect(mockGetUsers).toHaveBeenCalled();
      });

      const filterSelect = screen.getByLabelText('Filter by Status');
      fireEvent.change(filterSelect, { target: { value: 'active' } });

      await waitFor(() => {
        expect(mockGetUsers).toHaveBeenLastCalledWith(expect.objectContaining({
          page: 1
        }));
      });
    });
  });

  describe('pagination', () => {
    it('shows page information', async () => {
      renderWithProviders(<UserManagement />);

      await waitFor(() => {
        expect(screen.getByText('Page 1 of 3')).toBeInTheDocument();
      });
    });

    it('shows Previous button', async () => {
      renderWithProviders(<UserManagement />);

      await waitFor(() => {
        expect(screen.getByText('Previous')).toBeInTheDocument();
      });
    });

    it('shows Next button', async () => {
      renderWithProviders(<UserManagement />);

      await waitFor(() => {
        expect(screen.getByText('Next')).toBeInTheDocument();
      });
    });

    it('disables Previous button on first page', async () => {
      renderWithProviders(<UserManagement />);

      await waitFor(() => {
        expect(screen.getByText('Previous')).toBeDisabled();
      });
    });

    it('enables Next button when more pages available', async () => {
      renderWithProviders(<UserManagement />);

      await waitFor(() => {
        expect(screen.getByText('Next')).not.toBeDisabled();
      });
    });

    it('goes to next page when Next clicked', async () => {
      renderWithProviders(<UserManagement />);

      // Wait for initial data load
      await waitFor(() => {
        expect(screen.getByText('john@example.com')).toBeInTheDocument();
      });

      // Clear mock call history
      mockGetUsers.mockClear();

      fireEvent.click(screen.getByText('Next'));

      await waitFor(() => {
        expect(mockGetUsers).toHaveBeenCalledWith({
          page: 2,
          per_page: 20,
          status: undefined
        });
      });
    });

    it('goes to previous page when Previous clicked', async () => {
      renderWithProviders(<UserManagement />);

      // Wait for initial load
      await waitFor(() => {
        expect(screen.getByText('john@example.com')).toBeInTheDocument();
      });

      // Go to page 2 first
      fireEvent.click(screen.getByText('Next'));

      await waitFor(() => {
        expect(mockGetUsers).toHaveBeenCalledWith(expect.objectContaining({ page: 2 }));
      });

      // Clear mock and go back
      mockGetUsers.mockClear();
      fireEvent.click(screen.getByText('Previous'));

      await waitFor(() => {
        expect(mockGetUsers).toHaveBeenCalledWith(expect.objectContaining({ page: 1 }));
      });
    });

    it('disables Next button on last page', async () => {
      mockGetUsers.mockResolvedValue({
        ...mockUsersData,
        pagination: { ...mockUsersData.pagination, current_page: 3, total_pages: 3 }
      });

      renderWithProviders(<UserManagement />);

      await waitFor(() => {
        expect(screen.getByText('Next')).toBeDisabled();
      });
    });
  });

  describe('create user button', () => {
    it('shows Create User button when user has permission', () => {
      renderWithProviders(<UserManagement />, ['users.create']);

      expect(screen.getByText('Create User')).toBeInTheDocument();
    });

    it('hides Create User button when user lacks permission', () => {
      renderWithProviders(<UserManagement />, []);

      expect(screen.queryByText('Create User')).not.toBeInTheDocument();
    });

    it('opens create modal when clicked', async () => {
      renderWithProviders(<UserManagement />, ['users.create']);

      fireEvent.click(screen.getByText('Create User'));

      expect(screen.getByText('Create New User')).toBeInTheDocument();
    });
  });

  describe('create modal', () => {
    it('shows email field in create modal', async () => {
      renderWithProviders(<UserManagement />, ['users.create']);

      fireEvent.click(screen.getByText('Create User'));

      expect(screen.getByLabelText('Email')).toBeInTheDocument();
    });

    it('shows first name field in create modal', async () => {
      renderWithProviders(<UserManagement />, ['users.create']);

      fireEvent.click(screen.getByText('Create User'));

      expect(screen.getByLabelText('First Name')).toBeInTheDocument();
    });

    it('shows last name field in create modal', async () => {
      renderWithProviders(<UserManagement />, ['users.create']);

      fireEvent.click(screen.getByText('Create User'));

      expect(screen.getByLabelText('Last Name')).toBeInTheDocument();
    });

    it('shows Create button in modal', async () => {
      renderWithProviders(<UserManagement />, ['users.create']);

      fireEvent.click(screen.getByText('Create User'));

      // There's a Create User button and a Create button
      const createButtons = screen.getAllByText(/Create/);
      expect(createButtons.length).toBeGreaterThan(1);
    });
  });
});
