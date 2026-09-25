import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { InviteTeamMemberModal } from './InviteTeamMemberModal';

// Mock useForm hook. `capturedOnSubmit` exposes the component's own
// handleInvite (the mapping from form values -> the real InviteUserRequest
// shape) so the "exact POST body" tests below can call it directly, without
// needing checkbox-toggle plumbing to work through a mocked, non-reactive
// useForm.
const mockReset = jest.fn();
const mockSetValue = jest.fn();
const mockHandleBlur = jest.fn();
const mockHandleSubmit = jest.fn((e?: { preventDefault?: () => void }) => {
  e?.preventDefault?.();
  return Promise.resolve();
});

let capturedOnSubmit: ((values: unknown) => Promise<void> | void) | null = null;
let mockFormValues = {
  email: '',
  first_name: '',
  last_name: '',
  role_names: [] as string[]
};

jest.mock('@/shared/hooks/useForm', () => ({
  useForm: (options: { onSubmit: (values: unknown) => Promise<void> | void }) => {
    capturedOnSubmit = options.onSubmit;
    return {
      values: mockFormValues,
      errors: {},
      touched: {},
      isSubmitting: false,
      isValid: true,
      handleChange: jest.fn(),
      handleBlur: mockHandleBlur,
      handleSubmit: mockHandleSubmit,
      setValue: mockSetValue,
      setValues: jest.fn(),
      reset: mockReset,
      validateField: jest.fn(),
      validateForm: jest.fn(),
      getFieldProps: (name: string) => ({
        name,
        value: '',
        onChange: jest.fn(),
        onBlur: mockHandleBlur
      })
    };
  },
  FormValidationRules: {}
}));

// Mock invitations API
const mockInviteUser = jest.fn();
jest.mock('@/shared/services/account/invitationsApi', () => ({
  invitationsApi: {
    inviteUser: (...args: unknown[]) => mockInviteUser(...args)
  }
}));

// Mock usersApi -- the real assignable-roles source (/roles/assignable), the
// same one UserRolesModal and UsersContent already use. fc-06: the modal used
// to hardcode three fake role names (account.member etc.) that the server's
// Role.for_account lookup always rejected as "Unknown roles".
const mockGetAvailableRoles = jest.fn();
jest.mock('@/features/account/users/services/usersApi', () => ({
  usersApi: {
    getAvailableRoles: (...args: unknown[]) => mockGetAvailableRoles(...args)
  }
}));

// Mock Modal component
jest.mock('@/shared/components/ui/Modal', () => ({
  Modal: ({ isOpen, onClose, title, subtitle, children }: { isOpen: boolean; onClose: () => void; title?: string; subtitle?: string; children?: React.ReactNode }) =>
    isOpen ? (
      <div data-testid="modal">
        <h2>{title}</h2>
        <p>{subtitle}</p>
        {children}
        <button onClick={onClose}>Close Modal</button>
      </div>
    ) : null
}));

// Mock FormField component
jest.mock('@/shared/components/ui/FormField', () => ({
  FormField: ({ label, value, onChange, placeholder, type, disabled, error }: { label?: string; value?: string; onChange: (value: string) => void; placeholder?: string; type?: string; disabled?: boolean; error?: string }) => (
    <div>
      <label>{label}</label>
      {type === 'textarea' ? (
        <textarea
          value={value}
          onChange={(e) => onChange(e.target.value)}
          placeholder={placeholder}
          disabled={disabled}
          data-testid={`input-${label}`}
        />
      ) : (
        <input
          type={type}
          value={value}
          onChange={(e) => onChange(e.target.value)}
          placeholder={placeholder}
          disabled={disabled}
          data-testid={`input-${label}`}
        />
      )}
      {error && <span className="error">{error}</span>}
    </div>
  )
}));

// Mock Button component
jest.mock('@/shared/components/ui/Button', () => ({
  Button: ({ children, onClick, type, disabled, loading, variant }: { children?: React.ReactNode; onClick?: () => void; type?: 'button' | 'submit' | 'reset'; disabled?: boolean; loading?: boolean; variant?: string }) => (
    <button
      type={type || 'button'}
      onClick={onClick}
      disabled={disabled || loading}
      data-variant={variant}
      data-loading={loading}
    >
      {children}
    </button>
  )
}));

describe('InviteTeamMemberModal', () => {
  const defaultProps = {
    isOpen: true,
    onClose: jest.fn(),
    onInviteSent: jest.fn()
  };

  const mockRoles = [
    { value: 'account.admin', label: 'Account Admin', description: 'Full account management access', canAssign: true },
    { value: 'account.member', label: 'Account Member', description: 'Standard access to resources', canAssign: true },
    { value: 'billing.admin', label: 'Billing Admin', description: 'Restricted role', canAssign: false }
  ];

  beforeEach(() => {
    jest.clearAllMocks();
    capturedOnSubmit = null;
    mockFormValues = { email: '', first_name: '', last_name: '', role_names: [] };
    mockGetAvailableRoles.mockResolvedValue(mockRoles);
    mockInviteUser.mockResolvedValue({ success: true, data: {} });
  });

  describe('rendering', () => {
    it('renders modal when open', () => {
      render(<InviteTeamMemberModal {...defaultProps} />);

      expect(screen.getByTestId('modal')).toBeInTheDocument();
    });

    it('does not render when closed', () => {
      render(<InviteTeamMemberModal {...defaultProps} isOpen={false} />);

      expect(screen.queryByTestId('modal')).not.toBeInTheDocument();
    });

    it('renders modal title', () => {
      render(<InviteTeamMemberModal {...defaultProps} />);

      expect(screen.getByText('Invite Team Member')).toBeInTheDocument();
    });

    it('renders modal subtitle', () => {
      render(<InviteTeamMemberModal {...defaultProps} />);

      expect(screen.getByText('Send an invitation to join your team')).toBeInTheDocument();
    });

    it('renders first and last name fields', () => {
      render(<InviteTeamMemberModal {...defaultProps} />);

      expect(screen.getByText('First Name')).toBeInTheDocument();
      expect(screen.getByText('Last Name')).toBeInTheDocument();
    });

    it('renders email field', () => {
      render(<InviteTeamMemberModal {...defaultProps} />);

      expect(screen.getByText('Email Address')).toBeInTheDocument();
    });

    it('renders a Roles label, not the old singular Role', () => {
      render(<InviteTeamMemberModal {...defaultProps} />);

      expect(screen.getByText('Roles *')).toBeInTheDocument();
    });

    it('does not render a message field -- the server has no message column or param', () => {
      render(<InviteTeamMemberModal {...defaultProps} />);

      expect(screen.queryByText('Personal Message (Optional)')).not.toBeInTheDocument();
    });
  });

  describe('role options (fc-06: loaded from usersApi.getAvailableRoles, not hardcoded)', () => {
    it('fetches assignable roles on open', async () => {
      render(<InviteTeamMemberModal {...defaultProps} />);

      await waitFor(() => {
        expect(mockGetAvailableRoles).toHaveBeenCalled();
      });
    });

    it('displays the real roles the server returned', async () => {
      render(<InviteTeamMemberModal {...defaultProps} />);

      expect(await screen.findByText('Account Admin')).toBeInTheDocument();
      expect(screen.getByText('Account Member')).toBeInTheDocument();
    });

    it('excludes roles the server marked as not assignable by this operator', async () => {
      render(<InviteTeamMemberModal {...defaultProps} />);

      await screen.findByText('Account Admin');
      expect(screen.queryByText('Billing Admin')).not.toBeInTheDocument();
    });

    it('renders checkboxes, not radio buttons, since multiple roles can be granted', async () => {
      render(<InviteTeamMemberModal {...defaultProps} />);

      await screen.findByText('Account Admin');
      expect(screen.getAllByRole('checkbox').length).toBe(2);
      expect(screen.queryAllByRole('radio').length).toBe(0);
    });

    it('shows a load error and no crash when the roles fetch fails', async () => {
      mockGetAvailableRoles.mockRejectedValue(new Error('network error'));

      render(<InviteTeamMemberModal {...defaultProps} />);

      expect(await screen.findByRole('alert')).toHaveTextContent(/failed to load assignable roles/i);
    });
  });

  describe('what happens next section', () => {
    it('displays what happens next header', () => {
      render(<InviteTeamMemberModal {...defaultProps} />);

      expect(screen.getByText('What happens next?')).toBeInTheDocument();
    });

    it('displays invitation steps', () => {
      render(<InviteTeamMemberModal {...defaultProps} />);

      expect(screen.getByText(/The invitee will receive an email/)).toBeInTheDocument();
      expect(screen.getByText(/Invitations expire after 7 days/)).toBeInTheDocument();
    });
  });

  describe('buttons', () => {
    it('renders Cancel button', () => {
      render(<InviteTeamMemberModal {...defaultProps} />);

      expect(screen.getByText('Cancel')).toBeInTheDocument();
    });

    it('renders Send Invitation button', () => {
      render(<InviteTeamMemberModal {...defaultProps} />);

      expect(screen.getByText('Send Invitation')).toBeInTheDocument();
    });

    it('calls onClose when Cancel clicked', () => {
      const onClose = jest.fn();
      render(<InviteTeamMemberModal {...defaultProps} onClose={onClose} />);

      fireEvent.click(screen.getByText('Cancel'));

      expect(mockReset).toHaveBeenCalled();
      expect(onClose).toHaveBeenCalled();
    });
  });

  describe('form submission', () => {
    it('renders form element', () => {
      const { container } = render(<InviteTeamMemberModal {...defaultProps} />);

      const form = container.querySelector('form');
      expect(form).toBeInTheDocument();
    });

    it('calls handleSubmit on form submit', () => {
      const { container } = render(<InviteTeamMemberModal {...defaultProps} />);

      const form = container.querySelector('form');
      fireEvent.submit(form!);

      expect(mockHandleSubmit).toHaveBeenCalled();
    });
  });

  // fc-06: the real request shape, asserted directly against the component's
  // own onSubmit handler (captured via the mocked useForm), so this pins the
  // mapping regardless of the checkbox-toggle DOM plumbing above.
  describe('the exact request body (fc-06 review requirement)', () => {
    it('POSTs {invitation:{email,first_name,last_name,role_names}} via invitationsApi.inviteUser', async () => {
      render(<InviteTeamMemberModal {...defaultProps} />);
      await screen.findByText('Account Admin');

      expect(capturedOnSubmit).not.toBeNull();
      await capturedOnSubmit!({
        email: 'new@example.com',
        first_name: 'Jane',
        last_name: 'Doe',
        role_names: [ 'account.admin', 'account.member' ]
      });

      expect(mockInviteUser).toHaveBeenCalledWith({
        email: 'new@example.com',
        first_name: 'Jane',
        last_name: 'Doe',
        role_names: [ 'account.admin', 'account.member' ]
      });
    });

    it('never sends the empty first_name/last_name the old mapping hardcoded', async () => {
      render(<InviteTeamMemberModal {...defaultProps} />);
      await screen.findByText('Account Admin');

      await capturedOnSubmit!({
        email: 'new@example.com',
        first_name: 'Jane',
        last_name: 'Doe',
        role_names: [ 'account.member' ]
      });

      const sentRequest = mockInviteUser.mock.calls[0][0];
      expect(sentRequest.first_name).not.toBe('');
      expect(sentRequest.last_name).not.toBe('');
    });

    it('never sends a message field -- the server has no support for one', async () => {
      render(<InviteTeamMemberModal {...defaultProps} />);
      await screen.findByText('Account Admin');

      await capturedOnSubmit!({
        email: 'new@example.com',
        first_name: 'Jane',
        last_name: 'Doe',
        role_names: [ 'account.member' ]
      });

      const sentRequest = mockInviteUser.mock.calls[0][0];
      expect(sentRequest).not.toHaveProperty('message');
    });

    it('calls onInviteSent and onClose when the invite succeeds', async () => {
      const onInviteSent = jest.fn();
      const onClose = jest.fn();
      render(<InviteTeamMemberModal {...defaultProps} onInviteSent={onInviteSent} onClose={onClose} />);
      await screen.findByText('Account Admin');

      await capturedOnSubmit!({
        email: 'new@example.com',
        first_name: 'Jane',
        last_name: 'Doe',
        role_names: [ 'account.member' ]
      });

      expect(onInviteSent).toHaveBeenCalled();
      expect(onClose).toHaveBeenCalled();
    });

    it('throws (surfacing the server reason through useForm) when the invite is rejected', async () => {
      mockInviteUser.mockResolvedValue({ success: false, message: 'Unknown roles: account.ceo' });
      render(<InviteTeamMemberModal {...defaultProps} />);
      await screen.findByText('Account Admin');

      await expect(capturedOnSubmit!({
        email: 'new@example.com',
        first_name: 'Jane',
        last_name: 'Doe',
        role_names: [ 'account.ceo' ]
      })).rejects.toThrow('Unknown roles: account.ceo');
    });
  });
});
