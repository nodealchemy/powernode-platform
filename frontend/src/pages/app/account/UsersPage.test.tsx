import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { Provider } from 'react-redux';
import { configureStore } from '@reduxjs/toolkit';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { BreadcrumbProvider } from '@/shared/hooks/BreadcrumbContext';
import { UsersPage } from './UsersPage';

// fc-06: the "Invite Team Member" quick action used to land on this page with
// no invite flow at all -- InviteTeamMemberModal was built but never mounted
// anywhere. This suite pins the WIRING (permission gate, open/close, the
// ?invite=1 URL param); InviteTeamMemberModal's own form/request-shape
// behaviour has its own full suite and is not re-asserted here.
jest.mock('@/features/account/components/InviteTeamMemberModal', () => ({
  InviteTeamMemberModal: ({ isOpen, onClose, onInviteSent }: { isOpen: boolean; onClose: () => void; onInviteSent: () => void }) =>
    isOpen ? (
      <div data-testid="invite-modal">
        <button onClick={onClose}>Close Invite Modal</button>
        <button onClick={onInviteSent}>Signal Invite Sent</button>
      </div>
    ) : null
}));

const mockGetUsers = jest.fn();
const mockGetUserStats = jest.fn();
const mockGetAvailableRoles = jest.fn();
jest.mock('@/features/account/users/services/usersApi', () => ({
  usersApi: {
    getUsers: (...args: unknown[]) => mockGetUsers(...args),
    getUserStats: (...args: unknown[]) => mockGetUserStats(...args),
    getAvailableRoles: (...args: unknown[]) => mockGetAvailableRoles(...args),
    getRoleColor: () => ''
  }
}));

jest.mock('@/shared/hooks/usePageWebSocket', () => ({
  usePageWebSocket: () => {}
}));

const mockShowNotification = jest.fn();
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ showNotification: mockShowNotification })
}));

jest.mock('@/features/account/users/components/UserRolesModal', () => ({
  UserRolesModal: () => null
}));

// The table itself has its own suite (users-table/UsersTable.test.tsx); this
// one pins the invite wiring, so the table is a stub here.
jest.mock('@/features/account/users/components/users-table/UsersTableRows', () => ({
  UsersTableRows: () => <div data-testid="users-table" />
}));

const LocationDisplay = () => {
  const location = useLocation();
  return <div data-testid="location-search">{location.search}</div>;
};

describe('UsersContent (fc-06: invite flow mounted on the Users tab)', () => {
  const buildStore = (permissions: string[]) =>
    configureStore({
      reducer: {
        auth: (state = { user: { id: 'u1', name: 'Test User', email: 'test@example.com', permissions }, isAuthenticated: true }) => state
      }
    });

  const renderAt = (path: string, permissions: string[]) =>
    render(
      <Provider store={buildStore(permissions)}>
        <MemoryRouter initialEntries={[ path ]}>
          <BreadcrumbProvider>
            <UsersPage />
            <LocationDisplay />
          </BreadcrumbProvider>
        </MemoryRouter>
      </Provider>
    );

  beforeEach(() => {
    jest.clearAllMocks();
    mockGetUsers.mockResolvedValue({ success: true, data: [] });
    mockGetUserStats.mockResolvedValue({ success: true, data: { total_users: 0, active_users: 0, suspended_users: 0, unverified_users: 0, recent_logins: 0 } });
    mockGetAvailableRoles.mockResolvedValue([]);
  });

  describe('permission gate (team.invite OR users.create, mirroring the server)', () => {
    it('shows the Invite Team Member action for a user holding team.invite', async () => {
      renderAt('/app/profile/users', [ 'team.invite' ]);

      await waitFor(() => {
        expect(screen.getByText('Invite Team Member')).toBeInTheDocument();
      });
    });

    it('shows the Invite Team Member action for a user holding users.create', async () => {
      renderAt('/app/profile/users', [ 'users.create' ]);

      await waitFor(() => {
        expect(screen.getByText('Invite Team Member')).toBeInTheDocument();
      });
    });

    it('hides the Invite Team Member action for a user holding neither permission', async () => {
      renderAt('/app/profile/users', [ 'team.read' ]);

      await waitFor(() => {
        expect(screen.getByTestId('users-table')).toBeInTheDocument();
      });
      expect(screen.queryByText('Invite Team Member')).not.toBeInTheDocument();
    });
  });

  describe('opening the modal', () => {
    it('opens the invite modal when the action is clicked', async () => {
      renderAt('/app/profile/users', [ 'team.invite' ]);

      await waitFor(() => {
        expect(screen.getByText('Invite Team Member')).toBeInTheDocument();
      });
      fireEvent.click(screen.getByText('Invite Team Member'));

      expect(screen.getByTestId('invite-modal')).toBeInTheDocument();
    });

    it('opens the invite modal directly from the ?invite=1 URL param, URL-addressable', async () => {
      renderAt('/app/profile/users?invite=1', [ 'team.invite' ]);

      await waitFor(() => {
        expect(screen.getByTestId('invite-modal')).toBeInTheDocument();
      });
    });

    it('does not honor ?invite=1 for a user without permission', async () => {
      renderAt('/app/profile/users?invite=1', [ 'team.read' ]);

      await waitFor(() => {
        expect(screen.getByTestId('users-table')).toBeInTheDocument();
      });
      expect(screen.queryByTestId('invite-modal')).not.toBeInTheDocument();
    });

    it('clears the ?invite=1 param when the modal is closed', async () => {
      renderAt('/app/profile/users?invite=1', [ 'team.invite' ]);

      await waitFor(() => {
        expect(screen.getByTestId('invite-modal')).toBeInTheDocument();
      });
      expect(screen.getByTestId('location-search')).toHaveTextContent('invite=1');

      fireEvent.click(screen.getByText('Close Invite Modal'));

      await waitFor(() => {
        expect(screen.queryByTestId('invite-modal')).not.toBeInTheDocument();
      });
      expect(screen.getByTestId('location-search')).toHaveTextContent('');
    });

    it('shows a success notification when the invite modal signals a sent invite', async () => {
      renderAt('/app/profile/users', [ 'team.invite' ]);

      await waitFor(() => {
        expect(screen.getByText('Invite Team Member')).toBeInTheDocument();
      });
      fireEvent.click(screen.getByText('Invite Team Member'));
      fireEvent.click(screen.getByText('Signal Invite Sent'));

      expect(mockShowNotification).toHaveBeenCalledWith('Invitation sent successfully', 'success');
    });
  });
});
