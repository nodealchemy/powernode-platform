import { render, screen, fireEvent } from '@testing-library/react';
import { PermissionSelector } from './PermissionSelector';

describe('PermissionSelector', () => {
  const mockRoles = [
    { id: 'role-1', name: 'Admin', description: 'Full access' },
    { id: 'role-2', name: 'Editor', description: 'Can edit content' },
    { id: 'role-3', name: 'Viewer', description: 'Read-only access' }
  ];

  const mockPermissions = [
    { id: 'perm-1', resource: 'users', action: 'read', description: 'View users', key: 'users.read' },
    { id: 'perm-2', resource: 'users', action: 'create', description: 'Create users', key: 'users.create' },
    { id: 'perm-3', resource: 'users', action: 'delete', description: 'Delete users', key: 'users.delete' },
    { id: 'perm-4', resource: 'billing', action: 'read', description: 'View billing', key: 'billing.read' },
    { id: 'perm-5', resource: 'billing', action: 'update', description: 'Update billing', key: 'billing.update' },
    { id: 'perm-6', resource: 'analytics', action: 'export', description: 'Export analytics', key: 'analytics.export' }
  ];

  const defaultProps = {
    selectedRoleId: undefined,
    selectedPermissionIds: [],
    onPermissionChange: jest.fn(),
    onRoleChange: jest.fn(),
    availableRoles: mockRoles,
    availablePermissions: mockPermissions
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('loading state', () => {
    it('shows loading spinner when loading', () => {
      render(<PermissionSelector {...defaultProps} loading={true} />);

      expect(document.querySelector('.animate-spin')).toBeInTheDocument();
    });

    it('does not show content when loading', () => {
      render(<PermissionSelector {...defaultProps} loading={true} />);

      expect(screen.queryByText('Role (Optional)')).not.toBeInTheDocument();
    });
  });

  describe('mode: both (default)', () => {
    it('shows role selector', () => {
      render(<PermissionSelector {...defaultProps} />);

      expect(screen.getByText('Role (Optional)')).toBeInTheDocument();
    });

    it('shows permission selector', () => {
      render(<PermissionSelector {...defaultProps} />);

      expect(screen.getByText('Specific Permissions (Optional)')).toBeInTheDocument();
    });

    it('shows selected count', () => {
      render(<PermissionSelector {...defaultProps} selectedPermissionIds={['perm-1', 'perm-2']} />);

      // Count appears in header and in resource groups
      const selectedTexts = screen.getAllByText('2 selected');
      expect(selectedTexts.length).toBeGreaterThan(0);
    });

    it('shows warning when no role or permissions selected', () => {
      render(<PermissionSelector {...defaultProps} />);

      expect(screen.getByText(/Please select either a role or specific permissions/)).toBeInTheDocument();
    });

    it('hides warning when role is selected', () => {
      render(<PermissionSelector {...defaultProps} selectedRoleId="role-1" />);

      expect(screen.queryByText(/Please select either a role or specific permissions/)).not.toBeInTheDocument();
    });

    it('hides warning when permissions are selected', () => {
      render(<PermissionSelector {...defaultProps} selectedPermissionIds={['perm-1']} />);

      expect(screen.queryByText(/Please select either a role or specific permissions/)).not.toBeInTheDocument();
    });
  });

  describe('mode: role-only', () => {
    it('shows only role selector', () => {
      render(<PermissionSelector {...defaultProps} mode="role-only" />);

      expect(screen.getByText('Role (Optional)')).toBeInTheDocument();
      expect(screen.queryByText('Specific Permissions')).not.toBeInTheDocument();
    });
  });

  describe('mode: permissions-only', () => {
    it('shows only permission selector', () => {
      render(<PermissionSelector {...defaultProps} mode="permissions-only" />);

      expect(screen.queryByText('Role (Optional)')).not.toBeInTheDocument();
      expect(screen.getByText('Specific Permissions')).toBeInTheDocument();
    });
  });

  describe('role selection', () => {
    it('displays available roles in dropdown', () => {
      render(<PermissionSelector {...defaultProps} />);

      // First combobox is the role selector
      const selects = screen.getAllByRole('combobox');
      expect(selects[0]).toBeInTheDocument();

      expect(screen.getByText('Admin - Full access')).toBeInTheDocument();
      expect(screen.getByText('Editor - Can edit content')).toBeInTheDocument();
      expect(screen.getByText('Viewer - Read-only access')).toBeInTheDocument();
    });

    it('shows default option', () => {
      render(<PermissionSelector {...defaultProps} />);

      expect(screen.getByText('Select a role (optional)')).toBeInTheDocument();
    });

    it('calls onRoleChange when role selected', () => {
      const onRoleChange = jest.fn();
      render(<PermissionSelector {...defaultProps} onRoleChange={onRoleChange} />);

      // First combobox is the role selector
      const selects = screen.getAllByRole('combobox');
      fireEvent.change(selects[0], { target: { value: 'role-1' } });

      expect(onRoleChange).toHaveBeenCalledWith('role-1');
    });

    it('shows selected role message', () => {
      render(<PermissionSelector {...defaultProps} selectedRoleId="role-1" />);

      expect(screen.getByText(/Selected role provides base permissions/)).toBeInTheDocument();
    });

    it('disables role selector when disabled', () => {
      render(<PermissionSelector {...defaultProps} disabled={true} />);

      // First combobox is the role selector
      const selects = screen.getAllByRole('combobox');
      expect(selects[0]).toBeDisabled();
    });
  });

  describe('permission filtering', () => {
    it('shows search input', () => {
      render(<PermissionSelector {...defaultProps} />);

      expect(screen.getByPlaceholderText('Search permissions...')).toBeInTheDocument();
    });

    it('filters permissions by search term', () => {
      render(<PermissionSelector {...defaultProps} />);

      const searchInput = screen.getByPlaceholderText('Search permissions...');
      fireEvent.change(searchInput, { target: { value: 'billing' } });

      expect(screen.getByText('billing.read')).toBeInTheDocument();
      expect(screen.getByText('billing.update')).toBeInTheDocument();
      expect(screen.queryByText('users.read')).not.toBeInTheDocument();
    });

    it('filters permissions by description', () => {
      render(<PermissionSelector {...defaultProps} />);

      const searchInput = screen.getByPlaceholderText('Search permissions...');
      fireEvent.change(searchInput, { target: { value: 'Delete users' } });

      expect(screen.getByText('users.delete')).toBeInTheDocument();
      expect(screen.queryByText('users.read')).not.toBeInTheDocument();
    });

    it('shows resource filter dropdown', () => {
      render(<PermissionSelector {...defaultProps} />);

      expect(screen.getByText('All Resources')).toBeInTheDocument();
    });

    it('filters by selected resource', () => {
      render(<PermissionSelector {...defaultProps} />);

      const resourceFilter = screen.getAllByRole('combobox')[1];
      fireEvent.change(resourceFilter, { target: { value: 'billing' } });

      expect(screen.getByText('billing.read')).toBeInTheDocument();
      expect(screen.queryByText('users.read')).not.toBeInTheDocument();
    });

    it('shows empty state when no results', () => {
      render(<PermissionSelector {...defaultProps} />);

      const searchInput = screen.getByPlaceholderText('Search permissions...');
      fireEvent.change(searchInput, { target: { value: 'nonexistent' } });

      expect(screen.getByText('No permissions found matching your criteria')).toBeInTheDocument();
    });

    it('disables search when disabled', () => {
      render(<PermissionSelector {...defaultProps} disabled={true} />);

      expect(screen.getByPlaceholderText('Search permissions...')).toBeDisabled();
    });
  });

  describe('permission groups', () => {
    it('groups permissions by resource', () => {
      render(<PermissionSelector {...defaultProps} />);

      // Check resource headers
      expect(screen.getByText('users')).toBeInTheDocument();
      expect(screen.getByText('billing')).toBeInTheDocument();
      expect(screen.getByText('analytics')).toBeInTheDocument();
    });

    it('shows permission count per resource', () => {
      render(<PermissionSelector {...defaultProps} />);

      expect(screen.getByText('(3)')).toBeInTheDocument(); // users has 3
      expect(screen.getByText('(2)')).toBeInTheDocument(); // billing has 2
      expect(screen.getByText('(1)')).toBeInTheDocument(); // analytics has 1
    });

    it('shows selected count per resource', () => {
      render(<PermissionSelector {...defaultProps} selectedPermissionIds={['perm-1', 'perm-2']} />);

      // users resource has 2 selected
      const selectedTexts = screen.getAllByText(/\d+ selected/);
      expect(selectedTexts.some(el => el.textContent === '2 selected')).toBe(true);
    });
  });

  describe('individual permission selection', () => {
    it('displays permission keys', () => {
      render(<PermissionSelector {...defaultProps} />);

      expect(screen.getByText('users.read')).toBeInTheDocument();
      expect(screen.getByText('users.create')).toBeInTheDocument();
      expect(screen.getByText('billing.read')).toBeInTheDocument();
    });

    it('displays permission descriptions', () => {
      render(<PermissionSelector {...defaultProps} />);

      expect(screen.getByText('View users')).toBeInTheDocument();
      expect(screen.getByText('Create users')).toBeInTheDocument();
    });

    it('displays action badges', () => {
      render(<PermissionSelector {...defaultProps} />);

      expect(screen.getAllByText('read').length).toBeGreaterThan(0);
      expect(screen.getAllByText('create').length).toBeGreaterThan(0);
      expect(screen.getByText('delete')).toBeInTheDocument();
      expect(screen.getByText('update')).toBeInTheDocument();
      expect(screen.getByText('export')).toBeInTheDocument();
    });

    it('calls onPermissionChange when permission clicked', () => {
      const onPermissionChange = jest.fn();
      render(<PermissionSelector {...defaultProps} onPermissionChange={onPermissionChange} />);

      const permissionRow = screen.getByText('users.read').closest('div[class*="cursor-pointer"]');
      fireEvent.click(permissionRow!);

      expect(onPermissionChange).toHaveBeenCalledWith(['perm-1']);
    });

    it('removes permission when already selected', () => {
      const onPermissionChange = jest.fn();
      render(
        <PermissionSelector
          {...defaultProps}
          selectedPermissionIds={['perm-1']}
          onPermissionChange={onPermissionChange}
        />
      );

      const permissionRow = screen.getByText('users.read').closest('div[class*="cursor-pointer"]');
      fireEvent.click(permissionRow!);

      expect(onPermissionChange).toHaveBeenCalledWith([]);
    });

    it('does not toggle permission when disabled', () => {
      const onPermissionChange = jest.fn();
      render(<PermissionSelector {...defaultProps} onPermissionChange={onPermissionChange} disabled={true} />);

      const permissionRow = screen.getByText('users.read').closest('div[class*="cursor-pointer"]');
      fireEvent.click(permissionRow!);

      expect(onPermissionChange).not.toHaveBeenCalled();
    });
  });

  describe('select all in resource', () => {
    it('selects all permissions in resource when resource header clicked', () => {
      const onPermissionChange = jest.fn();
      render(<PermissionSelector {...defaultProps} onPermissionChange={onPermissionChange} />);

      const usersHeader = screen.getByText('users').closest('div[class*="cursor-pointer"]');
      fireEvent.click(usersHeader!);

      expect(onPermissionChange).toHaveBeenCalledWith(['perm-1', 'perm-2', 'perm-3']);
    });

    it('deselects all when all are already selected', () => {
      const onPermissionChange = jest.fn();
      render(
        <PermissionSelector
          {...defaultProps}
          selectedPermissionIds={['perm-1', 'perm-2', 'perm-3']}
          onPermissionChange={onPermissionChange}
        />
      );

      const usersHeader = screen.getByText('users').closest('div[class*="cursor-pointer"]');
      fireEvent.click(usersHeader!);

      expect(onPermissionChange).toHaveBeenCalledWith([]);
    });

    it('keeps other resource selections when toggling', () => {
      const onPermissionChange = jest.fn();
      render(
        <PermissionSelector
          {...defaultProps}
          selectedPermissionIds={['perm-4']}
          onPermissionChange={onPermissionChange}
        />
      );

      const usersHeader = screen.getByText('users').closest('div[class*="cursor-pointer"]');
      fireEvent.click(usersHeader!);

      expect(onPermissionChange).toHaveBeenCalledWith(['perm-4', 'perm-1', 'perm-2', 'perm-3']);
    });

    it('does not toggle when disabled', () => {
      const onPermissionChange = jest.fn();
      render(<PermissionSelector {...defaultProps} onPermissionChange={onPermissionChange} disabled={true} />);

      const usersHeader = screen.getByText('users').closest('div[class*="cursor-pointer"]');
      fireEvent.click(usersHeader!);

      expect(onPermissionChange).not.toHaveBeenCalled();
    });
  });

  describe('visual indicators', () => {
    it('shows check icon when all resource permissions selected', () => {
      render(
        <PermissionSelector
          {...defaultProps}
          selectedPermissionIds={['perm-1', 'perm-2', 'perm-3']}
        />
      );

      // The users resource should show a check icon
      const usersSection = screen.getByText('users').closest('div[class*="border-b"]');
      expect(usersSection?.querySelector('.text-theme-success')).toBeInTheDocument();
    });

    it('shows partial indicator when some permissions selected', () => {
      render(
        <PermissionSelector
          {...defaultProps}
          selectedPermissionIds={['perm-1']}
        />
      );

      // The users resource should show partial indicator
      const usersSection = screen.getByText('users').closest('div[class*="border-b"]');
      expect(usersSection?.querySelector('.bg-theme-info')).toBeInTheDocument();
    });

    it('highlights selected permission rows', () => {
      render(
        <PermissionSelector
          {...defaultProps}
          selectedPermissionIds={['perm-1']}
        />
      );

      const permissionRow = screen.getByText('users.read').closest('div[class*="cursor-pointer"]');
      expect(permissionRow).toHaveClass('bg-theme-info-background');
    });
  });
});
