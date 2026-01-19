import { screen, fireEvent, waitFor } from '@testing-library/react';
import { UserRolesModal } from './UserRolesModal';
import { renderWithProviders, mockAuthenticatedState, EnhancedUser, createMockUser } from '@/shared/utils/test-utils';

// Import the actual module first to ensure proper mocking
import { usersApi } from '@/features/account/users/services/usersApi';

jest.mock('@/features/account/users/services/usersApi', () => ({
  usersApi: {
    updateAdminUser: jest.fn(),
    getAvailableRoles: jest.fn(),
    getRoleColor: jest.fn(() => 'bg-blue-100 text-blue-800'),
    formatRole: jest.fn(() => 'Role Name')
  }
}));

const mockUser: EnhancedUser = createMockUser({
  id: '1',
  email: 'user@example.com',
  name: 'John Doe',
  roles: ['account.member'],
  permissions: ['users.read'],
  status: 'active',
  email_verified: true,
  created_at: '2023-01-01T00:00:00Z',
  account: {
    id: 'acc_1',
    name: 'Test Company',
    status: 'active'
  }
});

const mockAvailableRoles = [
  {
    value: 'account.member',
    label: 'Account Member',
    description: 'Basic account access',
    canAssign: true
  },
  {
    value: 'account.owner',
    label: 'Account Owner',
    description: 'Can manage account settings and users',
    canAssign: true
  },
  {
    value: 'billing.manager',
    label: 'Billing Manager',
    description: 'Can manage billing and subscriptions',
    canAssign: true
  },
  {
    value: 'system.admin',
    label: 'System Administrator',
    description: 'Full system access',
    canAssign: false
  }
];

describe('UserRolesModal', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    // Set up the mocks properly
    (usersApi.getAvailableRoles as jest.Mock).mockResolvedValue(mockAvailableRoles);
    (usersApi.updateAdminUser as jest.Mock).mockResolvedValue({ success: true });
  });

  it('renders modal with user information', async () => {
    renderWithProviders(
      <UserRolesModal
        isOpen={true}
        onClose={jest.fn()}
        user={mockUser}
        onUserUpdated={jest.fn()}
      />,
      { preloadedState: mockAuthenticatedState }
    );

    await waitFor(() => {
      expect(screen.getByText('Manage Roles - John Doe')).toBeInTheDocument();
    });

    expect(screen.getByText('John Doe')).toBeInTheDocument();
    expect(screen.getByText('user@example.com')).toBeInTheDocument();
  });

  it('loads and displays available roles', async () => {
    renderWithProviders(
      <UserRolesModal
        isOpen={true}
        onClose={jest.fn()}
        user={mockUser}
        onUserUpdated={jest.fn()}
      />,
      { preloadedState: mockAuthenticatedState }
    );

    await waitFor(() => {
      // Check that Available Roles section exists
      expect(screen.getByText('Available Roles')).toBeInTheDocument();
    });

    // Check for role labels in the available roles section
    expect(screen.getAllByText('Account Member')).toHaveLength(2); // One in current, one in available
    expect(screen.getByText('Account Owner')).toBeInTheDocument();
    expect(screen.getByText('Billing Manager')).toBeInTheDocument();
    expect(screen.getByText('System Administrator')).toBeInTheDocument();
  });

  it('shows current user roles in the current roles section', async () => {
    renderWithProviders(
      <UserRolesModal
        isOpen={true}
        onClose={jest.fn()}
        user={mockUser}
        onUserUpdated={jest.fn()}
      />,
      { preloadedState: mockAuthenticatedState }
    );

    await waitFor(() => {
      expect(screen.getByText('Current Roles')).toBeInTheDocument();
    });

    const rolesSection = screen.getByText('Current Roles').parentElement?.parentElement;
    expect(rolesSection).toHaveTextContent('Account Member');
  });

  it('allows toggling role selection', async () => {
    renderWithProviders(
      <UserRolesModal
        isOpen={true}
        onClose={jest.fn()}
        user={mockUser}
        onUserUpdated={jest.fn()}
      />,
      { preloadedState: mockAuthenticatedState }
    );

    await waitFor(() => {
      expect(screen.getByText('Account Owner')).toBeInTheDocument();
    });

    // Find and click the Account Owner role card
    const managerCard = screen.getByText('Account Owner').closest('div');
    if (managerCard) {
      fireEvent.click(managerCard);
    }

    // Check that it's now marked as being added
    await waitFor(() => {
      expect(screen.getByText('Adding:')).toBeInTheDocument();
    });
  });

  it('displays role descriptions', async () => {
    renderWithProviders(
      <UserRolesModal
        isOpen={true}
        onClose={jest.fn()}
        user={mockUser}
        onUserUpdated={jest.fn()}
      />,
      { preloadedState: mockAuthenticatedState }
    );

    await waitFor(() => {
      expect(screen.getByText('Basic account access')).toBeInTheDocument();
    });

    expect(screen.getByText('Can manage account settings and users')).toBeInTheDocument();
  });

  it('shows pending changes indicator', async () => {
    renderWithProviders(
      <UserRolesModal
        isOpen={true}
        onClose={jest.fn()}
        user={mockUser}
        onUserUpdated={jest.fn()}
      />,
      { preloadedState: mockAuthenticatedState }
    );

    await waitFor(() => {
      expect(screen.getByText('Account Owner')).toBeInTheDocument();
    });

    // Click to add a role
    const managerCard = screen.getByText('Account Owner').closest('div');
    if (managerCard) {
      fireEvent.click(managerCard);
    }

    // Should show "You have unsaved changes"
    await waitFor(() => {
      expect(screen.getByText('You have unsaved changes')).toBeInTheDocument();
    });
  });

  it('saves role changes successfully', async () => {
    const mockOnUserUpdated = jest.fn();
    const mockOnClose = jest.fn();
    (usersApi.updateAdminUser as jest.Mock).mockResolvedValue({
      success: true,
      data: { ...mockUser, roles: ['account.member', 'account.owner'] }
    });

    renderWithProviders(
      <UserRolesModal
        isOpen={true}
        onClose={mockOnClose}
        user={mockUser}
        onUserUpdated={mockOnUserUpdated}
      />
    );

    await waitFor(() => {
      expect(screen.getByText('Account Owner')).toBeInTheDocument();
    });

    // Add a role
    const managerCard = screen.getByText('Account Owner').closest('div');
    if (managerCard) {
      fireEvent.click(managerCard);
    }

    // Click save
    const saveButton = screen.getByRole('button', { name: /save changes/i });
    fireEvent.click(saveButton);

    await waitFor(() => {
      expect((usersApi.updateAdminUser as jest.Mock)).toHaveBeenCalledWith('1', {
        roles: ['account.member', 'account.owner']
      });
    });

    expect(mockOnUserUpdated).toHaveBeenCalled();
    expect(mockOnClose).toHaveBeenCalled();
  });

  it('handles save errors gracefully', async () => {
    (usersApi.updateAdminUser as jest.Mock).mockRejectedValue({
      response: {
        data: { error: 'Insufficient permissions' }
      }
    });

    renderWithProviders(
      <UserRolesModal
        isOpen={true}
        onClose={jest.fn()}
        user={mockUser}
        onUserUpdated={jest.fn()}
      />,
      { preloadedState: mockAuthenticatedState }
    );

    await waitFor(() => {
      expect(screen.getByText('Account Owner')).toBeInTheDocument();
    });

    // Add a role
    const managerCard = screen.getByText('Account Owner').closest('div');
    if (managerCard) {
      fireEvent.click(managerCard);
    }

    const saveButton = screen.getByRole('button', { name: /save changes/i });
    fireEvent.click(saveButton);

    await waitFor(() => {
      expect((usersApi.updateAdminUser as jest.Mock)).toHaveBeenCalled();
    });
  });

  it('prevents removing all roles', async () => {
    renderWithProviders(
      <UserRolesModal
        isOpen={true}
        onClose={jest.fn()}
        user={mockUser}
        onUserUpdated={jest.fn()}
      />
    );

    await waitFor(() => {
      expect(screen.getByText('Account Member')).toBeInTheDocument();
    });

    // Try to remove the only role
    const memberCard = Array.from(document.querySelectorAll('div')).find(
      el => el.textContent?.includes('Account Member') && el.className?.includes('cursor-pointer')
    );

    if (memberCard) {
      fireEvent.click(memberCard);
    }

    // Save button should still work but will show error
    const saveButton = screen.getByRole('button', { name: /save changes/i });
    fireEvent.click(saveButton);

    // The component should prevent saving with no roles
    await waitFor(() => {
      expect((usersApi.updateAdminUser as jest.Mock)).not.toHaveBeenCalled();
    });
  });

  it('shows restricted roles with lock icon', async () => {
    renderWithProviders(
      <UserRolesModal
        isOpen={true}
        onClose={jest.fn()}
        user={mockUser}
        onUserUpdated={jest.fn()}
      />,
      { preloadedState: mockAuthenticatedState }
    );

    await waitFor(() => {
      // System admin role should be restricted (canAssign: false)
      expect(screen.getByText('System Administrator')).toBeInTheDocument();
    });

    // Check for "Restricted" badge
    expect(screen.getByText('Restricted')).toBeInTheDocument();
  });

  it('allows resetting pending changes', async () => {
    renderWithProviders(
      <UserRolesModal
        isOpen={true}
        onClose={jest.fn()}
        user={mockUser}
        onUserUpdated={jest.fn()}
      />,
      { preloadedState: mockAuthenticatedState }
    );

    await waitFor(() => {
      expect(screen.getByText('Account Owner')).toBeInTheDocument();
    });

    // Add a role
    const managerCard = screen.getByText('Account Owner').closest('div');
    if (managerCard) {
      fireEvent.click(managerCard);
    }

    // Should show reset button
    await waitFor(() => {
      expect(screen.getByRole('button', { name: /reset changes/i })).toBeInTheDocument();
    });

    const resetButton = screen.getByRole('button', { name: /reset changes/i });
    fireEvent.click(resetButton);

    // Changes should be cleared
    await waitFor(() => {
      expect(screen.queryByText('Adding:')).not.toBeInTheDocument();
    });
  });

  it('does not render when user is null', () => {
    const { container } = renderWithProviders(
      <UserRolesModal
        isOpen={true}
        onClose={jest.fn()}
        user={null}
        onUserUpdated={jest.fn()}
      />,
      { preloadedState: mockAuthenticatedState }
    );

    expect(container.firstChild).toBeNull();
  });

  it('closes modal on cancel', () => {
    const mockOnClose = jest.fn();

    renderWithProviders(
      <UserRolesModal
        isOpen={true}
        onClose={mockOnClose}
        user={mockUser}
        onUserUpdated={jest.fn()}
      />
    );

    const cancelButton = screen.getByRole('button', { name: /cancel/i });
    fireEvent.click(cancelButton);

    expect(mockOnClose).toHaveBeenCalled();
  });

  it('handles API failure when loading roles', async () => {
    (usersApi.getAvailableRoles as jest.Mock).mockRejectedValue(new Error('Failed to load'));

    renderWithProviders(
      <UserRolesModal
        isOpen={true}
        onClose={jest.fn()}
        user={mockUser}
        onUserUpdated={jest.fn()}
      />,
      { preloadedState: mockAuthenticatedState }
    );

    // Should still render but without available roles
    await waitFor(() => {
      expect(screen.getByText('Manage Roles - John Doe')).toBeInTheDocument();
    });
  });

  it('displays role count correctly', async () => {
    renderWithProviders(
      <UserRolesModal
        isOpen={true}
        onClose={jest.fn()}
        user={mockUser}
        onUserUpdated={jest.fn()}
      />,
      { preloadedState: mockAuthenticatedState }
    );

    // User has 1 role
    await waitFor(() => {
      expect(screen.getByText('1')).toBeInTheDocument();
    });

    expect(screen.getByText('Role')).toBeInTheDocument();

    // Add another role
    const managerCard = screen.getByText('Account Owner').closest('div');
    if (managerCard) {
      fireEvent.click(managerCard);
    }

    // Should now show 2 roles
    await waitFor(() => {
      expect(screen.getByText('2')).toBeInTheDocument();
    });

    expect(screen.getByText('Roles')).toBeInTheDocument();
  });
});
