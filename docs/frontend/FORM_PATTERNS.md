# Form Patterns Documentation

This document outlines the standardized form patterns for the Powernode platform, including the useForm hook and best practices.

## Table of Contents

1. [useForm Hook Overview](#useform-hook-overview)
2. [Basic Usage](#basic-usage)
3. [Validation Patterns](#validation-patterns)
4. [Advanced Features](#advanced-features)
5. [Form Components](#form-components)
6. [Best Practices](#best-practices)
7. [Examples](#examples)
8. [Migration Guide](#migration-guide)

## useForm Hook Overview

The `useForm` hook provides a standardized way to handle forms across the Powernode platform. It includes:

- **State Management**: Automatic handling of form values, errors, and touched states
- **Validation**: Built-in validation rules with custom validation support
- **Submission Handling**: Standardized form submission with loading states
- **Global Notifications**: Automatic integration with the notification system
- **Accessibility**: Built-in ARIA attributes for accessibility
- **TypeScript Support**: Full TypeScript support with type safety

### Key Features

- ✅ Real-time or blur validation
- ✅ Automatic error handling and notifications
- ✅ Loading states during submission
- ✅ Form reset functionality
- ✅ Dirty state tracking
- ✅ Accessibility attributes
- ✅ TypeScript type safety
- ✅ Integration with global notification system

## Basic Usage

### Simple Form Example

```typescript
import { useForm } from '@/shared/hooks/useForm';

interface UserFormData {
  email: string;
  name: string;
  password: string;
}

const UserForm: React.FC = () => {
  const form = useForm<UserFormData>({
    initialValues: {
      email: '',
      name: '',
      password: ''
    },
    validationRules: {
      email: {
        required: true,
        pattern: /^[^\s@]+@[^\s@]+\.[^\s@]+$/
      },
      name: {
        required: true,
        minLength: 2,
        maxLength: 100
      },
      password: {
        required: true,
        minLength: 8
      }
    },
    onSubmit: async (values) => {
      await userApi.createUser(values);
    },
    successMessage: 'User created successfully'
  });

  return (
    <form onSubmit={form.handleSubmit} className="space-y-6">
      <div>
        <label htmlFor="email" className="block text-sm font-semibold text-theme-primary mb-2">
          Email Address
        </label>
        <input
          {...form.getFieldProps('email')}
          type="email"
          id="email"
          className="w-full px-4 py-3 border border-theme rounded-lg bg-theme-surface focus:ring-2 focus:ring-theme-focus focus:border-transparent"
        />
        {form.getFieldProps('email').error && (
          <p id="email-error" className="mt-1 text-sm text-theme-error">
            {form.getFieldProps('email').error}
          </p>
        )}
      </div>

      <div>
        <label htmlFor="name" className="block text-sm font-semibold text-theme-primary mb-2">
          Full Name
        </label>
        <input
          {...form.getFieldProps('name')}
          type="text"
          id="name"
          className="w-full px-4 py-3 border border-theme rounded-lg bg-theme-surface focus:ring-2 focus:ring-theme-focus focus:border-transparent"
        />
        {form.getFieldProps('name').error && (
          <p id="name-error" className="mt-1 text-sm text-theme-error">
            {form.getFieldProps('name').error}
          </p>
        )}
      </div>

      <div>
        <label htmlFor="password" className="block text-sm font-semibold text-theme-primary mb-2">
          Password
        </label>
        <input
          {...form.getFieldProps('password')}
          type="password"
          id="password"
          className="w-full px-4 py-3 border border-theme rounded-lg bg-theme-surface focus:ring-2 focus:ring-theme-focus focus:border-transparent"
        />
        {form.getFieldProps('password').error && (
          <p id="password-error" className="mt-1 text-sm text-theme-error">
            {form.getFieldProps('password').error}
          </p>
        )}
      </div>

      <button
        type="submit"
        disabled={form.isSubmitting || !form.isValid}
        className="w-full py-3 px-4 bg-theme-interactive-primary text-white font-semibold rounded-lg hover:bg-theme-interactive-primary-hover disabled:opacity-50 disabled:cursor-not-allowed"
      >
        {form.isSubmitting ? 'Creating User...' : 'Create User'}
      </button>
    </form>
  );
};
```

## Validation Patterns

### Built-in Validation Rules

```typescript
const validationRules = {
  fieldName: {
    required: true,                    // Field is required
    minLength: 3,                     // Minimum character length
    maxLength: 100,                   // Maximum character length
    pattern: /^[A-Za-z0-9]+$/,       // RegExp pattern validation
    custom: (value) => {              // Custom validation function
      if (value === 'forbidden') {
        return 'This value is not allowed';
      }
      return null; // No error
    }
  }
};
```

### Common Validation Patterns

```typescript
// Email validation
email: {
  required: true,
  pattern: /^[^\s@]+@[^\s@]+\.[^\s@]+$/,
  custom: (value) => {
    if (value && !value.includes('@')) {
      return 'Please enter a valid email address';
    }
    return null;
  }
}

// Password validation
password: {
  required: true,
  minLength: 8,
  custom: (value) => {
    if (value && !/(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/.test(value)) {
      return 'Password must contain at least one uppercase letter, one lowercase letter, and one number';
    }
    return null;
  }
}

// Confirm password validation
confirmPassword: {
  required: true,
  custom: (value, allValues) => {
    if (value !== allValues.password) {
      return 'Passwords do not match';
    }
    return null;
  }
}

// URL validation
website: {
  pattern: /^https?:\/\/.+/,
  custom: (value) => {
    if (value && !value.startsWith('http')) {
      return 'URL must start with http:// or https://';
    }
    return null;
  }
}

// Phone validation
phone: {
  pattern: /^\+?[\d\s-()]+$/,
  minLength: 10,
  maxLength: 15
}
```

## Advanced Features

### Real-time Validation

```typescript
const form = useForm({
  // ... other options
  enableRealTimeValidation: true // Validate fields as user types
});
```

### Custom Submit Handling

```typescript
const form = useForm({
  // ... other options
  onSubmit: async (values) => {
    try {
      const result = await api.submitData(values);
      
      // Custom success handling
      if (result.requiresVerification) {
        showNotification('Please check your email for verification', 'info');
        navigate('/verify-email');
      }
    } catch (error) {
      // Custom error handling
      if (error.status === 409) {
        form.setError('email', 'Email address already exists');
        return; // Don't show generic error notification
      }
      throw error; // Let useForm handle other errors
    }
  },
  showSuccessNotification: false // Disable default success notification
});
```

### Programmatic Form Control

```typescript
const form = useForm(/* ... */);

// Set field values programmatically
useEffect(() => {
  if (existingUser) {
    form.setValue('email', existingUser.email);
    form.setValue('name', existingUser.name);
  }
}, [existingUser]);

// Validate specific field
const handleEmailCheck = async () => {
  const emailError = form.validateField('email');
  if (!emailError) {
    const isAvailable = await api.checkEmailAvailability(form.values.email);
    if (!isAvailable) {
      form.setError('email', 'Email address is already taken');
    }
  }
};

// Reset form
const handleCancel = () => {
  form.reset();
  onCancel();
};
```

## Form Components

### FormField Component

Create reusable form field components:

```typescript
interface FormFieldProps {
  label: string;
  name: string;
  type?: 'text' | 'email' | 'password' | 'number' | 'tel' | 'url';
  placeholder?: string;
  required?: boolean;
  form: UseFormReturn<any>;
  className?: string;
}

const FormField: React.FC<FormFieldProps> = ({
  label,
  name,
  type = 'text',
  placeholder,
  required,
  form,
  className = ''
}) => {
  const fieldProps = form.getFieldProps(name);

  return (
    <div className={className}>
      <label htmlFor={name} className="block text-sm font-semibold text-theme-primary mb-2">
        {label}
        {required && <span className="text-theme-error ml-1">*</span>}
      </label>
      <input
        {...fieldProps}
        type={type}
        id={name}
        placeholder={placeholder}
        className={`w-full px-4 py-3 border rounded-lg bg-theme-surface focus:ring-2 focus:ring-theme-focus focus:border-transparent ${
          fieldProps.error ? 'border-theme-error' : 'border-theme'
        }`}
      />
      {fieldProps.error && (
        <p id={`${name}-error`} className="mt-1 text-sm text-theme-error">
          {fieldProps.error}
        </p>
      )}
    </div>
  );
};

// Usage
<FormField
  label="Email Address"
  name="email"
  type="email"
  required
  form={form}
  className="mb-6"
/>
```

### SelectField Component

```typescript
interface SelectFieldProps {
  label: string;
  name: string;
  options: { value: string; label: string }[];
  placeholder?: string;
  required?: boolean;
  form: UseFormReturn<any>;
  className?: string;
}

const SelectField: React.FC<SelectFieldProps> = ({
  label,
  name,
  options,
  placeholder,
  required,
  form,
  className = ''
}) => {
  const fieldProps = form.getFieldProps(name);

  return (
    <div className={className}>
      <label htmlFor={name} className="block text-sm font-semibold text-theme-primary mb-2">
        {label}
        {required && <span className="text-theme-error ml-1">*</span>}
      </label>
      <select
        {...fieldProps}
        id={name}
        className={`w-full px-4 py-3 border rounded-lg bg-theme-surface focus:ring-2 focus:ring-theme-focus focus:border-transparent ${
          fieldProps.error ? 'border-theme-error' : 'border-theme'
        }`}
      >
        {placeholder && <option value="">{placeholder}</option>}
        {options.map(option => (
          <option key={option.value} value={option.value}>
            {option.label}
          </option>
        ))}
      </select>
      {fieldProps.error && (
        <p id={`${name}-error`} className="mt-1 text-sm text-theme-error">
          {fieldProps.error}
        </p>
      )}
    </div>
  );
};
```

## Best Practices

### 1. Form Structure

```typescript
// ✅ CORRECT - Structured form with proper TypeScript
interface FormData {
  field1: string;
  field2: number;
}

const form = useForm<FormData>({
  initialValues: { field1: '', field2: 0 },
  validationRules: { /* rules */ },
  onSubmit: async (values) => { /* submit logic */ }
});

// ❌ WRONG - Untyped form
const form = useForm({
  initialValues: {},
  onSubmit: (values) => { /* no type safety */ }
});
```

### 2. Error Handling

```typescript
// ✅ CORRECT - Let useForm handle notifications
onSubmit: async (values) => {
  await api.submitData(values);
  // useForm automatically shows success notification
}

// ❌ WRONG - Manual error state management
const [error, setError] = useState('');
const handleSubmit = async () => {
  try {
    await api.submitData();
    setError('');
  } catch (err) {
    setError(err.message);
  }
};
```

### 3. Accessibility

```typescript
// ✅ CORRECT - Use getFieldProps for accessibility
<input {...form.getFieldProps('email')} />

// ❌ WRONG - Manual props without accessibility
<input
  value={form.values.email}
  onChange={form.handleChange}
  // Missing aria-invalid, aria-describedby
/>
```

### 4. Loading States

```typescript
// ✅ CORRECT - Use built-in loading state
<button 
  type="submit" 
  disabled={form.isSubmitting}
  className={`btn-primary ${form.isSubmitting ? 'opacity-50 cursor-not-allowed' : ''}`}
>
  {form.isSubmitting ? 'Submitting...' : 'Submit'}
</button>

// ❌ WRONG - Manual loading state
const [loading, setLoading] = useState(false);
```

## Examples

### User Registration Form

```typescript
const RegisterForm: React.FC = () => {
  const form = useForm<{
    email: string;
    password: string;
    confirmPassword: string;
    firstName: string;
    lastName: string;
    acceptTerms: boolean;
  }>({
    initialValues: {
      email: '',
      password: '',
      confirmPassword: '',
      firstName: '',
      lastName: '',
      acceptTerms: false
    },
    validationRules: {
      email: {
        required: true,
        pattern: /^[^\s@]+@[^\s@]+\.[^\s@]+$/
      },
      password: {
        required: true,
        minLength: 8,
        custom: (value) => {
          if (!/(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/.test(value)) {
            return 'Password must contain uppercase, lowercase, and number';
          }
          return null;
        }
      },
      confirmPassword: {
        required: true,
        custom: (value, allValues) => {
          if (value !== allValues?.password) {
            return 'Passwords do not match';
          }
          return null;
        }
      },
      firstName: { required: true, minLength: 2 },
      lastName: { required: true, minLength: 2 },
      acceptTerms: {
        custom: (value) => value ? null : 'You must accept the terms and conditions'
      }
    },
    onSubmit: async (values) => {
      await authAPI.register(values);
    },
    successMessage: 'Registration successful! Please check your email for verification.'
  });

  return (
    <form onSubmit={form.handleSubmit} className="space-y-6">
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <FormField label="First Name" name="firstName" required form={form} />
        <FormField label="Last Name" name="lastName" required form={form} />
      </div>
      
      <FormField label="Email Address" name="email" type="email" required form={form} />
      <FormField label="Password" name="password" type="password" required form={form} />
      <FormField label="Confirm Password" name="confirmPassword" type="password" required form={form} />
      
      <div className="flex items-start space-x-3">
        <input
          {...form.getFieldProps('acceptTerms')}
          type="checkbox"
          id="acceptTerms"
          className="mt-1 h-4 w-4 text-theme-interactive-primary focus:ring-theme-focus border-theme rounded"
        />
        <label htmlFor="acceptTerms" className="text-sm text-theme-secondary">
          I accept the <a href="/terms" className="text-theme-link hover:underline">Terms and Conditions</a> and{' '}
          <a href="/privacy" className="text-theme-link hover:underline">Privacy Policy</a>
        </label>
      </div>
      {form.getFieldProps('acceptTerms').error && (
        <p className="text-sm text-theme-error">{form.getFieldProps('acceptTerms').error}</p>
      )}

      <button
        type="submit"
        disabled={form.isSubmitting || !form.isValid}
        className="w-full py-3 px-4 bg-theme-interactive-primary text-white font-semibold rounded-lg hover:bg-theme-interactive-primary-hover disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
      >
        {form.isSubmitting ? 'Creating Account...' : 'Create Account'}
      </button>
    </form>
  );
};
```

### Settings Form with Auto-Save

```typescript
const SettingsForm: React.FC = () => {
  const form = useForm<{
    companyName: string;
    website: string;
    timezone: string;
    emailNotifications: boolean;
  }>({
    initialValues: {
      companyName: '',
      website: '',
      timezone: 'UTC',
      emailNotifications: true
    },
    validationRules: {
      companyName: { required: true, minLength: 2, maxLength: 100 },
      website: { pattern: /^https?:\/\/.+/ },
      timezone: { required: true }
    },
    enableRealTimeValidation: true,
    onSubmit: async (values) => {
      await settingsApi.updateSettings(values);
    },
    showSuccessNotification: false // We'll show a subtle success message
  });

  // Auto-save functionality
  useEffect(() => {
    if (form.isDirty && form.isValid) {
      const timer = setTimeout(() => {
        form.handleSubmit(new Event('submit') as any);
      }, 2000); // Auto-save after 2 seconds of inactivity
      
      return () => clearTimeout(timer);
    }
  }, [form.values, form.isDirty, form.isValid]);

  return (
    <form onSubmit={form.handleSubmit} className="space-y-6">
      <FormField 
        label="Company Name" 
        name="companyName" 
        required 
        form={form} 
      />
      
      <FormField 
        label="Website" 
        name="website" 
        type="url" 
        placeholder="https://example.com" 
        form={form} 
      />
      
      <SelectField
        label="Timezone"
        name="timezone"
        required
        form={form}
        options={[
          { value: 'UTC', label: 'UTC' },
          { value: 'America/New_York', label: 'Eastern Time' },
          { value: 'America/Los_Angeles', label: 'Pacific Time' },
          // ... more timezones
        ]}
      />
      
      <div className="flex items-center space-x-3">
        <input
          {...form.getFieldProps('emailNotifications')}
          type="checkbox"
          id="emailNotifications"
          className="h-4 w-4 text-theme-interactive-primary focus:ring-theme-focus border-theme rounded"
        />
        <label htmlFor="emailNotifications" className="text-sm font-medium text-theme-primary">
          Receive email notifications
        </label>
      </div>

      <div className="flex items-center justify-between">
        <div className="flex items-center space-x-2 text-sm text-theme-secondary">
          {form.isDirty && <span>Unsaved changes</span>}
          {form.isSubmitting && <span>Saving...</span>}
        </div>
        
        <div className="flex items-center space-x-3">
          <button
            type="button"
            onClick={form.reset}
            disabled={!form.isDirty || form.isSubmitting}
            className="px-4 py-2 text-sm font-medium text-theme-secondary hover:text-theme-primary disabled:opacity-50"
          >
            Reset
          </button>
          
          <button
            type="submit"
            disabled={!form.isDirty || !form.isValid || form.isSubmitting}
            className="px-4 py-2 bg-theme-interactive-primary text-white font-medium rounded-lg hover:bg-theme-interactive-primary-hover disabled:opacity-50 disabled:cursor-not-allowed"
          >
            Save Changes
          </button>
        </div>
      </div>
    </form>
  );
};
```

## Migration Guide

### From Manual Form State

**Before:**
```typescript
const [formData, setFormData] = useState({ email: '', name: '' });
const [errors, setErrors] = useState<Record<string, string>>({});
const [loading, setLoading] = useState(false);

const handleChange = (e: ChangeEvent<HTMLInputElement>) => {
  setFormData(prev => ({ ...prev, [e.target.name]: e.target.value }));
  if (errors[e.target.name]) {
    setErrors(prev => ({ ...prev, [e.target.name]: '' }));
  }
};

const handleSubmit = async (e: FormEvent) => {
  e.preventDefault();
  setLoading(true);
  try {
    await api.submit(formData);
    showNotification('Success!', 'success');
  } catch (error) {
    showNotification('Error!', 'error');
  } finally {
    setLoading(false);
  }
};
```

**After:**
```typescript
const form = useForm({
  initialValues: { email: '', name: '' },
  validationRules: {
    email: { required: true, pattern: /^[^\s@]+@[^\s@]+\.[^\s@]+$/ },
    name: { required: true, minLength: 2 }
  },
  onSubmit: async (values) => {
    await api.submit(values);
  }
});
```

### Migration Checklist

1. ✅ Replace manual state management with useForm
2. ✅ Move validation logic to validationRules
3. ✅ Remove manual error state management
4. ✅ Remove manual loading state management
5. ✅ Use getFieldProps for input props
6. ✅ Remove manual notification calls (useForm handles it)
7. ✅ Add proper TypeScript types
8. ✅ Update tests to work with new form structure

## Testing Forms

```typescript
import { render, screen, fireEvent, waitFor } from '@/shared/utils/test-utils';
import { UserForm } from './UserForm';

describe('UserForm', () => {
  it('validates required fields', async () => {
    render(<UserForm />);
    
    const submitButton = screen.getByRole('button', { name: /submit/i });
    fireEvent.click(submitButton);
    
    await waitFor(() => {
      expect(screen.getByText('Email is required')).toBeInTheDocument();
      expect(screen.getByText('Name is required')).toBeInTheDocument();
    });
  });

  it('submits form with valid data', async () => {
    const mockSubmit = jest.fn();
    render(<UserForm onSubmit={mockSubmit} />);
    
    fireEvent.change(screen.getByLabelText(/email/i), {
      target: { value: 'test@example.com' }
    });
    fireEvent.change(screen.getByLabelText(/name/i), {
      target: { value: 'John Doe' }
    });
    
    fireEvent.click(screen.getByRole('button', { name: /submit/i }));
    
    await waitFor(() => {
      expect(mockSubmit).toHaveBeenCalledWith({
        email: 'test@example.com',
        name: 'John Doe'
      });
    });
  });
});
```

---

This documentation provides a comprehensive guide to using the standardized form patterns in the Powernode platform. Following these patterns ensures consistency, accessibility, and maintainability across all forms in the application.