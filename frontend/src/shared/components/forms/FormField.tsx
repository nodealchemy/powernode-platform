import React from 'react';
import { UseFormReturn } from '@/shared/hooks/useForm';

interface FormFieldProps {
  label: string;
  name: string;
  type?: 'text' | 'email' | 'password' | 'number' | 'tel' | 'url' | 'search';
  placeholder?: string;
  required?: boolean;
  form: UseFormReturn<any>;
  className?: string;
  disabled?: boolean;
  helpText?: string;
  autoComplete?: string;
}

/**
 * Standardized form field component that works with the useForm hook
 * Provides consistent styling, validation display, and accessibility
 */
export const FormField: React.FC<FormFieldProps> = ({
  label,
  name,
  type = 'text',
  placeholder,
  required = false,
  form,
  className = '',
  disabled = false,
  helpText,
  autoComplete
}) => {
  const fieldProps = form.getFieldProps(name);
  const hasError = !!fieldProps.error;

  return (
    <div className={className}>
      <label 
        htmlFor={name} 
        className="block text-sm font-semibold text-theme-primary mb-2"
      >
        {label}
        {required && <span className="text-theme-error ml-1">*</span>}
      </label>
      
      <input
        {...fieldProps}
        type={type}
        id={name}
        placeholder={placeholder}
        disabled={disabled || form.isSubmitting}
        autoComplete={autoComplete}
        className={`w-full px-4 py-3 border rounded-lg bg-theme-surface focus:ring-2 focus:ring-theme-focus focus:border-transparent transition-colors ${
          hasError 
            ? 'border-theme-error focus:ring-theme-error-focus' 
            : 'border-theme'
        } ${
          disabled || form.isSubmitting 
            ? 'opacity-60 cursor-not-allowed' 
            : ''
        }`}
      />
      
      {hasError && (
        <p 
          id={`${name}-error`} 
          className="mt-1 text-sm text-theme-error flex items-center space-x-1"
          role="alert"
        >
          <svg className="w-4 h-4 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20">
            <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
          </svg>
          <span>{fieldProps.error}</span>
        </p>
      )}
      
      {helpText && !hasError && (
        <p className="mt-1 text-sm text-theme-tertiary">
          {helpText}
        </p>
      )}
    </div>
  );
};