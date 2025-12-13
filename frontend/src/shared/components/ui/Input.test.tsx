import { render, screen, fireEvent } from '@testing-library/react';
import { Input } from './Input';

describe('Input', () => {
  describe('rendering', () => {
    it('renders input element', () => {
      render(<Input />);
      expect(screen.getByRole('textbox')).toBeInTheDocument();
    });

    it('renders with placeholder', () => {
      render(<Input placeholder="Enter text" />);
      expect(screen.getByPlaceholderText('Enter text')).toBeInTheDocument();
    });

    it('renders with value', () => {
      render(<Input value="test value" onChange={() => {}} />);
      expect(screen.getByDisplayValue('test value')).toBeInTheDocument();
    });
  });

  describe('label', () => {
    it('renders label when provided', () => {
      render(<Input label="Email" />);
      expect(screen.getByText('Email')).toBeInTheDocument();
    });

    it('associates label with input using htmlFor', () => {
      render(<Input label="Email" id="email-input" />);
      const label = screen.getByText('Email');
      expect(label).toHaveAttribute('for', 'email-input');
    });

    it('generates unique id when id is not provided', () => {
      render(<Input label="Email" />);
      const input = screen.getByRole('textbox');
      expect(input).toHaveAttribute('id');
    });
  });

  describe('error', () => {
    it('renders error message when provided', () => {
      render(<Input error="This field is required" />);
      expect(screen.getByText('This field is required')).toBeInTheDocument();
    });

    it('applies error styling when error is present', () => {
      render(<Input error="Error" />);
      expect(screen.getByRole('textbox')).toHaveClass('border-theme-error');
    });

    it('sets aria-describedby on input when error is present', () => {
      render(<Input error="Error" id="test-input" />);
      const input = screen.getByRole('textbox');
      expect(input).toHaveAttribute('aria-describedby', 'test-input-error');
    });

    it('applies alert role to error message', () => {
      render(<Input error="Error" />);
      expect(screen.getByRole('alert')).toBeInTheDocument();
    });
  });

  describe('fullWidth', () => {
    it('applies full width class by default', () => {
      render(<Input />);
      expect(screen.getByRole('textbox')).toHaveClass('w-full');
    });

    it('removes full width class when fullWidth is false', () => {
      render(<Input fullWidth={false} />);
      expect(screen.getByRole('textbox')).not.toHaveClass('w-full');
    });

    it('applies full width to container when fullWidth is true', () => {
      const { container } = render(<Input fullWidth />);
      expect(container.firstChild).toHaveClass('w-full');
    });
  });

  describe('disabled', () => {
    it('disables input when disabled prop is true', () => {
      render(<Input disabled />);
      expect(screen.getByRole('textbox')).toBeDisabled();
    });

    it('applies disabled styling', () => {
      render(<Input disabled />);
      expect(screen.getByRole('textbox')).toHaveClass('disabled:bg-theme-background');
    });
  });

  describe('interactions', () => {
    it('calls onChange handler when value changes', () => {
      const handleChange = jest.fn();
      render(<Input onChange={handleChange} />);
      fireEvent.change(screen.getByRole('textbox'), { target: { value: 'new value' } });
      expect(handleChange).toHaveBeenCalled();
    });

    it('calls onBlur handler when input loses focus', () => {
      const handleBlur = jest.fn();
      render(<Input onBlur={handleBlur} />);
      const input = screen.getByRole('textbox');
      fireEvent.focus(input);
      fireEvent.blur(input);
      expect(handleBlur).toHaveBeenCalled();
    });

    it('calls onFocus handler when input gains focus', () => {
      const handleFocus = jest.fn();
      render(<Input onFocus={handleFocus} />);
      fireEvent.focus(screen.getByRole('textbox'));
      expect(handleFocus).toHaveBeenCalled();
    });
  });

  describe('input types', () => {
    it('renders as text input by default', () => {
      render(<Input />);
      // HTML inputs default to type="text" even without explicit attribute
      expect(screen.getByRole('textbox')).toBeInTheDocument();
    });

    it('renders as email input', () => {
      render(<Input type="email" />);
      expect(screen.getByRole('textbox')).toHaveAttribute('type', 'email');
    });

    it('renders as password input', () => {
      render(<Input type="password" />);
      // Password inputs don't have textbox role
      const input = document.querySelector('input[type="password"]');
      expect(input).toBeInTheDocument();
    });

    it('renders as number input', () => {
      render(<Input type="number" />);
      expect(screen.getByRole('spinbutton')).toBeInTheDocument();
    });
  });

  describe('custom className', () => {
    it('merges custom className with default classes', () => {
      render(<Input className="custom-input" />);
      const input = screen.getByRole('textbox');
      expect(input).toHaveClass('custom-input');
      expect(input).toHaveClass('px-3');
    });
  });

  describe('HTML attributes', () => {
    it('passes through HTML input attributes', () => {
      render(
        <Input
          name="email"
          required
          maxLength={100}
          autoComplete="email"
          data-testid="email-input"
        />
      );
      const input = screen.getByRole('textbox');
      expect(input).toHaveAttribute('name', 'email');
      expect(input).toHaveAttribute('required');
      expect(input).toHaveAttribute('maxLength', '100');
      expect(input).toHaveAttribute('autoComplete', 'email');
      expect(input).toHaveAttribute('data-testid', 'email-input');
    });
  });
});
