import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { Provider } from 'react-redux';
import { configureStore } from '@reduxjs/toolkit';
import { UserManagement } from './UserManagement';

// fc-38: migrated off adminSettingsApi.getUsers() onto usersApi.getAllUsers()
// — mock the new client, in its actual response shape
// ({ success, data: User[] }, no pagination/status-filter params, since
// /admin/users returns every user in one response).
const mockGetAllUsers = jest.fn();
jest.mock('@/features/account/users/services/usersApi', () => ({
  usersApi: {
    getAllUsers: (...args: unknown[]) => mockGetAllUsers(...args)
  }
}));

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

// User shape per features/account/users/services/usersApi.ts's `User`
// interface — status is the USER's own status; account.status is separate
// (the badge in the list reads account.status, unchanged from before the
// migration; the filter reads status, per the pre-migration filter's own
// intent — see AdminSettingsController#users's now-deleted active_count/
// inactive_count/suspended_count, which counted User.status, not account
// status).
const makeUser = (overrides: Partial<{
  id: string; email: string; name: string; status: string; roles: string[]; accountStatus: string;
}>) => ({
  id: overrides.id ?? 'user-1',
  email: overrides.email ?? 'john@example.com',
  name: overrides.name ?? 'John',
  email_verified: true,
  roles: overrides.roles ?? [],
  permissions: [],
  status: overrides.status ?? 'active',
  locked: false,
  failed_login_attempts: 0,
  last_login_at: null,
  created_at: '2026-01-01T00:00:00Z',
  updated_at: '2026-01-01T00:00:00Z',
  preferences: {},
  account: { id: 'account-1', name: 'Acme', status: overrides.accountStatus ?? 'active' }
});

describe('UserManagement', () => {
  const threeUsers = [
    makeUser({ id: 'user-1', email: 'john@example.com', name: 'John Doe', roles: ['account.manager', 'billing.manager'] }),
    makeUser({ id: 'user-2', email: 'jane@example.com', name: 'Jane Smith', roles: ['account.member'] }),
    makeUser({ id: 'user-3', email: 'bob@example.com', name: 'Bob Wilson', roles: [], status: 'inactive', accountStatus: 'suspended' })
  ];

  beforeEach(() => {
    jest.clearAllMocks();
    mockGetAllUsers.mockResolvedValue({ success: true, data: threeUsers });
  });

  describe('rendering', () => {
    it('renders title', () => {
      renderWithProviders(<UserManagement />);

      expect(screen.getByText('User Management')).toBeInTheDocument();
    });

    it('renders status filter with All/Active/Inactive options', () => {
      renderWithProviders(<UserManagement />);

      expect(screen.getByLabelText('Filter by Status')).toBeInTheDocument();
      expect(screen.getByText('All')).toBeInTheDocument();
      expect(screen.getByText('Active')).toBeInTheDocument();
      expect(screen.getByText('Inactive')).toBeInTheDocument();
    });
  });

  describe('user list (field parity with the pre-migration adminSettingsApi shape)', () => {
    it('loads from usersApi.getAllUsers on mount', async () => {
      renderWithProviders(<UserManagement />);

      await waitFor(() => expect(mockGetAllUsers).toHaveBeenCalledTimes(1));
    });

    it('displays user emails', async () => {
      renderWithProviders(<UserManagement />);

      await waitFor(() => expect(screen.getByText('john@example.com')).toBeInTheDocument());
      expect(screen.getByText('jane@example.com')).toBeInTheDocument();
      expect(screen.getByText('bob@example.com')).toBeInTheDocument();
    });

    it('displays user names', async () => {
      renderWithProviders(<UserManagement />);

      await waitFor(() => expect(screen.getByText('John Doe')).toBeInTheDocument());
      expect(screen.getByText('Jane Smith')).toBeInTheDocument();
      expect(screen.getByText('Bob Wilson')).toBeInTheDocument();
    });

    it('displays user roles', async () => {
      renderWithProviders(<UserManagement />);

      await waitFor(() => expect(screen.getByText('account.manager')).toBeInTheDocument());
      expect(screen.getByText('billing.manager')).toBeInTheDocument();
      expect(screen.getByText('account.member')).toBeInTheDocument();
    });

    it('displays account status (from user.account.status)', async () => {
      renderWithProviders(<UserManagement />);

      await waitFor(() => expect(screen.getByText('bob@example.com')).toBeInTheDocument());

      const activeStatuses = screen.getAllByText('Active');
      expect(activeStatuses.length).toBeGreaterThan(1); // select option + 2 active-account users
      expect(screen.getByText('Suspended')).toBeInTheDocument();
    });
  });

  describe('status filtering (client-side — the pre-migration control sent a `status` param the old endpoint silently ignored, so this never actually filtered before)', () => {
    it('shows only active-status users when Active is selected', async () => {
      renderWithProviders(<UserManagement />);
      await waitFor(() => expect(screen.getByText('john@example.com')).toBeInTheDocument());

      fireEvent.change(screen.getByLabelText('Filter by Status'), { target: { value: 'active' } });

      expect(screen.getByText('john@example.com')).toBeInTheDocument();
      expect(screen.getByText('jane@example.com')).toBeInTheDocument();
      expect(screen.queryByText('bob@example.com')).not.toBeInTheDocument();
    });

    it('shows only inactive-status users when Inactive is selected', async () => {
      renderWithProviders(<UserManagement />);
      await waitFor(() => expect(screen.getByText('bob@example.com')).toBeInTheDocument());

      fireEvent.change(screen.getByLabelText('Filter by Status'), { target: { value: 'inactive' } });

      expect(screen.getByText('bob@example.com')).toBeInTheDocument();
      expect(screen.queryByText('john@example.com')).not.toBeInTheDocument();
    });

    it('does not call the API again when the filter changes (all data is already loaded)', async () => {
      renderWithProviders(<UserManagement />);
      await waitFor(() => expect(mockGetAllUsers).toHaveBeenCalledTimes(1));

      fireEvent.change(screen.getByLabelText('Filter by Status'), { target: { value: 'active' } });

      expect(mockGetAllUsers).toHaveBeenCalledTimes(1);
    });
  });

  describe('pagination (client-side, 20 per page)', () => {
    const manyUsers = Array.from({ length: 25 }, (_, i) =>
      makeUser({ id: `user-${i}`, email: `user${i}@example.com`, name: `User ${i}` })
    );

    beforeEach(() => {
      mockGetAllUsers.mockResolvedValue({ success: true, data: manyUsers });
    });

    it('shows page 1 of 2 for 25 users at 20/page', async () => {
      renderWithProviders(<UserManagement />);

      await waitFor(() => expect(screen.getByText('Page 1 of 2')).toBeInTheDocument());
    });

    it('disables Previous on page 1 and enables Next', async () => {
      renderWithProviders(<UserManagement />);

      await waitFor(() => expect(screen.getByText('user0@example.com')).toBeInTheDocument());
      expect(screen.getByText('Previous')).toBeDisabled();
      expect(screen.getByText('Next')).not.toBeDisabled();
    });

    it('shows the next 5 users and disables Next on the last page', async () => {
      renderWithProviders(<UserManagement />);
      await waitFor(() => expect(screen.getByText('user0@example.com')).toBeInTheDocument());

      fireEvent.click(screen.getByText('Next'));

      expect(screen.getByText('Page 2 of 2')).toBeInTheDocument();
      expect(screen.getByText('user20@example.com')).toBeInTheDocument();
      expect(screen.queryByText('user0@example.com')).not.toBeInTheDocument();
      expect(screen.getByText('Next')).toBeDisabled();
    });

    it('goes back to page 1 with Previous', async () => {
      renderWithProviders(<UserManagement />);
      await waitFor(() => expect(screen.getByText('user0@example.com')).toBeInTheDocument());

      fireEvent.click(screen.getByText('Next'));
      fireEvent.click(screen.getByText('Previous'));

      expect(screen.getByText('Page 1 of 2')).toBeInTheDocument();
      expect(screen.getByText('user0@example.com')).toBeInTheDocument();
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

    it('opens create modal when clicked', () => {
      renderWithProviders(<UserManagement />, ['users.create']);

      fireEvent.click(screen.getByText('Create User'));

      expect(screen.getByText('Create New User')).toBeInTheDocument();
    });
  });

  describe('create modal', () => {
    it('shows email, first name and last name fields, and a Create button', () => {
      renderWithProviders(<UserManagement />, ['users.create']);

      fireEvent.click(screen.getByText('Create User'));

      expect(screen.getByLabelText('Email')).toBeInTheDocument();
      expect(screen.getByLabelText('First Name')).toBeInTheDocument();
      expect(screen.getByLabelText('Last Name')).toBeInTheDocument();
      expect(screen.getAllByText(/Create/).length).toBeGreaterThan(1);
    });
  });
});
