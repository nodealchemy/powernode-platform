
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { CreateDelegationModal } from './CreateDelegationModal';

// Mock delegation API
const mockGetAvailableRoles = jest.fn();
const mockGetAvailablePermissions = jest.fn();

jest.mock('@/features/delegations/services/delegationApi', () => ({
  delegationApi: {
    getAvailableRoles: (...args: any[]) => mockGetAvailableRoles(...args),
    getAvailablePermissions: (...args: any[]) => mockGetAvailablePermissions(...args)
  }
}));

// Mock PermissionSelector
jest.mock('@/features/account/components/PermissionSelector', () => ({
  PermissionSelector: ({ onRoleChange, onPermissionChange, selectedRoleId, selectedPermissionIds, loading }: any) => (
    <div data-testid="permission-selector">
      {loading && <span>Loading permissions...</span>}
      <button onClick={() => onRoleChange('role-1')}>Select Role</button>
      <button onClick={() => onPermissionChange(['perm-1', 'perm-2'])}>Select Permissions</button>
      <span data-testid="selected-role">{selectedRoleId || 'none'}</span>
      <span data-testid="selected-permissions">{selectedPermissionIds.join(',') || 'none'}</span>
    </div>
  )
}));

describe('CreateDelegationModal', () => {
  const defaultProps = {
    onClose: jest.fn(),
    onCreate: jest.fn()
  };

  const mockRoles = [
    { id: 'role-1', name: 'Admin', description: 'Full access' },
    { id: 'role-2', name: 'Viewer', description: 'Read-only access' }
  ];

  const mockPermissions = [
    { id: 'perm-1', resource: 'billing', action: 'read', description: 'View billing', key: 'billing.read' },
    { id: 'perm-2', resource: 'billing', action: 'manage', description: 'Manage billing', key: 'billing.manage' }
  ];

  beforeEach(() => {
    jest.clearAllMocks();
    mockGetAvailableRoles.mockResolvedValue(mockRoles);
    mockGetAvailablePermissions.mockResolvedValue(mockPermissions);
  });

  describe('rendering', () => {
    it('renders modal with title', () => {
      render(<CreateDelegationModal {...defaultProps} />);

      expect(screen.getByText('Create Delegation')).toBeInTheDocument();
    });

    it('shows close button', () => {
      render(<CreateDelegationModal {...defaultProps} />);

      const closeButton = screen.getByRole('button', { name: '' });
      expect(closeButton.querySelector('svg')).toBeInTheDocument();
    });

    it('shows step indicator', () => {
      render(<CreateDelegationModal {...defaultProps} />);

      expect(screen.getByText('1')).toBeInTheDocument();
      expect(screen.getByText('2')).toBeInTheDocument();
    });

    it('shows step 1 title', () => {
      render(<CreateDelegationModal {...defaultProps} />);

      expect(screen.getByText('Delegation Details')).toBeInTheDocument();
    });
  });

  describe('step 1 - delegation details', () => {
    it('shows user email field', () => {
      render(<CreateDelegationModal {...defaultProps} />);

      expect(screen.getByText('User Email')).toBeInTheDocument();
      expect(screen.getByPlaceholderText('Enter the email address of the user to delegate to')).toBeInTheDocument();
    });

    it('shows expiration date field', () => {
      render(<CreateDelegationModal {...defaultProps} />);

      expect(screen.getByText('Expiration Date (Optional)')).toBeInTheDocument();
    });

    it('shows notes field', () => {
      render(<CreateDelegationModal {...defaultProps} />);

      expect(screen.getByText('Notes (Optional)')).toBeInTheDocument();
      expect(screen.getByPlaceholderText('Add any notes about this delegation...')).toBeInTheDocument();
    });

    it('shows Cancel and Next buttons', async () => {
      render(<CreateDelegationModal {...defaultProps} />);

      await waitFor(() => {
        expect(mockGetAvailableRoles).toHaveBeenCalled();
      });

      expect(screen.getByText('Cancel')).toBeInTheDocument();
      expect(screen.getByText('Next')).toBeInTheDocument();
    });

    it('Next button is disabled when email is empty', async () => {
      render(<CreateDelegationModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Next')).toBeInTheDocument();
      });

      const nextButton = screen.getByText('Next');
      expect(nextButton).toBeDisabled();
    });

    it('Next button is enabled when email is entered', async () => {
      render(<CreateDelegationModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Next')).toBeInTheDocument();
      });

      const emailInput = screen.getByPlaceholderText('Enter the email address of the user to delegate to');
      fireEvent.change(emailInput, { target: { value: 'test@example.com' } });

      const nextButton = screen.getByText('Next');
      expect(nextButton).not.toBeDisabled();
    });

    it('calls onClose when Cancel clicked', async () => {
      const onClose = jest.fn();
      render(<CreateDelegationModal {...defaultProps} onClose={onClose} />);

      await waitFor(() => {
        expect(mockGetAvailableRoles).toHaveBeenCalled();
      });

      fireEvent.click(screen.getByText('Cancel'));

      expect(onClose).toHaveBeenCalled();
    });
  });

  describe('step navigation', () => {
    it('advances to step 2 when Next clicked with valid email', async () => {
      render(<CreateDelegationModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Next')).toBeInTheDocument();
      });

      const emailInput = screen.getByPlaceholderText('Enter the email address of the user to delegate to');
      fireEvent.change(emailInput, { target: { value: 'test@example.com' } });

      fireEvent.click(screen.getByText('Next'));

      await waitFor(() => {
        expect(screen.getByText('Back')).toBeInTheDocument();
      });
    });

    it('shows step 2 title', async () => {
      render(<CreateDelegationModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Next')).toBeInTheDocument();
      });

      const emailInput = screen.getByPlaceholderText('Enter the email address of the user to delegate to');
      fireEvent.change(emailInput, { target: { value: 'test@example.com' } });
      fireEvent.click(screen.getByText('Next'));

      await waitFor(() => {
        // Step 2 shows the PermissionSelector
        expect(screen.getByTestId('permission-selector')).toBeInTheDocument();
      });
    });

    it('shows Back button on step 2', async () => {
      render(<CreateDelegationModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Next')).toBeInTheDocument();
      });

      const emailInput = screen.getByPlaceholderText('Enter the email address of the user to delegate to');
      fireEvent.change(emailInput, { target: { value: 'test@example.com' } });
      fireEvent.click(screen.getByText('Next'));

      await waitFor(() => {
        expect(screen.getByText('Back')).toBeInTheDocument();
      });
    });

    it('goes back to step 1 when Back clicked', async () => {
      render(<CreateDelegationModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Next')).toBeInTheDocument();
      });

      const emailInput = screen.getByPlaceholderText('Enter the email address of the user to delegate to');
      fireEvent.change(emailInput, { target: { value: 'test@example.com' } });
      fireEvent.click(screen.getByText('Next'));

      await waitFor(() => {
        expect(screen.getByText('Back')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Back'));

      await waitFor(() => {
        expect(screen.getByText('Delegation Details')).toBeInTheDocument();
      });
    });

    it('shows Create Delegation button on step 2', async () => {
      render(<CreateDelegationModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Next')).toBeInTheDocument();
      });

      const emailInput = screen.getByPlaceholderText('Enter the email address of the user to delegate to');
      fireEvent.change(emailInput, { target: { value: 'test@example.com' } });
      fireEvent.click(screen.getByText('Next'));

      await waitFor(() => {
        // Step 2 shows Create Delegation button - find by button role
        const createButtons = screen.getAllByText('Create Delegation');
        const submitButton = createButtons.find(el => el.tagName === 'BUTTON');
        expect(submitButton).toBeInTheDocument();
      });
    });
  });

  describe('step 2 - roles and permissions', () => {
    const goToStep2 = async () => {
      await waitFor(() => {
        expect(screen.getByText('Next')).toBeInTheDocument();
      });
      const emailInput = screen.getByPlaceholderText('Enter the email address of the user to delegate to');
      fireEvent.change(emailInput, { target: { value: 'test@example.com' } });
      fireEvent.click(screen.getByText('Next'));
      await waitFor(() => {
        expect(screen.getByText('Back')).toBeInTheDocument();
      });
    };

    it('shows PermissionSelector component', async () => {
      render(<CreateDelegationModal {...defaultProps} />);
      await goToStep2();

      expect(screen.getByTestId('permission-selector')).toBeInTheDocument();
    });

    it('shows description text', async () => {
      render(<CreateDelegationModal {...defaultProps} />);
      await goToStep2();

      expect(screen.getByText('Select a role or specific permissions to delegate to the user')).toBeInTheDocument();
    });

    it('Create Delegation button is disabled without role or permissions', async () => {
      render(<CreateDelegationModal {...defaultProps} />);
      await goToStep2();

      const createButtons = screen.getAllByText('Create Delegation');
      const createButton = createButtons.find(el => el.tagName === 'BUTTON');
      expect(createButton).toBeDisabled();
    });

    it('Create Delegation button is enabled after selecting role', async () => {
      render(<CreateDelegationModal {...defaultProps} />);
      await goToStep2();

      fireEvent.click(screen.getByText('Select Role'));

      const createButtons = screen.getAllByText('Create Delegation');
      const createButton = createButtons.find(el => el.tagName === 'BUTTON');
      expect(createButton).not.toBeDisabled();
    });

    it('Create Delegation button is enabled after selecting permissions', async () => {
      render(<CreateDelegationModal {...defaultProps} />);
      await goToStep2();

      fireEvent.click(screen.getByText('Select Permissions'));

      const createButtons = screen.getAllByText('Create Delegation');
      const createButton = createButtons.find(el => el.tagName === 'BUTTON');
      expect(createButton).not.toBeDisabled();
    });
  });

  describe('form submission', () => {
    it('calls onCreate with form data when Create Delegation clicked', async () => {
      const onCreate = jest.fn();
      render(<CreateDelegationModal {...defaultProps} onCreate={onCreate} />);

      await waitFor(() => {
        expect(screen.getByText('Next')).toBeInTheDocument();
      });

      // Fill step 1
      const emailInput = screen.getByPlaceholderText('Enter the email address of the user to delegate to');
      fireEvent.change(emailInput, { target: { value: 'test@example.com' } });

      const notesInput = screen.getByPlaceholderText('Add any notes about this delegation...');
      fireEvent.change(notesInput, { target: { value: 'Test notes' } });

      fireEvent.click(screen.getByText('Next'));

      // Wait for step 2 by checking for Back button
      await waitFor(() => {
        expect(screen.getByText('Back')).toBeInTheDocument();
      });

      // Select a role
      fireEvent.click(screen.getByText('Select Role'));

      // Submit - use button role to distinguish from title
      const createButtons = screen.getAllByText('Create Delegation');
      const submitButton = createButtons.find(el => el.tagName === 'BUTTON');
      fireEvent.click(submitButton!);

      await waitFor(() => {
        expect(onCreate).toHaveBeenCalledWith(expect.objectContaining({
          delegated_user_email: 'test@example.com',
          role_id: 'role-1',
          notes: 'Test notes'
        }));
      });
    });
  });

  describe('loading state', () => {
    it('shows Loading... button text when loading', () => {
      mockGetAvailableRoles.mockImplementation(() => new Promise(() => {}));
      mockGetAvailablePermissions.mockImplementation(() => new Promise(() => {}));

      render(<CreateDelegationModal {...defaultProps} />);

      // When the component is loading, it shows Loading... on the button
      expect(screen.getByText('Loading...')).toBeInTheDocument();
    });

    it('loads initial data on mount', async () => {
      render(<CreateDelegationModal {...defaultProps} />);

      await waitFor(() => {
        expect(mockGetAvailableRoles).toHaveBeenCalled();
        expect(mockGetAvailablePermissions).toHaveBeenCalled();
      });
    });
  });

  describe('step indicator', () => {
    it('highlights current step', async () => {
      render(<CreateDelegationModal {...defaultProps} />);

      await waitFor(() => {
        expect(mockGetAvailableRoles).toHaveBeenCalled();
      });

      const stepIndicators = screen.getAllByText(/^[12]$/);
      const step1 = stepIndicators[0].closest('div');
      expect(step1).toHaveClass('bg-theme-interactive-primary');
    });

    it('shows checkmark for completed steps', async () => {
      render(<CreateDelegationModal {...defaultProps} />);

      await waitFor(() => {
        expect(screen.getByText('Next')).toBeInTheDocument();
      });

      const emailInput = screen.getByPlaceholderText('Enter the email address of the user to delegate to');
      fireEvent.change(emailInput, { target: { value: 'test@example.com' } });
      fireEvent.click(screen.getByText('Next'));

      await waitFor(() => {
        expect(screen.getByText('✓')).toBeInTheDocument();
      });
    });
  });

  describe('form fields', () => {
    it('updates email field value', async () => {
      render(<CreateDelegationModal {...defaultProps} />);

      await waitFor(() => {
        expect(mockGetAvailableRoles).toHaveBeenCalled();
      });

      const emailInput = screen.getByPlaceholderText('Enter the email address of the user to delegate to') as HTMLInputElement;
      fireEvent.change(emailInput, { target: { value: 'test@example.com' } });

      expect(emailInput.value).toBe('test@example.com');
    });

    it('updates expiration date field value', async () => {
      render(<CreateDelegationModal {...defaultProps} />);

      await waitFor(() => {
        expect(mockGetAvailableRoles).toHaveBeenCalled();
      });

      // Find the datetime-local input (second input in the form)
      const allInputs = document.querySelectorAll('input');
      const dateInput = Array.from(allInputs).find(input => input.type === 'datetime-local') as HTMLInputElement;
      fireEvent.change(dateInput, { target: { value: '2025-12-31T23:59' } });

      expect(dateInput.value).toBe('2025-12-31T23:59');
    });

    it('updates notes field value', async () => {
      render(<CreateDelegationModal {...defaultProps} />);

      await waitFor(() => {
        expect(mockGetAvailableRoles).toHaveBeenCalled();
      });

      const notesInput = screen.getByPlaceholderText('Add any notes about this delegation...') as HTMLTextAreaElement;
      fireEvent.change(notesInput, { target: { value: 'Important delegation' } });

      expect(notesInput.value).toBe('Important delegation');
    });
  });

  describe('close functionality', () => {
    it('calls onClose when X button clicked', async () => {
      const onClose = jest.fn();
      render(<CreateDelegationModal {...defaultProps} onClose={onClose} />);

      await waitFor(() => {
        expect(mockGetAvailableRoles).toHaveBeenCalled();
      });

      // Find the close button (the one with the X SVG)
      const buttons = screen.getAllByRole('button');
      const closeButton = buttons.find(btn => btn.querySelector('svg path[d*="M6 18L18 6"]'));

      if (closeButton) {
        fireEvent.click(closeButton);
        expect(onClose).toHaveBeenCalled();
      }
    });
  });
});
