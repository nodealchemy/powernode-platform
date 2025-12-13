import { render, screen } from '@testing-library/react';
import { CheckboxField } from './CheckboxField';
import { UseFormReturn } from '@/shared/hooks/useForm';

// Mock useForm hook return type
const createMockForm = (overrides: Partial<{
  values: Record<string, any>;
  errors: Record<string, string>;
  touched: Record<string, boolean>;
  isSubmitting: boolean;
}> = {}): UseFormReturn<any> => {
  const values = overrides.values || { testCheckbox: false };
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
      value: values[String(field)] || false,
      onChange: jest.fn(),
      onBlur: jest.fn(),
      error: errors[String(field)],
      'aria-invalid': !!errors[String(field)],
      'aria-describedby': errors[String(field)] ? `${String(field)}-error` : undefined,
    }),
  };
};

describe('CheckboxField', () => {
  describe('default variant', () => {
    it('renders label', () => {
      const form = createMockForm();
      render(<CheckboxField label="Accept terms" name="testCheckbox" form={form} />);

      expect(screen.getByText('Accept terms')).toBeInTheDocument();
    });

    it('renders checkbox with correct name and id', () => {
      const form = createMockForm();
      render(<CheckboxField label="Test" name="testCheckbox" form={form} />);

      const checkbox = screen.getByRole('checkbox');
      expect(checkbox).toHaveAttribute('name', 'testCheckbox');
      expect(checkbox).toHaveAttribute('id', 'testCheckbox');
    });

    it('renders required indicator when required', () => {
      const form = createMockForm();
      render(<CheckboxField label="Test" name="testCheckbox" form={form} required />);

      expect(screen.getByText('*')).toBeInTheDocument();
    });

    it('renders help text', () => {
      const form = createMockForm();
      render(
        <CheckboxField
          label="Test"
          name="testCheckbox"
          form={form}
          helpText="This is helpful information"
        />
      );

      expect(screen.getByText('This is helpful information')).toBeInTheDocument();
    });

    it('applies custom className', () => {
      const form = createMockForm();
      const { container } = render(
        <CheckboxField
          label="Test"
          name="testCheckbox"
          form={form}
          className="custom-class"
        />
      );

      expect(container.firstChild).toHaveClass('custom-class');
    });

    it('associates label with checkbox', () => {
      const form = createMockForm();
      render(<CheckboxField label="Click me" name="testCheckbox" form={form} />);

      const label = screen.getByText('Click me');
      expect(label).toHaveAttribute('for', 'testCheckbox');
    });
  });

  describe('card variant', () => {
    it('renders with card styling', () => {
      const form = createMockForm();
      const { container } = render(
        <CheckboxField
          label="Card Option"
          name="testCheckbox"
          form={form}
          variant="card"
        />
      );

      const label = container.querySelector('label');
      expect(label).toHaveClass('p-4', 'border', 'rounded-lg');
    });

    it('renders help text in card variant', () => {
      const form = createMockForm();
      render(
        <CheckboxField
          label="Card Option"
          name="testCheckbox"
          form={form}
          variant="card"
          helpText="Description for this option"
        />
      );

      expect(screen.getByText('Description for this option')).toBeInTheDocument();
    });

    it('applies selected styling when checked', () => {
      const form = createMockForm({ values: { testCheckbox: true } });
      const { container } = render(
        <CheckboxField
          label="Card Option"
          name="testCheckbox"
          form={form}
          variant="card"
        />
      );

      const label = container.querySelector('label');
      expect(label).toHaveClass('border-theme-focus', 'bg-theme-interactive-secondary');
    });
  });

  describe('disabled state', () => {
    it('disables checkbox when disabled prop is true', () => {
      const form = createMockForm();
      render(
        <CheckboxField
          label="Test"
          name="testCheckbox"
          form={form}
          disabled
        />
      );

      expect(screen.getByRole('checkbox')).toBeDisabled();
    });

    it('disables checkbox when form is submitting', () => {
      const form = createMockForm({ isSubmitting: true });
      render(<CheckboxField label="Test" name="testCheckbox" form={form} />);

      expect(screen.getByRole('checkbox')).toBeDisabled();
    });

    it('applies disabled styling to label', () => {
      const form = createMockForm();
      render(
        <CheckboxField
          label="Test"
          name="testCheckbox"
          form={form}
          disabled
        />
      );

      const label = screen.getByText('Test');
      expect(label).toHaveClass('opacity-60', 'cursor-not-allowed');
    });
  });

  describe('error handling', () => {
    it('displays error message when field has error', () => {
      const form = createMockForm({
        errors: { testCheckbox: 'You must accept the terms' },
      });

      render(<CheckboxField label="Test" name="testCheckbox" form={form} />);

      expect(screen.getByText('You must accept the terms')).toBeInTheDocument();
    });

    it('shows error with alert role', () => {
      const form = createMockForm({
        errors: { testCheckbox: 'Error' },
      });

      render(<CheckboxField label="Test" name="testCheckbox" form={form} />);

      expect(screen.getByRole('alert')).toBeInTheDocument();
    });

    it('does not show help text when error is present', () => {
      const form = createMockForm({
        errors: { testCheckbox: 'Error' },
      });

      render(
        <CheckboxField
          label="Test"
          name="testCheckbox"
          form={form}
          helpText="Help text"
        />
      );

      expect(screen.queryByText('Help text')).not.toBeInTheDocument();
    });

    it('applies error styling in card variant', () => {
      const form = createMockForm({
        errors: { testCheckbox: 'Error' },
      });

      const { container } = render(
        <CheckboxField
          label="Test"
          name="testCheckbox"
          form={form}
          variant="card"
        />
      );

      const label = container.querySelector('label');
      expect(label).toHaveClass('border-theme-error');
    });
  });

  describe('ReactNode label', () => {
    it('renders ReactNode as label', () => {
      const form = createMockForm();
      render(
        <CheckboxField
          label={<span data-testid="custom-label">Custom Label</span>}
          name="testCheckbox"
          form={form}
        />
      );

      expect(screen.getByTestId('custom-label')).toBeInTheDocument();
    });
  });

  describe('accessibility', () => {
    it('has accessible error message with id', () => {
      const form = createMockForm({
        errors: { testCheckbox: 'Error message' },
      });

      render(<CheckboxField label="Test" name="testCheckbox" form={form} />);

      const error = screen.getByRole('alert');
      expect(error).toHaveAttribute('id', 'testCheckbox-error');
    });
  });
});
