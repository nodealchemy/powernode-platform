import { render, screen, fireEvent } from '@testing-library/react';
import { InviteTeamMemberModal } from './InviteTeamMemberModal';

// Mock useForm hook
const mockReset = jest.fn();
const mockSetValue = jest.fn();
const mockHandleBlur = jest.fn();
const mockHandleSubmit = jest.fn((e: any) => {
  e?.preventDefault?.();
  return Promise.resolve();
});

jest.mock('@/shared/hooks/useForm', () => ({
  useForm: () => ({
    values: {
      email: '',
      role: 'account.member',
      message: ''
    },
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
  }),
  FormValidationRules: {}
}));

// Mock invitations API
const mockInviteUser = jest.fn();
jest.mock('@/shared/services/account/invitationsApi', () => ({
  invitationsApi: {
    inviteUser: (...args: any[]) => mockInviteUser(...args)
  }
}));

// Mock Modal component
jest.mock('@/shared/components/ui/Modal', () => ({
  Modal: ({ isOpen, onClose, title, subtitle, children }: any) =>
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
  FormField: ({ label, value, onChange, placeholder, type, disabled, error }: any) => (
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
  Button: ({ children, onClick, type, disabled, loading, variant }: any) => (
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

  beforeEach(() => {
    jest.clearAllMocks();
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

    it('renders email field', () => {
      render(<InviteTeamMemberModal {...defaultProps} />);

      expect(screen.getByText('Email Address')).toBeInTheDocument();
    });

    it('renders role selection', () => {
      render(<InviteTeamMemberModal {...defaultProps} />);

      expect(screen.getByText('Role *')).toBeInTheDocument();
    });

    it('renders message field', () => {
      render(<InviteTeamMemberModal {...defaultProps} />);

      expect(screen.getByText('Personal Message (Optional)')).toBeInTheDocument();
    });
  });

  describe('role options', () => {
    it('displays Account Manager option', () => {
      render(<InviteTeamMemberModal {...defaultProps} />);

      expect(screen.getByText('Account Manager')).toBeInTheDocument();
      expect(screen.getByText('Full account management access')).toBeInTheDocument();
    });

    it('displays Billing Manager option', () => {
      render(<InviteTeamMemberModal {...defaultProps} />);

      expect(screen.getByText('Billing Manager')).toBeInTheDocument();
      expect(screen.getByText('Can manage billing and payments')).toBeInTheDocument();
    });

    it('displays Account Member option', () => {
      render(<InviteTeamMemberModal {...defaultProps} />);

      expect(screen.getByText('Account Member')).toBeInTheDocument();
      expect(screen.getByText('Standard access to resources')).toBeInTheDocument();
    });

    it('has radio buttons for role selection', () => {
      render(<InviteTeamMemberModal {...defaultProps} />);

      const radioButtons = screen.getAllByRole('radio');
      expect(radioButtons.length).toBe(3);
    });

    it('defaults to account.member role', () => {
      render(<InviteTeamMemberModal {...defaultProps} />);

      const memberRadio = screen.getByDisplayValue('account.member');
      expect(memberRadio).toBeChecked();
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
      expect(screen.getByText(/They'll need to create an account/)).toBeInTheDocument();
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

    it('calls form reset when Cancel clicked', () => {
      render(<InviteTeamMemberModal {...defaultProps} />);

      fireEvent.click(screen.getByText('Cancel'));

      expect(mockReset).toHaveBeenCalled();
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

  describe('role selection', () => {
    it('calls setValue when role changed', () => {
      render(<InviteTeamMemberModal {...defaultProps} />);

      const managerRadio = screen.getByDisplayValue('account.manager');
      fireEvent.click(managerRadio);

      expect(mockSetValue).toHaveBeenCalledWith('role', 'account.manager');
    });
  });

  describe('accountId prop', () => {
    it('accepts accountId prop', () => {
      render(<InviteTeamMemberModal {...defaultProps} accountId="account-123" />);

      expect(screen.getByTestId('modal')).toBeInTheDocument();
    });
  });
});
