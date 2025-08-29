import React from 'react';
import { useForm } from '@/shared/hooks/useForm';

interface ExampleFormData {
  email: string;
  name: string;
  message: string;
  newsletter: boolean;
}

interface ExampleFormProps {
  onSubmit?: (data: ExampleFormData) => Promise<void>;
  className?: string;
}

/**
 * Example form demonstrating the useForm hook usage
 * This serves as a reference implementation for other forms in the application
 */
export const ExampleForm: React.FC<ExampleFormProps> = ({ 
  onSubmit = async (data) => {
    // Simulate API call
    await new Promise(resolve => setTimeout(resolve, 1000));
  },
  className = ''
}) => {
  const form = useForm<ExampleFormData>({
    initialValues: {
      email: '',
      name: '',
      message: '',
      newsletter: false
    },
    validationRules: {
      email: {
        required: true,
        pattern: /^[^\s@]+@[^\s@]+\.[^\s@]+$/,
        custom: (value: unknown) => {
          if (typeof value === 'string' && value.includes('test@')) {
            return 'Test emails are not allowed';
          }
          return null;
        }
      },
      name: {
        required: true,
        minLength: 2,
        maxLength: 100
      },
      message: {
        required: true,
        minLength: 10,
        maxLength: 500
      }
    },
    onSubmit,
    enableRealTimeValidation: false,
    resetAfterSubmit: true,
    successMessage: 'Form submitted successfully!'
  });

  return (
    <div className={`max-w-md mx-auto ${className}`}>
      <div className="bg-theme-surface rounded-xl border border-theme p-6 shadow-lg">
        <h2 className="text-xl font-bold text-theme-primary mb-6">Contact Form</h2>
        
        <form onSubmit={form.handleSubmit} className="space-y-6">
          {/* Email Field */}
          <div>
            <label htmlFor="email" className="block text-sm font-semibold text-theme-primary mb-2">
              Email Address <span className="text-theme-error">*</span>
            </label>
            <input
              {...form.getFieldProps('email')}
              type="email"
              id="email"
              placeholder="Enter your email address"
              className={`w-full px-4 py-3 border rounded-lg bg-theme-surface focus:ring-2 focus:ring-theme-focus focus:border-transparent transition-colors ${
                form.getFieldProps('email').error ? 'border-theme-error' : 'border-theme'
              }`}
            />
            {form.getFieldProps('email').error && (
              <p id="email-error" className="mt-1 text-sm text-theme-error">
                {form.getFieldProps('email').error}
              </p>
            )}
          </div>

          {/* Name Field */}
          <div>
            <label htmlFor="name" className="block text-sm font-semibold text-theme-primary mb-2">
              Full Name <span className="text-theme-error">*</span>
            </label>
            <input
              {...form.getFieldProps('name')}
              type="text"
              id="name"
              placeholder="Enter your full name"
              className={`w-full px-4 py-3 border rounded-lg bg-theme-surface focus:ring-2 focus:ring-theme-focus focus:border-transparent transition-colors ${
                form.getFieldProps('name').error ? 'border-theme-error' : 'border-theme'
              }`}
            />
            {form.getFieldProps('name').error && (
              <p id="name-error" className="mt-1 text-sm text-theme-error">
                {form.getFieldProps('name').error}
              </p>
            )}
          </div>

          {/* Message Field */}
          <div>
            <label htmlFor="message" className="block text-sm font-semibold text-theme-primary mb-2">
              Message <span className="text-theme-error">*</span>
            </label>
            <textarea
              {...form.getFieldProps('message')}
              id="message"
              rows={4}
              placeholder="Enter your message (minimum 10 characters)"
              className={`w-full px-4 py-3 border rounded-lg bg-theme-surface focus:ring-2 focus:ring-theme-focus focus:border-transparent transition-colors resize-vertical ${
                form.getFieldProps('message').error ? 'border-theme-error' : 'border-theme'
              }`}
            />
            {form.getFieldProps('message').error && (
              <p id="message-error" className="mt-1 text-sm text-theme-error">
                {form.getFieldProps('message').error}
              </p>
            )}
            <div className="mt-1 text-xs text-theme-tertiary">
              {form.values.message.length}/500 characters
            </div>
          </div>

          {/* Newsletter Checkbox */}
          <div className="flex items-start space-x-3">
            <input
              {...form.getFieldProps('newsletter')}
              type="checkbox"
              id="newsletter"
              className="mt-1 h-4 w-4 text-theme-interactive-primary focus:ring-theme-focus border-theme rounded"
            />
            <label htmlFor="newsletter" className="text-sm text-theme-secondary">
              I would like to receive newsletter updates and promotional emails
            </label>
          </div>

          {/* Form Status */}
          <div className="flex items-center justify-between text-sm">
            <div className="flex items-center space-x-4">
              {form.isDirty && (
                <span className="text-theme-warning">Unsaved changes</span>
              )}
              {!form.isValid && form.values.email && (
                <span className="text-theme-error">Please fix errors</span>
              )}
            </div>
            <div className="text-theme-tertiary">
              {form.isSubmitting && 'Submitting...'}
            </div>
          </div>

          {/* Action Buttons */}
          <div className="flex items-center space-x-3">
            <button
              type="button"
              onClick={form.reset}
              disabled={!form.isDirty || form.isSubmitting}
              className="flex-1 py-3 px-4 border border-theme text-theme-secondary font-semibold rounded-lg hover:bg-theme-interactive-secondary hover:text-theme-primary disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              Reset
            </button>
            
            <button
              type="submit"
              disabled={form.isSubmitting || !form.isValid}
              className="flex-1 py-3 px-4 bg-theme-interactive-primary text-white font-semibold rounded-lg hover:bg-theme-interactive-primary-hover disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              {form.isSubmitting ? 'Submitting...' : 'Submit'}
            </button>
          </div>
        </form>

        {/* Form Debug Info (for development) */}
        {process.env.NODE_ENV === 'development' && (
          <details className="mt-6 text-xs">
            <summary className="cursor-pointer text-theme-tertiary hover:text-theme-secondary">
              Debug Info
            </summary>
            <pre className="mt-2 p-2 bg-theme-background border border-theme rounded text-theme-secondary overflow-auto">
              {JSON.stringify({ 
                values: form.values, 
                errors: form.errors, 
                touched: form.touched,
                isValid: form.isValid,
                isDirty: form.isDirty,
                isSubmitting: form.isSubmitting
              }, null, 2)}
            </pre>
          </details>
        )}
      </div>
    </div>
  );
};