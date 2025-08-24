import { useState, useCallback, ChangeEvent, FormEvent } from 'react';
import { useNotification } from './useNotification';

export interface FormValidationRule {
  required?: boolean;
  minLength?: number;
  maxLength?: number;
  pattern?: RegExp;
  custom?: (value: any) => string | null;
}

export interface FormValidationRules {
  [fieldName: string]: FormValidationRule;
}

export interface FormField {
  value: any;
  error?: string;
  touched?: boolean;
}

export interface FormState {
  [fieldName: string]: FormField;
}

export interface UseFormOptions<T> {
  initialValues: T;
  validationRules?: FormValidationRules;
  onSubmit: (values: T) => Promise<void> | void;
  enableRealTimeValidation?: boolean;
  resetAfterSubmit?: boolean;
  showSuccessNotification?: boolean;
  successMessage?: string;
}

export interface UseFormReturn<T> {
  values: T;
  errors: Record<keyof T, string | undefined>;
  touched: Record<keyof T, boolean>;
  isSubmitting: boolean;
  isValid: boolean;
  isDirty: boolean;
  
  // Field methods
  setValue: (field: keyof T, value: any) => void;
  setError: (field: keyof T, error: string) => void;
  clearError: (field: keyof T) => void;
  setTouched: (field: keyof T, touched?: boolean) => void;
  
  // Form methods
  handleChange: (e: ChangeEvent<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>) => void;
  handleBlur: (e: ChangeEvent<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>) => void;
  handleSubmit: (e: FormEvent) => Promise<void>;
  reset: () => void;
  validateField: (field: keyof T) => string | null;
  validateForm: () => boolean;
  
  // Utility methods
  getFieldProps: (field: keyof T) => {
    name: string;
    value: any;
    onChange: (e: ChangeEvent<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>) => void;
    onBlur: (e: ChangeEvent<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>) => void;
    error?: string;
    'aria-invalid': boolean;
    'aria-describedby'?: string;
  };
}

export function useForm<T extends Record<string, any>>(
  options: UseFormOptions<T>
): UseFormReturn<T> {
  const { showNotification } = useNotification();
  const {
    initialValues,
    validationRules = {},
    onSubmit,
    enableRealTimeValidation = false,
    resetAfterSubmit = false,
    showSuccessNotification = true,
    successMessage = 'Form submitted successfully'
  } = options;

  // Create initial form state
  const createInitialState = useCallback(
    (): FormState => {
      const state: FormState = {};
      Object.keys(initialValues).forEach(key => {
        // eslint-disable-next-line security/detect-object-injection
        state[key] = {
          // eslint-disable-next-line security/detect-object-injection
          value: initialValues[key as keyof T],
          error: undefined,
          touched: false
        };
      });
      return state;
    },
    [initialValues]
  );

  const [formState, setFormState] = useState<FormState>(createInitialState);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [submitAttempted, setSubmitAttempted] = useState(false);

  // Extract values, errors, touched from form state
  const values = Object.keys(formState).reduce((acc, key) => {
    // eslint-disable-next-line security/detect-object-injection
    acc[key as keyof T] = formState[key].value;
    return acc;
  }, {} as T);

  const errors = Object.keys(formState).reduce((acc, key) => {
    // eslint-disable-next-line security/detect-object-injection
    acc[key as keyof T] = formState[key].error;
    return acc;
  }, {} as Record<keyof T, string | undefined>);

  const touched = Object.keys(formState).reduce((acc, key) => {
    // eslint-disable-next-line security/detect-object-injection
    acc[key as keyof T] = formState[key].touched || false;
    return acc;
  }, {} as Record<keyof T, boolean>);

  // Validation function for a single field
  const validateField = useCallback(
    (field: keyof T): string | null => {
      const value = formState[field as string]?.value;
      const rules = validationRules[field as string];

      if (!rules) return null;

      // Required validation
      if (rules.required && (value === undefined || value === null || value === '')) {
        return `${String(field)} is required`;
      }

      // Skip other validations if value is empty and not required
      if (!value && !rules.required) return null;

      // String-based validations
      if (typeof value === 'string') {
        // Minimum length validation
        if (rules.minLength && value.length < rules.minLength) {
          return `${String(field)} must be at least ${rules.minLength} characters`;
        }

        // Maximum length validation
        if (rules.maxLength && value.length > rules.maxLength) {
          return `${String(field)} must be no more than ${rules.maxLength} characters`;
        }

        // Pattern validation
        if (rules.pattern && !rules.pattern.test(value)) {
          return `${String(field)} format is invalid`;
        }
      }

      // Custom validation
      if (rules.custom) {
        const customError = rules.custom(value);
        if (customError) return customError;
      }

      return null;
    },
    [formState, validationRules]
  );

  // Validate entire form
  const validateForm = useCallback(
    (): boolean => {
      let hasErrors = false;
      const newState = { ...formState };

      Object.keys(formState).forEach(key => {
        const error = validateField(key as keyof T);
        // eslint-disable-next-line security/detect-object-injection
        newState[key] = {
          // eslint-disable-next-line security/detect-object-injection
          ...newState[key],
          error: error || undefined
        };
        if (error) hasErrors = true;
      });

      setFormState(newState);
      return !hasErrors;
    },
    [formState, validateField]
  );

  // Set field value
  const setValue = useCallback(
    (field: keyof T, value: any) => {
      setFormState(prev => ({
        ...prev,
        [field]: {
          ...prev[field as string],
          value,
          error: enableRealTimeValidation ? validateField(field) || undefined : prev[field as string]?.error
        }
      }));
    },
    [enableRealTimeValidation, validateField]
  );

  // Set field error
  const setError = useCallback(
    (field: keyof T, error: string) => {
      setFormState(prev => ({
        ...prev,
        [field]: {
          ...prev[field as string],
          error
        }
      }));
    },
    []
  );

  // Clear field error
  const clearError = useCallback(
    (field: keyof T) => {
      setFormState(prev => ({
        ...prev,
        [field]: {
          ...prev[field as string],
          error: undefined
        }
      }));
    },
    []
  );

  // Set field touched
  const setTouched = useCallback(
    (field: keyof T, touchedValue = true) => {
      setFormState(prev => ({
        ...prev,
        [field]: {
          ...prev[field as string],
          touched: touchedValue
        }
      }));
    },
    []
  );

  // Handle input changes
  const handleChange = useCallback(
    (e: ChangeEvent<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>) => {
      const { name, value, type } = e.target;
      
      let processedValue: any = value;
      
      // Handle different input types
      if (type === 'checkbox') {
        processedValue = (e.target as HTMLInputElement).checked;
      } else if (type === 'number') {
        processedValue = value === '' ? '' : Number(value);
      }

      setValue(name as keyof T, processedValue);
    },
    [setValue]
  );

  // Handle input blur (for validation)
  const handleBlur = useCallback(
    (e: ChangeEvent<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>) => {
      const { name } = e.target;
      setTouched(name as keyof T, true);
      
      // Validate field on blur if real-time validation is disabled
      if (!enableRealTimeValidation) {
        const error = validateField(name as keyof T);
        if (error) {
          setError(name as keyof T, error);
        } else {
          clearError(name as keyof T);
        }
      }
    },
    [setTouched, enableRealTimeValidation, validateField, setError, clearError]
  );

  // Reset form to initial state
  const reset = useCallback(
    () => {
      setFormState(createInitialState());
      setIsSubmitting(false);
      setSubmitAttempted(false);
    },
    [createInitialState]
  );

  // Handle form submission
  const handleSubmit = useCallback(
    async (e: FormEvent) => {
      e.preventDefault();
      setSubmitAttempted(true);

      // Validate all fields
      const isFormValid = validateForm();
      if (!isFormValid) {
        showNotification('Please correct the errors in the form', 'error');
        return;
      }

      setIsSubmitting(true);

      try {
        await onSubmit(values);
        
        if (showSuccessNotification) {
          showNotification(successMessage, 'success');
        }
        
        if (resetAfterSubmit) {
          reset();
        }
      } catch (error: any) {
        showNotification(
          error?.message || 'An error occurred while submitting the form',
          'error'
        );
      } finally {
        setIsSubmitting(false);
      }
    },
    [validateForm, onSubmit, values, showNotification, showSuccessNotification, successMessage, resetAfterSubmit, reset]
  );

  // Get props for a field (convenience method)
  const getFieldProps = useCallback(
    (field: keyof T) => {
      const fieldState = formState[field as string];
      return {
        name: String(field),
        value: fieldState?.value || '',
        onChange: handleChange,
        onBlur: handleBlur,
        error: (fieldState?.touched || submitAttempted) ? fieldState?.error : undefined,
        'aria-invalid': !!fieldState?.error,
        'aria-describedby': fieldState?.error ? `${String(field)}-error` : undefined
      };
    },
    [formState, handleChange, handleBlur, submitAttempted]
  );

  // Computed properties
  const isValid = Object.values(formState).every(field => !field.error);
  const isDirty = Object.keys(formState).some(key => {
    // eslint-disable-next-line security/detect-object-injection
    return formState[key].value !== initialValues[key as keyof T];
  });

  return {
    values,
    errors,
    touched,
    isSubmitting,
    isValid,
    isDirty,
    setValue,
    setError,
    clearError,
    setTouched,
    handleChange,
    handleBlur,
    handleSubmit,
    reset,
    validateField,
    validateForm,
    getFieldProps
  };
}