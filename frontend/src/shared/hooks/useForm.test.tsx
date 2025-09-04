import React from 'react';
import { screen, fireEvent, waitFor, act, render } from '@testing-library/react';
import { renderHook } from '@testing-library/react';
import { Provider } from 'react-redux';
import { configureStore } from '@reduxjs/toolkit';
import { renderWithProviders, mockAuthenticatedState } from '../utils/test-utils';
import { useForm, FormValidationRules, UseFormOptions } from './useForm';
import uiReducer from '@/shared/services/slices/uiSlice';

// Mock the notification hook
const mockShowNotification = jest.fn();
jest.mock('./useNotification', () => ({
  useNotification: () => ({
    showNotification: mockShowNotification
  })
}));

// Create a test store factory
const createMockStore = () => {
  return configureStore({
    reducer: {
      ui: uiReducer
    }
  });
};

interface TestFormData {
  email: string;
  password: string;
  name: string;
  age: number;
  acceptTerms: boolean;
}

describe('useForm', () => {
  const defaultInitialValues: TestFormData = {
    email: '',
    password: '',
    name: '',
    age: 0,
    acceptTerms: false
  };

  const defaultValidationRules: FormValidationRules = {
    email: {
      required: true,
      pattern: /^[^\s@]+@[^\s@]+\.[^\s@]+$/
    },
    password: {
      required: true,
      minLength: 8
    },
    name: {
      required: true,
      minLength: 2,
      maxLength: 50
    },
    age: {
      required: true,
      custom: (value: unknown) => {
        const numValue = Number(value);
        if (numValue < 18) return 'Must be at least 18 years old';
        if (numValue > 120) return 'Must be less than 120 years old';
        return null;
      }
    }
  };

  // Create wrapper component for hooks with Redux provider
  const createWrapper = () => {
    const store = createMockStore();
    const Wrapper: React.FC<{ children: React.ReactNode }> = ({ children }) => (
      <Provider store={store}>{children}</Provider>
    );
    return { Wrapper, store };
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('initialization', () => {
    it('initializes with correct default values', () => {
      const mockOnSubmit = jest.fn();
      const { Wrapper } = createWrapper();
      const { result } = renderHook(() =>
        useForm({
          initialValues: defaultInitialValues,
          onSubmit: mockOnSubmit
        }),
        { wrapper: Wrapper }
      );

      expect(result.current.values).toEqual(defaultInitialValues);
      expect(result.current.isSubmitting).toBe(false);
      expect(result.current.isValid).toBe(true); // No validation rules, so valid
      expect(result.current.isDirty).toBe(false);
      
      // All errors should be undefined
      Object.keys(defaultInitialValues).forEach(key => {
        expect(result.current.errors[key as keyof TestFormData]).toBeUndefined();
      });
      
      // All touched should be false
      Object.keys(defaultInitialValues).forEach(key => {
        expect(result.current.touched[key as keyof TestFormData]).toBe(false);
      });
    });

    it('initializes with validation rules', () => {
      const mockOnSubmit = jest.fn();
      const { Wrapper } = createWrapper();
      const { result } = renderHook(() =>
        useForm({
          initialValues: defaultInitialValues,
          validationRules: defaultValidationRules,
          onSubmit: mockOnSubmit
        }),
        { wrapper: Wrapper }
      );

      expect(result.current.isValid).toBe(true); // Form is valid until validation is triggered
    });
  });

  describe('field operations', () => {
    it('updates field values correctly', () => {
      const mockOnSubmit = jest.fn();
      const { Wrapper } = createWrapper();
      const { result } = renderHook(() =>
        useForm({
          initialValues: defaultInitialValues,
          onSubmit: mockOnSubmit
        }),
        { wrapper: Wrapper }
      );

      act(() => {
        result.current.setValue('email', 'test@example.com');
      });

      expect(result.current.values.email).toBe('test@example.com');
      expect(result.current.isDirty).toBe(true);
    });

    it('sets field errors correctly', () => {
      const mockOnSubmit = jest.fn();
      const { Wrapper } = createWrapper();
      const { result } = renderHook(() =>
        useForm({
          initialValues: defaultInitialValues,
          onSubmit: mockOnSubmit
        }),
        { wrapper: Wrapper }
      );

      act(() => {
        result.current.setError('email', 'Invalid email format');
      });

      expect(result.current.errors.email).toBe('Invalid email format');
      expect(result.current.isValid).toBe(false);
    });

    it('clears field errors correctly', () => {
      const mockOnSubmit = jest.fn();
      const { Wrapper } = createWrapper();
      const { result } = renderHook(() =>
        useForm({
          initialValues: defaultInitialValues,
          validationRules: defaultValidationRules,
          onSubmit: mockOnSubmit
        }),
        { wrapper: Wrapper }
      );

      // Set an error first
      act(() => {
        result.current.setError('email', 'Invalid email format');
      });

      expect(result.current.errors.email).toBe('Invalid email format');

      // Clear the error
      act(() => {
        result.current.clearError('email');
      });

      expect(result.current.errors.email).toBeUndefined();
    });

    it('sets touched state correctly', () => {
      const mockOnSubmit = jest.fn();
      const { Wrapper } = createWrapper();
      const { result } = renderHook(() =>
        useForm({
          initialValues: defaultInitialValues,
          onSubmit: mockOnSubmit
        }),
        { wrapper: Wrapper }
      );

      act(() => {
        result.current.setTouched('email', true);
      });

      expect(result.current.touched.email).toBe(true);

      act(() => {
        result.current.setTouched('email', false);
      });

      expect(result.current.touched.email).toBe(false);
    });
  });

  describe('validation', () => {
    it('validates required fields correctly', () => {
      const mockOnSubmit = jest.fn();
      const { Wrapper } = createWrapper();
      const { result } = renderHook(() =>
        useForm({
          initialValues: defaultInitialValues,
          validationRules: defaultValidationRules,
          onSubmit: mockOnSubmit
        }),
        { wrapper: Wrapper }
      );

      const emailError = result.current.validateField('email');
      expect(emailError).toBe('email is required');

      // Set a value and re-validate
      act(() => {
        result.current.setValue('email', 'test@example.com');
      });

      const emailErrorAfter = result.current.validateField('email');
      expect(emailErrorAfter).toBe(null);
    });

    it('validates string length correctly', () => {
      const mockOnSubmit = jest.fn();
      const { Wrapper } = createWrapper();
      const { result } = renderHook(() =>
        useForm({
          initialValues: { ...defaultInitialValues, name: 'x' },
          validationRules: defaultValidationRules,
          onSubmit: mockOnSubmit
        }),
        { wrapper: Wrapper }
      );

      const nameError = result.current.validateField('name');
      expect(nameError).toBe('name must be at least 2 characters');

      // Test max length
      const longName = 'a'.repeat(51);
      act(() => {
        result.current.setValue('name', longName);
      });

      const longNameError = result.current.validateField('name');
      expect(longNameError).toBe('name must be no more than 50 characters');
    });

    it('validates pattern correctly', () => {
      const mockOnSubmit = jest.fn();
      const { Wrapper } = createWrapper();
      const { result } = renderHook(() =>
        useForm({
          initialValues: { ...defaultInitialValues, email: 'invalid-email' },
          validationRules: defaultValidationRules,
          onSubmit: mockOnSubmit
        }),
        { wrapper: Wrapper }
      );

      const emailError = result.current.validateField('email');
      expect(emailError).toBe('email format is invalid');

      // Test valid email
      act(() => {
        result.current.setValue('email', 'valid@example.com');
      });

      const validEmailError = result.current.validateField('email');
      expect(validEmailError).toBe(null);
    });

    it('validates custom rules correctly', () => {
      const mockOnSubmit = jest.fn();
      const { Wrapper } = createWrapper();
      const { result } = renderHook(() =>
        useForm({
          initialValues: { ...defaultInitialValues, age: 16 },
          validationRules: defaultValidationRules,
          onSubmit: mockOnSubmit
        }),
        { wrapper: Wrapper }
      );

      const ageError = result.current.validateField('age');
      expect(ageError).toBe('Must be at least 18 years old');

      // Test valid age
      act(() => {
        result.current.setValue('age', 25);
      });

      const validAgeError = result.current.validateField('age');
      expect(validAgeError).toBe(null);
    });

    it('validates entire form correctly', () => {
      const mockOnSubmit = jest.fn();
      const { Wrapper } = createWrapper();
      const { result } = renderHook(() =>
        useForm({
          initialValues: defaultInitialValues,
          validationRules: defaultValidationRules,
          onSubmit: mockOnSubmit
        }),
        { wrapper: Wrapper }
      );

      let isValid: boolean = false;
      
      act(() => {
        isValid = result.current.validateForm();
      });

      expect(isValid).toBe(false);
      expect(result.current.errors.email).toBe('email is required');
      expect(result.current.errors.password).toBe('password is required');
      expect(result.current.errors.name).toBe('name is required');
      expect(result.current.errors.age).toBe('Must be at least 18 years old');
    });

    it('performs real-time validation when enabled', () => {
      const mockOnSubmit = jest.fn();
      const { Wrapper } = createWrapper();
      const { result } = renderHook(() =>
        useForm({
          initialValues: { ...defaultInitialValues, email: 'valid@test.com' }, // Start with valid email
          validationRules: defaultValidationRules,
          onSubmit: mockOnSubmit,
          enableRealTimeValidation: true
        }),
        { wrapper: Wrapper }
      );

      // Change to invalid email
      act(() => {
        result.current.setValue('email', 'invalid');
      });

      expect(result.current.errors.email).toBe('email format is invalid');

      act(() => {
        result.current.setValue('email', 'valid@example.com');
      });

      expect(result.current.errors.email).toBeUndefined();
    });
  });

  describe('event handlers', () => {
    it('handles input changes correctly', () => {
      const mockOnSubmit = jest.fn();
      const { Wrapper } = createWrapper();
      const { result } = renderHook(() =>
        useForm({
          initialValues: defaultInitialValues,
          onSubmit: mockOnSubmit
        }),
        { wrapper: Wrapper }
      );

      const mockEvent = {
        target: {
          name: 'email',
          value: 'test@example.com',
          type: 'email'
        }
      } as React.ChangeEvent<HTMLInputElement>;

      act(() => {
        result.current.handleChange(mockEvent);
      });

      expect(result.current.values.email).toBe('test@example.com');
    });

    it('handles checkbox changes correctly', () => {
      const mockOnSubmit = jest.fn();
      const { Wrapper } = createWrapper();
      const { result } = renderHook(() =>
        useForm({
          initialValues: defaultInitialValues,
          onSubmit: mockOnSubmit
        }),
        { wrapper: Wrapper }
      );

      const mockEvent = {
        target: {
          name: 'acceptTerms',
          checked: true,
          type: 'checkbox'
        }
      } as React.ChangeEvent<HTMLInputElement>;

      act(() => {
        result.current.handleChange(mockEvent);
      });

      expect(result.current.values.acceptTerms).toBe(true);
    });

    it('handles number input changes correctly', () => {
      const mockOnSubmit = jest.fn();
      const { Wrapper } = createWrapper();
      const { result } = renderHook(() =>
        useForm({
          initialValues: defaultInitialValues,
          onSubmit: mockOnSubmit
        }),
        { wrapper: Wrapper }
      );

      const mockEvent = {
        target: {
          name: 'age',
          value: '25',
          type: 'number'
        }
      } as React.ChangeEvent<HTMLInputElement>;

      act(() => {
        result.current.handleChange(mockEvent);
      });

      expect(result.current.values.age).toBe(25);
    });

    it('handles blur events correctly', () => {
      const mockOnSubmit = jest.fn();
      const { Wrapper } = createWrapper();
      const { result } = renderHook(() =>
        useForm({
          initialValues: defaultInitialValues,
          validationRules: defaultValidationRules,
          onSubmit: mockOnSubmit
        }),
        { wrapper: Wrapper }
      );

      const mockEvent = {
        target: {
          name: 'email',
          value: '',
          type: 'email'
        }
      } as React.ChangeEvent<HTMLInputElement>;

      act(() => {
        result.current.handleBlur(mockEvent);
      });

      expect(result.current.touched.email).toBe(true);
      expect(result.current.errors.email).toBe('email is required');
    });
  });

  describe('form submission', () => {
    it('submits form successfully with valid data', async () => {
      const mockOnSubmit = jest.fn().mockResolvedValue(undefined);
      const validData: TestFormData = {
        email: 'test@example.com',
        password: 'password123',
        name: 'John Doe',
        age: 25,
        acceptTerms: true
      };

      const { Wrapper } = createWrapper();
      const { result } = renderHook(() =>
        useForm({
          initialValues: validData,
          validationRules: defaultValidationRules,
          onSubmit: mockOnSubmit
        }),
        { wrapper: Wrapper }
      );

      const mockEvent = {
        preventDefault: jest.fn()
      } as unknown as React.FormEvent;

      await act(async () => {
        await result.current.handleSubmit(mockEvent);
      });

      expect(mockEvent.preventDefault).toHaveBeenCalled();
      expect(mockOnSubmit).toHaveBeenCalledWith(validData);
      // Note: Success notifications are handled by the global notification system
    });

    it('prevents submission with invalid data', async () => {
      const mockOnSubmit = jest.fn();
      const { Wrapper } = createWrapper();
      const { result } = renderHook(() =>
        useForm({
          initialValues: defaultInitialValues,
          validationRules: defaultValidationRules,
          onSubmit: mockOnSubmit
        }),
        { wrapper: Wrapper }
      );

      const mockEvent = {
        preventDefault: jest.fn()
      } as unknown as React.FormEvent;

      await act(async () => {
        await result.current.handleSubmit(mockEvent);
      });

      expect(mockEvent.preventDefault).toHaveBeenCalled();
      expect(mockOnSubmit).not.toHaveBeenCalled();
      // Note: Validation error notifications are handled by the global notification system
      expect(result.current.isValid).toBe(false);
    });

    it('handles submission errors correctly', async () => {
      const submissionError = new Error('Submission failed');
      const mockOnSubmit = jest.fn().mockRejectedValue(submissionError);
      const validData: TestFormData = {
        email: 'test@example.com',
        password: 'password123',
        name: 'John Doe',
        age: 25,
        acceptTerms: true
      };

      const { Wrapper } = createWrapper();
      const { result } = renderHook(() =>
        useForm({
          initialValues: validData,
          validationRules: defaultValidationRules,
          onSubmit: mockOnSubmit
        }),
        { wrapper: Wrapper }
      );

      const mockEvent = {
        preventDefault: jest.fn()
      } as unknown as React.FormEvent;

      await act(async () => {
        await result.current.handleSubmit(mockEvent);
      });

      expect(mockOnSubmit).toHaveBeenCalled();
      // Note: Error notifications are handled by the global notification system
      expect(result.current.isSubmitting).toBe(false);
    });

    it('manages submitting state correctly', async () => {
      let resolveSubmit: () => void;
      const mockOnSubmit = jest.fn().mockImplementation(() => {
        return new Promise<void>((resolve) => {
          resolveSubmit = resolve;
        });
      });

      const validData: TestFormData = {
        email: 'test@example.com',
        password: 'password123',
        name: 'John Doe',
        age: 25,
        acceptTerms: true
      };

      const { Wrapper } = createWrapper();
      const { result } = renderHook(() =>
        useForm({
          initialValues: validData,
          validationRules: defaultValidationRules,
          onSubmit: mockOnSubmit
        }),
        { wrapper: Wrapper }
      );

      const mockEvent = {
        preventDefault: jest.fn()
      } as unknown as React.FormEvent;

      // Start submission - don't await yet
      let submitPromise: Promise<void>;
      act(() => {
        submitPromise = result.current.handleSubmit(mockEvent);
      });

      // Should be submitting immediately after starting
      expect(result.current.isSubmitting).toBe(true);

      // Resolve the async operation
      act(() => {
        resolveSubmit();
      });

      // Wait for submission to complete
      await act(async () => {
        await submitPromise!;
      });

      // Should no longer be submitting
      expect(result.current.isSubmitting).toBe(false);
    });

    it('resets form after successful submission when enabled', async () => {
      const mockOnSubmit = jest.fn().mockResolvedValue(undefined);
      const validData: TestFormData = {
        email: 'test@example.com',
        password: 'password123',
        name: 'John Doe',
        age: 25,
        acceptTerms: true
      };

      const { Wrapper } = createWrapper();
      const { result } = renderHook(() =>
        useForm({
          initialValues: defaultInitialValues,
          validationRules: defaultValidationRules,
          onSubmit: mockOnSubmit,
          resetAfterSubmit: true
        }),
        { wrapper: Wrapper }
      );

      // Set valid data
      act(() => {
        Object.entries(validData).forEach(([key, value]) => {
          result.current.setValue(key as keyof TestFormData, value);
        });
      });

      expect(result.current.values).toEqual(validData);
      expect(result.current.isDirty).toBe(true);

      const mockEvent = {
        preventDefault: jest.fn()
      } as unknown as React.FormEvent;

      await act(async () => {
        await result.current.handleSubmit(mockEvent);
      });

      expect(result.current.values).toEqual(defaultInitialValues);
      expect(result.current.isDirty).toBe(false);
    });
  });

  describe('utility methods', () => {
    it('provides correct field props', () => {
      const mockOnSubmit = jest.fn();
      const { Wrapper } = createWrapper();
      const { result } = renderHook(() =>
        useForm({
          initialValues: defaultInitialValues,
          validationRules: defaultValidationRules,
          onSubmit: mockOnSubmit
        }),
        { wrapper: Wrapper }
      );

      // Touch field and add error
      act(() => {
        result.current.setTouched('email', true);
        result.current.setError('email', 'Invalid email');
      });

      const fieldProps = result.current.getFieldProps('email');

      expect(fieldProps.name).toBe('email');
      expect(fieldProps.value).toBe('');
      expect(fieldProps.error).toBe('Invalid email');
      expect(fieldProps['aria-invalid']).toBe(true);
      expect(fieldProps['aria-describedby']).toBe('email-error');
      expect(typeof fieldProps.onChange).toBe('function');
      expect(typeof fieldProps.onBlur).toBe('function');
    });

    it('resets form correctly', () => {
      const mockOnSubmit = jest.fn();
      const { Wrapper } = createWrapper();
      const { result } = renderHook(() =>
        useForm({
          initialValues: defaultInitialValues,
          validationRules: defaultValidationRules,
          onSubmit: mockOnSubmit
        }),
        { wrapper: Wrapper }
      );

      // Modify form state
      act(() => {
        result.current.setValue('email', 'test@example.com');
        result.current.setTouched('email', true);
        result.current.setError('password', 'Too short');
      });

      expect(result.current.values.email).toBe('test@example.com');
      expect(result.current.touched.email).toBe(true);
      expect(result.current.errors.password).toBe('Too short');

      // Reset form
      act(() => {
        result.current.reset();
      });

      expect(result.current.values).toEqual(defaultInitialValues);
      expect(result.current.touched.email).toBe(false);
      expect(result.current.errors.password).toBeUndefined();
      expect(result.current.isSubmitting).toBe(false);
    });
  });

  describe('component integration', () => {
    const TestForm: React.FC = () => {
      const form = useForm({
        initialValues: { email: '', password: '' },
        validationRules: {
          email: { required: true, pattern: /^[^\s@]+@[^\s@]+\.[^\s@]+$/ },
          password: { required: true, minLength: 8 }
        },
        onSubmit: async (values) => {
          await new Promise(resolve => setTimeout(resolve, 100));
        }
      });

      return (
        <form onSubmit={form.handleSubmit} data-testid="test-form">
          <input
            {...form.getFieldProps('email')}
            type="email"
            placeholder="Email"
            data-testid="email-input"
          />
          {form.errors.email && form.touched.email && (
            <div data-testid="email-error">{form.errors.email}</div>
          )}
          
          <input
            {...form.getFieldProps('password')}
            type="password"
            placeholder="Password"
            data-testid="password-input"
          />
          {form.errors.password && form.touched.password && (
            <div data-testid="password-error">{form.errors.password}</div>
          )}
          
          <button
            type="submit"
            disabled={form.isSubmitting}
            data-testid="submit-button"
          >
            {form.isSubmitting ? 'Submitting...' : 'Submit'}
          </button>
          
          <button
            type="button"
            onClick={form.reset}
            data-testid="reset-button"
          >
            Reset
          </button>
        </form>
      );
    };

    it('integrates correctly with form components', async () => {
      renderWithProviders(<TestForm />, {
        preloadedState: mockAuthenticatedState
      });

      const emailInput = screen.getByTestId('email-input') as HTMLInputElement;
      const passwordInput = screen.getByTestId('password-input') as HTMLInputElement;
      const submitButton = screen.getByTestId('submit-button');

      // Initially no errors shown
      expect(screen.queryByTestId('email-error')).not.toBeInTheDocument();
      expect(screen.queryByTestId('password-error')).not.toBeInTheDocument();

      // Enter invalid data and blur
      fireEvent.change(emailInput, { target: { value: 'invalid-email' } });
      fireEvent.blur(emailInput);

      // Should show validation error
      await waitFor(() => {
        expect(screen.getByTestId('email-error')).toHaveTextContent('email format is invalid');
      });

      // Fix email
      fireEvent.change(emailInput, { target: { value: 'valid@example.com' } });

      // Enter valid password
      fireEvent.change(passwordInput, { target: { value: 'password123' } });

      // Submit form
      fireEvent.click(submitButton);

      // Should show submitting state
      await waitFor(() => {
        expect(submitButton).toHaveTextContent('Submitting...');
        expect(submitButton).toBeDisabled();
      });

      // Should complete submission
      await waitFor(() => {
        expect(submitButton).toHaveTextContent('Submit');
        expect(submitButton).not.toBeDisabled();
      });

      // Note: Success notifications are handled by the global notification system
    });

    it('handles form reset correctly', () => {
      renderWithProviders(<TestForm />, {
        preloadedState: mockAuthenticatedState
      });

      const emailInput = screen.getByTestId('email-input') as HTMLInputElement;
      const resetButton = screen.getByTestId('reset-button');

      // Enter some data
      fireEvent.change(emailInput, { target: { value: 'test@example.com' } });
      expect(emailInput.value).toBe('test@example.com');

      // Reset form
      fireEvent.click(resetButton);
      expect(emailInput.value).toBe('');
    });
  });
});