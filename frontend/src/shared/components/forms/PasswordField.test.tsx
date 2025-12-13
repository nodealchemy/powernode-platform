import { render, screen, fireEvent } from '@testing-library/react';
import { PasswordField } from './PasswordField';

describe('PasswordField', () => {
  const defaultProps = {
    name: 'password',
    value: '',
    onChange: jest.fn(),
    onBlur: jest.fn(),
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('rendering', () => {
    it('renders with default label', () => {
      render(<PasswordField {...defaultProps} />);

      expect(screen.getByText('Password')).toBeInTheDocument();
    });

    it('renders with custom label', () => {
      render(<PasswordField {...defaultProps} label="New Password" />);

      expect(screen.getByText('New Password')).toBeInTheDocument();
    });

    it('renders without label when label is empty', () => {
      render(<PasswordField {...defaultProps} label="" />);

      expect(screen.queryByText('Password')).not.toBeInTheDocument();
    });

    it('renders input with correct name and id', () => {
      render(<PasswordField {...defaultProps} />);

      const input = screen.getByLabelText('Password');
      expect(input).toHaveAttribute('name', 'password');
      expect(input).toHaveAttribute('id', 'password');
    });

    it('renders placeholder', () => {
      render(<PasswordField {...defaultProps} placeholder="Enter password" />);

      expect(screen.getByPlaceholderText('Enter password')).toBeInTheDocument();
    });

    it('uses default placeholder when not provided', () => {
      render(<PasswordField {...defaultProps} />);

      expect(screen.getByPlaceholderText('Enter your password')).toBeInTheDocument();
    });

    it('renders required indicator when required', () => {
      render(<PasswordField {...defaultProps} required />);

      expect(screen.getByText('*')).toBeInTheDocument();
    });

    it('applies custom className', () => {
      const { container } = render(
        <PasswordField {...defaultProps} className="custom-class" />
      );

      expect(container.firstChild).toHaveClass('custom-class');
    });
  });

  describe('password visibility toggle', () => {
    it('renders as password input by default', () => {
      render(<PasswordField {...defaultProps} />);

      const input = screen.getByLabelText('Password');
      expect(input).toHaveAttribute('type', 'password');
    });

    it('toggles to text input when show password clicked', () => {
      render(<PasswordField {...defaultProps} />);

      const toggleButton = screen.getByLabelText('Show password');
      fireEvent.click(toggleButton);

      const input = screen.getByLabelText('Password');
      expect(input).toHaveAttribute('type', 'text');
    });

    it('toggles back to password input', () => {
      render(<PasswordField {...defaultProps} />);

      const showButton = screen.getByLabelText('Show password');
      fireEvent.click(showButton);

      const hideButton = screen.getByLabelText('Hide password');
      fireEvent.click(hideButton);

      const input = screen.getByLabelText('Password');
      expect(input).toHaveAttribute('type', 'password');
    });

    it('has correct aria-label based on visibility state', () => {
      render(<PasswordField {...defaultProps} />);

      expect(screen.getByLabelText('Show password')).toBeInTheDocument();

      fireEvent.click(screen.getByLabelText('Show password'));

      expect(screen.getByLabelText('Hide password')).toBeInTheDocument();
    });
  });

  describe('disabled state', () => {
    it('disables input when disabled prop is true', () => {
      render(<PasswordField {...defaultProps} disabled />);

      expect(screen.getByLabelText('Password')).toBeDisabled();
    });

    it('disables toggle button when disabled', () => {
      render(<PasswordField {...defaultProps} disabled />);

      expect(screen.getByLabelText('Show password')).toBeDisabled();
    });

    it('applies disabled styling', () => {
      render(<PasswordField {...defaultProps} disabled />);

      const input = screen.getByLabelText('Password');
      expect(input).toHaveClass('opacity-60', 'cursor-not-allowed');
    });
  });

  describe('error handling', () => {
    it('displays error message when error and touched', () => {
      render(
        <PasswordField
          {...defaultProps}
          error="Password is required"
          touched
        />
      );

      expect(screen.getByText('Password is required')).toBeInTheDocument();
    });

    it('does not display error when not touched', () => {
      render(
        <PasswordField
          {...defaultProps}
          error="Password is required"
          touched={false}
        />
      );

      expect(screen.queryByText('Password is required')).not.toBeInTheDocument();
    });

    it('shows error with alert role', () => {
      render(
        <PasswordField
          {...defaultProps}
          error="Error"
          touched
        />
      );

      expect(screen.getByRole('alert')).toBeInTheDocument();
    });

    it('applies error styling to input', () => {
      render(
        <PasswordField
          {...defaultProps}
          error="Error"
          touched
        />
      );

      const input = screen.getByLabelText('Password');
      expect(input).toHaveClass('border-theme-error');
    });

    it('has aria-invalid when error present', () => {
      render(
        <PasswordField
          {...defaultProps}
          error="Error"
          touched
        />
      );

      const input = screen.getByLabelText('Password');
      expect(input).toHaveAttribute('aria-invalid', 'true');
    });
  });

  describe('password strength indicator', () => {
    it('does not show strength indicator by default', () => {
      render(<PasswordField {...defaultProps} value="Test123!" />);

      expect(screen.queryByText(/weak|fair|good|strong/i)).not.toBeInTheDocument();
    });

    it('shows strength indicator when enabled', () => {
      render(
        <PasswordField
          {...defaultProps}
          value="Test123!"
          showStrengthIndicator
        />
      );

      // Should show some strength label
      expect(screen.getByText(/weak|fair|good|strong/i)).toBeInTheDocument();
    });

    it('does not show strength indicator with empty value', () => {
      render(
        <PasswordField
          {...defaultProps}
          value=""
          showStrengthIndicator
        />
      );

      expect(screen.queryByText(/weak|fair|good|strong/i)).not.toBeInTheDocument();
    });

    it('shows "Very Weak" for short passwords', () => {
      render(
        <PasswordField
          {...defaultProps}
          value="abc"
          showStrengthIndicator
        />
      );

      expect(screen.getByText(/very weak|weak/i)).toBeInTheDocument();
    });

    it('shows stronger rating for complex passwords', () => {
      render(
        <PasswordField
          {...defaultProps}
          value="MyStr0ng!P@ssword123"
          showStrengthIndicator
        />
      );

      // Complex password should be strong or very strong
      expect(screen.getByText(/strong|very strong/i)).toBeInTheDocument();
    });

    it('calculates strength based on minLength', () => {
      // Using a short simple password that won't meet minLength
      render(
        <PasswordField
          {...defaultProps}
          value="short"
          showStrengthIndicator
          minLength={12}
        />
      );

      // Short password without special chars should be weak
      const strengthText = screen.getByText(/weak|fair/i);
      expect(strengthText).toBeInTheDocument();
    });
  });

  describe('autocomplete', () => {
    it('uses default autocomplete value', () => {
      render(<PasswordField {...defaultProps} />);

      expect(screen.getByLabelText('Password')).toHaveAttribute(
        'autocomplete',
        'current-password'
      );
    });

    it('uses custom autocomplete value', () => {
      render(
        <PasswordField
          {...defaultProps}
          autoComplete="new-password"
        />
      );

      expect(screen.getByLabelText('Password')).toHaveAttribute(
        'autocomplete',
        'new-password'
      );
    });
  });

  describe('events', () => {
    it('calls onChange when input changes', () => {
      const onChange = jest.fn();
      render(<PasswordField {...defaultProps} onChange={onChange} />);

      const input = screen.getByLabelText('Password');
      fireEvent.change(input, { target: { value: 'newpassword' } });

      expect(onChange).toHaveBeenCalled();
    });

    it('calls onBlur when input loses focus', () => {
      const onBlur = jest.fn();
      render(<PasswordField {...defaultProps} onBlur={onBlur} />);

      const input = screen.getByLabelText('Password');
      fireEvent.blur(input);

      expect(onBlur).toHaveBeenCalled();
    });
  });

  describe('accessibility', () => {
    it('associates label with input via htmlFor', () => {
      render(<PasswordField {...defaultProps} />);

      const label = screen.getByText('Password');
      expect(label).toHaveAttribute('for', 'password');
    });

    it('has accessible error message', () => {
      render(
        <PasswordField
          {...defaultProps}
          error="Error message"
          touched
        />
      );

      const error = screen.getByRole('alert');
      expect(error).toHaveAttribute('id', 'password-error');
    });

    it('references error in aria-describedby when error present', () => {
      render(
        <PasswordField
          {...defaultProps}
          error="Error"
          touched
        />
      );

      const input = screen.getByLabelText('Password');
      expect(input).toHaveAttribute('aria-describedby', 'password-error');
    });

    it('toggle button does not receive focus via tabIndex', () => {
      render(<PasswordField {...defaultProps} />);

      const toggleButton = screen.getByLabelText('Show password');
      expect(toggleButton).toHaveAttribute('tabIndex', '-1');
    });
  });

  describe('value handling', () => {
    it('displays the provided value', () => {
      render(<PasswordField {...defaultProps} value="testpassword" />);

      const input = screen.getByLabelText('Password');
      expect(input).toHaveValue('testpassword');
    });

    it('updates displayed value when prop changes', () => {
      const { rerender } = render(
        <PasswordField {...defaultProps} value="initial" />
      );

      expect(screen.getByLabelText('Password')).toHaveValue('initial');

      rerender(<PasswordField {...defaultProps} value="updated" />);

      expect(screen.getByLabelText('Password')).toHaveValue('updated');
    });
  });
});
