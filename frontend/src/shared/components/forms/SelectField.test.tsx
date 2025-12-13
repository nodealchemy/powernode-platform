import { render, screen } from '@testing-library/react';
import { SelectField } from './SelectField';
import { UseFormReturn } from '@/shared/hooks/useForm';

// Mock useForm hook return type
const createMockForm = (overrides: Partial<{
  values: Record<string, any>;
  errors: Record<string, string>;
  touched: Record<string, boolean>;
  isSubmitting: boolean;
}> = {}): UseFormReturn<any> => {
  const values = overrides.values || { testSelect: '' };
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

const mockOptions = [
  { value: 'option1', label: 'Option 1' },
  { value: 'option2', label: 'Option 2' },
  { value: 'option3', label: 'Option 3', disabled: true },
];

describe('SelectField', () => {
  describe('rendering', () => {
    it('renders label', () => {
      const form = createMockForm();
      render(
        <SelectField
          label="Select Label"
          name="testSelect"
          form={form}
          options={mockOptions}
        />
      );

      expect(screen.getByText('Select Label')).toBeInTheDocument();
    });

    it('renders select with correct name and id', () => {
      const form = createMockForm();
      render(
        <SelectField
          label="Select Label"
          name="testSelect"
          form={form}
          options={mockOptions}
        />
      );

      const select = screen.getByRole('combobox');
      expect(select).toHaveAttribute('name', 'testSelect');
      expect(select).toHaveAttribute('id', 'testSelect');
    });

    it('renders all options', () => {
      const form = createMockForm();
      render(
        <SelectField
          label="Select Label"
          name="testSelect"
          form={form}
          options={mockOptions}
        />
      );

      expect(screen.getByText('Option 1')).toBeInTheDocument();
      expect(screen.getByText('Option 2')).toBeInTheDocument();
      expect(screen.getByText('Option 3')).toBeInTheDocument();
    });

    it('renders placeholder as first option', () => {
      const form = createMockForm();
      render(
        <SelectField
          label="Select Label"
          name="testSelect"
          form={form}
          options={mockOptions}
          placeholder="Choose one..."
        />
      );

      expect(screen.getByText('Choose one...')).toBeInTheDocument();
    });

    it('uses default placeholder when not provided', () => {
      const form = createMockForm();
      render(
        <SelectField
          label="Select Label"
          name="testSelect"
          form={form}
          options={mockOptions}
        />
      );

      expect(screen.getByText('Select an option...')).toBeInTheDocument();
    });

    it('renders required indicator when required', () => {
      const form = createMockForm();
      render(
        <SelectField
          label="Select Label"
          name="testSelect"
          form={form}
          options={mockOptions}
          required
        />
      );

      expect(screen.getByText('*')).toBeInTheDocument();
    });

    it('renders help text', () => {
      const form = createMockForm();
      render(
        <SelectField
          label="Select Label"
          name="testSelect"
          form={form}
          options={mockOptions}
          helpText="Choose wisely"
        />
      );

      expect(screen.getByText('Choose wisely')).toBeInTheDocument();
    });

    it('applies custom className', () => {
      const form = createMockForm();
      const { container } = render(
        <SelectField
          label="Select Label"
          name="testSelect"
          form={form}
          options={mockOptions}
          className="custom-class"
        />
      );

      expect(container.firstChild).toHaveClass('custom-class');
    });
  });

  describe('options', () => {
    it('renders disabled options', () => {
      const form = createMockForm();
      render(
        <SelectField
          label="Select Label"
          name="testSelect"
          form={form}
          options={mockOptions}
        />
      );

      const disabledOption = screen.getByText('Option 3');
      expect(disabledOption).toBeDisabled();
    });

    it('does not render empty option when allowEmpty is false', () => {
      const form = createMockForm();
      render(
        <SelectField
          label="Select Label"
          name="testSelect"
          form={form}
          options={mockOptions}
          allowEmpty={false}
        />
      );

      expect(screen.queryByText('Select an option...')).not.toBeInTheDocument();
    });

    it('disables placeholder when required', () => {
      const form = createMockForm();
      render(
        <SelectField
          label="Select Label"
          name="testSelect"
          form={form}
          options={mockOptions}
          required
        />
      );

      const placeholder = screen.getByText('Select an option...');
      expect(placeholder).toBeDisabled();
    });
  });

  describe('disabled state', () => {
    it('disables select when disabled prop is true', () => {
      const form = createMockForm();
      render(
        <SelectField
          label="Select Label"
          name="testSelect"
          form={form}
          options={mockOptions}
          disabled
        />
      );

      expect(screen.getByRole('combobox')).toBeDisabled();
    });

    it('disables select when form is submitting', () => {
      const form = createMockForm({ isSubmitting: true });
      render(
        <SelectField
          label="Select Label"
          name="testSelect"
          form={form}
          options={mockOptions}
        />
      );

      expect(screen.getByRole('combobox')).toBeDisabled();
    });

    it('applies disabled styling', () => {
      const form = createMockForm();
      render(
        <SelectField
          label="Select Label"
          name="testSelect"
          form={form}
          options={mockOptions}
          disabled
        />
      );

      const select = screen.getByRole('combobox');
      expect(select).toHaveClass('opacity-60', 'cursor-not-allowed');
    });
  });

  describe('error handling', () => {
    it('displays error message when field has error', () => {
      const form = createMockForm({
        errors: { testSelect: 'Please select an option' },
      });

      render(
        <SelectField
          label="Select Label"
          name="testSelect"
          form={form}
          options={mockOptions}
        />
      );

      expect(screen.getByText('Please select an option')).toBeInTheDocument();
    });

    it('shows error with alert role', () => {
      const form = createMockForm({
        errors: { testSelect: 'Error' },
      });

      render(
        <SelectField
          label="Select Label"
          name="testSelect"
          form={form}
          options={mockOptions}
        />
      );

      expect(screen.getByRole('alert')).toBeInTheDocument();
    });

    it('applies error styling to select', () => {
      const form = createMockForm({
        errors: { testSelect: 'Error' },
      });

      render(
        <SelectField
          label="Select Label"
          name="testSelect"
          form={form}
          options={mockOptions}
        />
      );

      const select = screen.getByRole('combobox');
      expect(select).toHaveClass('border-theme-error');
    });

    it('does not show help text when error is present', () => {
      const form = createMockForm({
        errors: { testSelect: 'Error' },
      });

      render(
        <SelectField
          label="Select Label"
          name="testSelect"
          form={form}
          options={mockOptions}
          helpText="Help text"
        />
      );

      expect(screen.queryByText('Help text')).not.toBeInTheDocument();
    });
  });

  describe('accessibility', () => {
    it('associates label with select via htmlFor', () => {
      const form = createMockForm();
      render(
        <SelectField
          label="Select Label"
          name="testSelect"
          form={form}
          options={mockOptions}
        />
      );

      const label = screen.getByText('Select Label');
      expect(label).toHaveAttribute('for', 'testSelect');
    });

    it('has accessible error message', () => {
      const form = createMockForm({
        errors: { testSelect: 'Error message' },
      });

      render(
        <SelectField
          label="Select Label"
          name="testSelect"
          form={form}
          options={mockOptions}
        />
      );

      const error = screen.getByRole('alert');
      expect(error).toHaveAttribute('id', 'testSelect-error');
    });
  });

  describe('styling', () => {
    it('has proper label styling', () => {
      const form = createMockForm();
      render(
        <SelectField
          label="Select Label"
          name="testSelect"
          form={form}
          options={mockOptions}
        />
      );

      const label = screen.getByText('Select Label');
      expect(label).toHaveClass('text-sm', 'font-semibold', 'text-theme-primary');
    });

    it('has proper select styling', () => {
      const form = createMockForm();
      render(
        <SelectField
          label="Select Label"
          name="testSelect"
          form={form}
          options={mockOptions}
        />
      );

      const select = screen.getByRole('combobox');
      expect(select).toHaveClass('w-full', 'px-4', 'py-3', 'border', 'rounded-lg');
    });
  });
});
