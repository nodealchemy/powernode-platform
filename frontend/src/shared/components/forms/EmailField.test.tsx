import { render, screen, fireEvent } from '@testing-library/react';
import { EmailField } from './EmailField';

describe('EmailField', () => {
  const defaultProps = {
    name: 'email',
    value: '',
    onChange: jest.fn(),
    onBlur: jest.fn(),
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('rendering', () => {
    it('renders with default label', () => {
      render(<EmailField {...defaultProps} />);

      expect(screen.getByText('Email Address')).toBeInTheDocument();
    });

    it('renders with custom label', () => {
      render(<EmailField {...defaultProps} label="Work Email" />);

      expect(screen.getByText('Work Email')).toBeInTheDocument();
    });

    it('renders without label when label is empty', () => {
      render(<EmailField {...defaultProps} label="" />);

      expect(screen.queryByText('Email Address')).not.toBeInTheDocument();
    });

    it('renders input with correct name and id', () => {
      render(<EmailField {...defaultProps} />);

      const input = screen.getByRole('textbox');
      expect(input).toHaveAttribute('name', 'email');
      expect(input).toHaveAttribute('id', 'email');
    });

    it('renders as email input type', () => {
      render(<EmailField {...defaultProps} />);

      const input = screen.getByRole('textbox');
      expect(input).toHaveAttribute('type', 'email');
    });

    it('renders placeholder', () => {
      render(<EmailField {...defaultProps} placeholder="your@email.com" />);

      expect(screen.getByPlaceholderText('your@email.com')).toBeInTheDocument();
    });

    it('uses default placeholder when not provided', () => {
      render(<EmailField {...defaultProps} />);

      expect(screen.getByPlaceholderText('Enter your email address')).toBeInTheDocument();
    });

    it('renders required indicator when required', () => {
      render(<EmailField {...defaultProps} required />);

      expect(screen.getByText('*')).toBeInTheDocument();
    });

    it('applies custom className', () => {
      const { container } = render(
        <EmailField {...defaultProps} className="custom-class" />
      );

      expect(container.firstChild).toHaveClass('custom-class');
    });

    it('renders envelope icon', () => {
      const { container } = render(<EmailField {...defaultProps} />);

      // Check for SVG icon (EnvelopeIcon)
      const icon = container.querySelector('svg');
      expect(icon).toBeInTheDocument();
    });
  });

  describe('disabled state', () => {
    it('disables input when disabled prop is true', () => {
      render(<EmailField {...defaultProps} disabled />);

      expect(screen.getByRole('textbox')).toBeDisabled();
    });

    it('applies disabled styling', () => {
      render(<EmailField {...defaultProps} disabled />);

      const input = screen.getByRole('textbox');
      expect(input).toHaveClass('opacity-60', 'cursor-not-allowed');
    });
  });

  describe('error handling', () => {
    it('displays error message when error and touched', () => {
      render(
        <EmailField
          {...defaultProps}
          error="Invalid email address"
          touched
        />
      );

      expect(screen.getByText('Invalid email address')).toBeInTheDocument();
    });

    it('does not display error when not touched', () => {
      render(
        <EmailField
          {...defaultProps}
          error="Invalid email address"
          touched={false}
        />
      );

      expect(screen.queryByText('Invalid email address')).not.toBeInTheDocument();
    });

    it('shows error with alert role', () => {
      render(
        <EmailField
          {...defaultProps}
          error="Error"
          touched
        />
      );

      expect(screen.getByRole('alert')).toBeInTheDocument();
    });

    it('applies error styling to input', () => {
      render(
        <EmailField
          {...defaultProps}
          error="Error"
          touched
        />
      );

      const input = screen.getByRole('textbox');
      expect(input).toHaveClass('border-theme-error');
    });

    it('has aria-invalid when error present', () => {
      render(
        <EmailField
          {...defaultProps}
          error="Error"
          touched
        />
      );

      const input = screen.getByRole('textbox');
      expect(input).toHaveAttribute('aria-invalid', 'true');
    });

    it('has aria-invalid false when no error', () => {
      render(<EmailField {...defaultProps} />);

      const input = screen.getByRole('textbox');
      expect(input).toHaveAttribute('aria-invalid', 'false');
    });
  });

  describe('autocomplete', () => {
    it('uses default email autocomplete', () => {
      render(<EmailField {...defaultProps} />);

      expect(screen.getByRole('textbox')).toHaveAttribute('autocomplete', 'email');
    });

    it('uses custom autocomplete value', () => {
      render(<EmailField {...defaultProps} autoComplete="username" />);

      expect(screen.getByRole('textbox')).toHaveAttribute('autocomplete', 'username');
    });
  });

  describe('events', () => {
    it('calls onChange when input changes', () => {
      const onChange = jest.fn();
      render(<EmailField {...defaultProps} onChange={onChange} />);

      const input = screen.getByRole('textbox');
      fireEvent.change(input, { target: { value: 'test@example.com' } });

      expect(onChange).toHaveBeenCalled();
    });

    it('calls onBlur when input loses focus', () => {
      const onBlur = jest.fn();
      render(<EmailField {...defaultProps} onBlur={onBlur} />);

      const input = screen.getByRole('textbox');
      fireEvent.blur(input);

      expect(onBlur).toHaveBeenCalled();
    });
  });

  describe('accessibility', () => {
    it('associates label with input via htmlFor', () => {
      render(<EmailField {...defaultProps} />);

      const label = screen.getByText('Email Address');
      expect(label).toHaveAttribute('for', 'email');
    });

    it('has accessible error message', () => {
      render(
        <EmailField
          {...defaultProps}
          error="Error message"
          touched
        />
      );

      const error = screen.getByRole('alert');
      expect(error).toHaveAttribute('id', 'email-error');
    });

    it('references error in aria-describedby when error present', () => {
      render(
        <EmailField
          {...defaultProps}
          error="Error"
          touched
        />
      );

      const input = screen.getByRole('textbox');
      expect(input).toHaveAttribute('aria-describedby', 'email-error');
    });

    it('does not have aria-describedby when no error', () => {
      render(<EmailField {...defaultProps} />);

      const input = screen.getByRole('textbox');
      expect(input).not.toHaveAttribute('aria-describedby');
    });
  });

  describe('value handling', () => {
    it('displays the provided value', () => {
      render(<EmailField {...defaultProps} value="test@example.com" />);

      const input = screen.getByRole('textbox');
      expect(input).toHaveValue('test@example.com');
    });

    it('updates displayed value when prop changes', () => {
      const { rerender } = render(
        <EmailField {...defaultProps} value="initial@example.com" />
      );

      expect(screen.getByRole('textbox')).toHaveValue('initial@example.com');

      rerender(<EmailField {...defaultProps} value="updated@example.com" />);

      expect(screen.getByRole('textbox')).toHaveValue('updated@example.com');
    });
  });

  describe('styling', () => {
    it('has proper input styling', () => {
      render(<EmailField {...defaultProps} />);

      const input = screen.getByRole('textbox');
      expect(input).toHaveClass('w-full', 'pl-10', 'border', 'rounded-lg');
    });
  });
});
