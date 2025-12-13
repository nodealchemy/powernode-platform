import { render, screen } from '@testing-library/react';
import { TextAreaField } from './TextAreaField';
import { UseFormReturn } from '@/shared/hooks/useForm';

// Mock useForm hook return type
const createMockForm = (overrides: Partial<{
  values: Record<string, any>;
  errors: Record<string, string>;
  touched: Record<string, boolean>;
  isSubmitting: boolean;
}> = {}): UseFormReturn<any> => {
  const values = overrides.values || { testTextarea: '' };
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

describe('TextAreaField', () => {
  describe('rendering', () => {
    it('renders label', () => {
      const form = createMockForm();
      render(<TextAreaField label="Description" name="testTextarea" form={form} />);

      expect(screen.getByText('Description')).toBeInTheDocument();
    });

    it('renders textarea with correct name and id', () => {
      const form = createMockForm();
      render(<TextAreaField label="Description" name="testTextarea" form={form} />);

      const textarea = screen.getByRole('textbox');
      expect(textarea).toHaveAttribute('name', 'testTextarea');
      expect(textarea).toHaveAttribute('id', 'testTextarea');
    });

    it('renders placeholder', () => {
      const form = createMockForm();
      render(
        <TextAreaField
          label="Description"
          name="testTextarea"
          form={form}
          placeholder="Enter description..."
        />
      );

      expect(screen.getByPlaceholderText('Enter description...')).toBeInTheDocument();
    });

    it('renders required indicator when required', () => {
      const form = createMockForm();
      render(
        <TextAreaField
          label="Description"
          name="testTextarea"
          form={form}
          required
        />
      );

      expect(screen.getByText('*')).toBeInTheDocument();
    });

    it('renders help text', () => {
      const form = createMockForm();
      render(
        <TextAreaField
          label="Description"
          name="testTextarea"
          form={form}
          helpText="Maximum 500 characters"
        />
      );

      expect(screen.getByText('Maximum 500 characters')).toBeInTheDocument();
    });

    it('applies custom className', () => {
      const form = createMockForm();
      const { container } = render(
        <TextAreaField
          label="Description"
          name="testTextarea"
          form={form}
          className="custom-class"
        />
      );

      expect(container.firstChild).toHaveClass('custom-class');
    });
  });

  describe('rows configuration', () => {
    it('uses default 4 rows', () => {
      const form = createMockForm();
      render(<TextAreaField label="Description" name="testTextarea" form={form} />);

      expect(screen.getByRole('textbox')).toHaveAttribute('rows', '4');
    });

    it('uses custom rows', () => {
      const form = createMockForm();
      render(
        <TextAreaField
          label="Description"
          name="testTextarea"
          form={form}
          rows={8}
        />
      );

      expect(screen.getByRole('textbox')).toHaveAttribute('rows', '8');
    });
  });

  describe('character count', () => {
    it('shows character count when showCharacterCount is true', () => {
      const form = createMockForm({ values: { testTextarea: 'Hello' } });
      render(
        <TextAreaField
          label="Description"
          name="testTextarea"
          form={form}
          showCharacterCount
        />
      );

      expect(screen.getByText(/5 characters/)).toBeInTheDocument();
    });

    it('shows character count with maxLength', () => {
      const form = createMockForm({ values: { testTextarea: 'Hello' } });
      render(
        <TextAreaField
          label="Description"
          name="testTextarea"
          form={form}
          maxLength={100}
        />
      );

      expect(screen.getByText('5/100 characters')).toBeInTheDocument();
    });

    it('shows singular character when count is 1', () => {
      const form = createMockForm({ values: { testTextarea: 'H' } });
      render(
        <TextAreaField
          label="Description"
          name="testTextarea"
          form={form}
          showCharacterCount
        />
      );

      expect(screen.getByText('1 character')).toBeInTheDocument();
    });

    it('sets maxLength attribute on textarea', () => {
      const form = createMockForm();
      render(
        <TextAreaField
          label="Description"
          name="testTextarea"
          form={form}
          maxLength={200}
        />
      );

      expect(screen.getByRole('textbox')).toHaveAttribute('maxLength', '200');
    });
  });

  describe('resize configuration', () => {
    it('uses vertical resize by default', () => {
      const form = createMockForm();
      render(<TextAreaField label="Description" name="testTextarea" form={form} />);

      expect(screen.getByRole('textbox')).toHaveClass('resize-y');
    });

    it('applies resize-none class', () => {
      const form = createMockForm();
      render(
        <TextAreaField
          label="Description"
          name="testTextarea"
          form={form}
          resize="none"
        />
      );

      expect(screen.getByRole('textbox')).toHaveClass('resize-none');
    });

    it('applies resize class for both', () => {
      const form = createMockForm();
      render(
        <TextAreaField
          label="Description"
          name="testTextarea"
          form={form}
          resize="both"
        />
      );

      expect(screen.getByRole('textbox')).toHaveClass('resize');
    });

    it('applies resize-x class for horizontal', () => {
      const form = createMockForm();
      render(
        <TextAreaField
          label="Description"
          name="testTextarea"
          form={form}
          resize="horizontal"
        />
      );

      expect(screen.getByRole('textbox')).toHaveClass('resize-x');
    });
  });

  describe('disabled state', () => {
    it('disables textarea when disabled prop is true', () => {
      const form = createMockForm();
      render(
        <TextAreaField
          label="Description"
          name="testTextarea"
          form={form}
          disabled
        />
      );

      expect(screen.getByRole('textbox')).toBeDisabled();
    });

    it('disables textarea when form is submitting', () => {
      const form = createMockForm({ isSubmitting: true });
      render(<TextAreaField label="Description" name="testTextarea" form={form} />);

      expect(screen.getByRole('textbox')).toBeDisabled();
    });

    it('applies disabled styling', () => {
      const form = createMockForm();
      render(
        <TextAreaField
          label="Description"
          name="testTextarea"
          form={form}
          disabled
        />
      );

      expect(screen.getByRole('textbox')).toHaveClass('opacity-60', 'cursor-not-allowed');
    });
  });

  describe('error handling', () => {
    it('displays error message when field has error', () => {
      const form = createMockForm({
        errors: { testTextarea: 'Description is required' },
      });

      render(<TextAreaField label="Description" name="testTextarea" form={form} />);

      expect(screen.getByText('Description is required')).toBeInTheDocument();
    });

    it('shows error with alert role', () => {
      const form = createMockForm({
        errors: { testTextarea: 'Error' },
      });

      render(<TextAreaField label="Description" name="testTextarea" form={form} />);

      expect(screen.getByRole('alert')).toBeInTheDocument();
    });

    it('applies error styling to textarea', () => {
      const form = createMockForm({
        errors: { testTextarea: 'Error' },
      });

      render(<TextAreaField label="Description" name="testTextarea" form={form} />);

      expect(screen.getByRole('textbox')).toHaveClass('border-theme-error');
    });

    it('does not show help text when error is present', () => {
      const form = createMockForm({
        errors: { testTextarea: 'Error' },
      });

      render(
        <TextAreaField
          label="Description"
          name="testTextarea"
          form={form}
          helpText="Help text"
        />
      );

      expect(screen.queryByText('Help text')).not.toBeInTheDocument();
    });
  });

  describe('accessibility', () => {
    it('associates label with textarea via htmlFor', () => {
      const form = createMockForm();
      render(<TextAreaField label="Description" name="testTextarea" form={form} />);

      const label = screen.getByText('Description');
      expect(label).toHaveAttribute('for', 'testTextarea');
    });

    it('has accessible error message', () => {
      const form = createMockForm({
        errors: { testTextarea: 'Error message' },
      });

      render(<TextAreaField label="Description" name="testTextarea" form={form} />);

      const error = screen.getByRole('alert');
      expect(error).toHaveAttribute('id', 'testTextarea-error');
    });
  });

  describe('styling', () => {
    it('has proper textarea styling', () => {
      const form = createMockForm();
      render(<TextAreaField label="Description" name="testTextarea" form={form} />);

      const textarea = screen.getByRole('textbox');
      expect(textarea).toHaveClass('w-full', 'px-4', 'py-3', 'border', 'rounded-lg');
    });
  });
});
