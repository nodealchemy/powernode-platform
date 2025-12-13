import { render, screen } from '@testing-library/react';
import { FormField } from './FormField';
import { UseFormReturn } from '@/shared/hooks/useForm';

// Mock useForm hook return type
const createMockForm = (overrides: Partial<{
  values: Record<string, any>;
  errors: Record<string, string>;
  touched: Record<string, boolean>;
  isSubmitting: boolean;
}> = {}): UseFormReturn<any> => {
  const values = overrides.values || { testField: '' };
  const errors = overrides.errors || {};
  const touched = overrides.touched || {};

  return {
    values,
    errors: errors as Record<keyof typeof values, string | undefined>,
    touched: touched as Record<keyof typeof values, boolean>,
    isSubmitting: overrides.isSubmitting ?? false,
    isValid: Object.keys(errors).length === 0,
    isDirty: false,
    handleChange: jest.fn(),
    handleBlur: jest.fn(),
    handleSubmit: jest.fn(),
    setValue: jest.fn(),
    setError: jest.fn(),
    clearError: jest.fn(),
    setTouched: jest.fn(),
    reset: jest.fn(),
    validateField: jest.fn(),
    validateForm: jest.fn(),
    getFieldProps: (field: string | number | symbol) => ({
      name: String(field),
      value: values[String(field)] || '',
      onChange: jest.fn(),
      onBlur: jest.fn(),
      error: errors[String(field)],
      'aria-invalid': !!errors[String(field)],
      'aria-describedby': errors[String(field)] ? `${String(field)}-error` : undefined,
    }),
  };
};

describe('FormField', () => {
  describe('rendering', () => {
    it('renders label', () => {
      const form = createMockForm();
      render(<FormField label="Test Label" name="testField" form={form} />);

      expect(screen.getByText('Test Label')).toBeInTheDocument();
    });

    it('renders input with correct name and id', () => {
      const form = createMockForm();
      render(<FormField label="Test Label" name="testField" form={form} />);

      const input = screen.getByRole('textbox');
      expect(input).toHaveAttribute('name', 'testField');
      expect(input).toHaveAttribute('id', 'testField');
    });

    it('renders placeholder', () => {
      const form = createMockForm();
      render(
        <FormField
          label="Test Label"
          name="testField"
          form={form}
          placeholder="Enter value"
        />
      );

      expect(screen.getByPlaceholderText('Enter value')).toBeInTheDocument();
    });

    it('renders required indicator when required', () => {
      const form = createMockForm();
      render(
        <FormField
          label="Test Label"
          name="testField"
          form={form}
          required
        />
      );

      expect(screen.getByText('*')).toBeInTheDocument();
    });

    it('does not render required indicator when not required', () => {
      const form = createMockForm();
      render(<FormField label="Test Label" name="testField" form={form} />);

      expect(screen.queryByText('*')).not.toBeInTheDocument();
    });

    it('renders help text', () => {
      const form = createMockForm();
      render(
        <FormField
          label="Test Label"
          name="testField"
          form={form}
          helpText="This is help text"
        />
      );

      expect(screen.getByText('This is help text')).toBeInTheDocument();
    });

    it('applies custom className', () => {
      const form = createMockForm();
      const { container } = render(
        <FormField
          label="Test Label"
          name="testField"
          form={form}
          className="custom-class"
        />
      );

      expect(container.firstChild).toHaveClass('custom-class');
    });
  });

  describe('input types', () => {
    it('renders text input by default', () => {
      const form = createMockForm();
      render(<FormField label="Test Label" name="testField" form={form} />);

      const input = screen.getByRole('textbox');
      expect(input).toHaveAttribute('type', 'text');
    });

    it('renders email input', () => {
      const form = createMockForm();
      render(
        <FormField
          label="Email"
          name="email"
          form={form}
          type="email"
        />
      );

      const input = screen.getByRole('textbox');
      expect(input).toHaveAttribute('type', 'email');
    });

    it('renders number input', () => {
      const form = createMockForm();
      render(
        <FormField
          label="Amount"
          name="amount"
          form={form}
          type="number"
        />
      );

      const input = screen.getByRole('spinbutton');
      expect(input).toHaveAttribute('type', 'number');
    });

    it('renders password input', () => {
      const form = createMockForm();
      render(
        <FormField
          label="Password"
          name="password"
          form={form}
          type="password"
        />
      );

      const input = document.getElementById('password');
      expect(input).toHaveAttribute('type', 'password');
    });

    it('renders tel input', () => {
      const form = createMockForm();
      render(
        <FormField
          label="Phone"
          name="phone"
          form={form}
          type="tel"
        />
      );

      const input = screen.getByRole('textbox');
      expect(input).toHaveAttribute('type', 'tel');
    });
  });

  describe('disabled state', () => {
    it('disables input when disabled prop is true', () => {
      const form = createMockForm();
      render(
        <FormField
          label="Test Label"
          name="testField"
          form={form}
          disabled
        />
      );

      expect(screen.getByRole('textbox')).toBeDisabled();
    });

    it('disables input when form is submitting', () => {
      const form = createMockForm({ isSubmitting: true });
      render(<FormField label="Test Label" name="testField" form={form} />);

      expect(screen.getByRole('textbox')).toBeDisabled();
    });

    it('applies disabled styling', () => {
      const form = createMockForm();
      render(
        <FormField
          label="Test Label"
          name="testField"
          form={form}
          disabled
        />
      );

      const input = screen.getByRole('textbox');
      expect(input).toHaveClass('opacity-60', 'cursor-not-allowed');
    });
  });

  describe('error handling', () => {
    it('displays error message when field has error', () => {
      const form = createMockForm({
        errors: { testField: 'This field is required' },
      });

      render(<FormField label="Test Label" name="testField" form={form} />);

      expect(screen.getByText('This field is required')).toBeInTheDocument();
    });

    it('shows error with alert role', () => {
      const form = createMockForm({
        errors: { testField: 'This field is required' },
      });

      render(<FormField label="Test Label" name="testField" form={form} />);

      expect(screen.getByRole('alert')).toBeInTheDocument();
    });

    it('applies error styling to input', () => {
      const form = createMockForm({
        errors: { testField: 'Error' },
      });

      render(<FormField label="Test Label" name="testField" form={form} />);

      const input = screen.getByRole('textbox');
      expect(input).toHaveClass('border-theme-error');
    });

    it('does not show help text when error is present', () => {
      const form = createMockForm({
        errors: { testField: 'Error' },
      });

      render(
        <FormField
          label="Test Label"
          name="testField"
          form={form}
          helpText="Help text"
        />
      );

      expect(screen.queryByText('Help text')).not.toBeInTheDocument();
    });
  });

  describe('autocomplete', () => {
    it('sets autocomplete attribute', () => {
      const form = createMockForm();
      render(
        <FormField
          label="Email"
          name="email"
          form={form}
          autoComplete="email"
        />
      );

      expect(screen.getByRole('textbox')).toHaveAttribute('autocomplete', 'email');
    });
  });

  describe('accessibility', () => {
    it('associates label with input via htmlFor', () => {
      const form = createMockForm();
      render(<FormField label="Test Label" name="testField" form={form} />);

      const label = screen.getByText('Test Label');
      expect(label).toHaveAttribute('for', 'testField');
    });

    it('has accessible error message', () => {
      const form = createMockForm({
        errors: { testField: 'Error message' },
      });

      render(<FormField label="Test Label" name="testField" form={form} />);

      const error = screen.getByRole('alert');
      expect(error).toHaveAttribute('id', 'testField-error');
    });
  });

  describe('styling', () => {
    it('has proper label styling', () => {
      const form = createMockForm();
      render(<FormField label="Test Label" name="testField" form={form} />);

      const label = screen.getByText('Test Label');
      expect(label).toHaveClass('text-sm', 'font-semibold', 'text-theme-primary');
    });

    it('has proper input styling', () => {
      const form = createMockForm();
      render(<FormField label="Test Label" name="testField" form={form} />);

      const input = screen.getByRole('textbox');
      expect(input).toHaveClass('w-full', 'px-4', 'py-3', 'border', 'rounded-lg');
    });
  });
});
