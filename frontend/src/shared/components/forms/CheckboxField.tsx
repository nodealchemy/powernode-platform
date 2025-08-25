import React from 'react';
import { UseFormReturn } from '@/shared/hooks/useForm';

interface CheckboxFieldProps {
  label: string | React.ReactNode;
  name: string;
  form: UseFormReturn<any>;
  className?: string;
  disabled?: boolean;
  helpText?: string;
  required?: boolean;
  variant?: 'default' | 'card';
}

/**
 * Standardized checkbox field component that works with the useForm hook
 * Provides consistent styling, validation display, and accessibility
 */
export const CheckboxField: React.FC<CheckboxFieldProps> = ({
  label,
  name,
  form,
  className = '',
  disabled = false,
  helpText,
  required = false,
  variant = 'default'
}) => {
  const fieldProps = form.getFieldProps(name);
  const hasError = !!fieldProps.error;

  if (variant === 'card') {
    return (
      <div className={`${className}`}>
        <label 
          htmlFor={name}
          className={`flex items-start space-x-3 p-4 border rounded-lg cursor-pointer transition-colors ${
            fieldProps.value 
              ? 'border-theme-focus bg-theme-interactive-secondary' 
              : 'border-theme hover:border-theme-focus'
          } ${
            disabled || form.isSubmitting 
              ? 'opacity-60 cursor-not-allowed' 
              : ''
          } ${
            hasError ? 'border-theme-error' : ''
          }`}
        >
          <input
            {...fieldProps}
            type="checkbox"
            id={name}
            disabled={disabled || form.isSubmitting}
            className="mt-1 h-4 w-4 text-theme-interactive-primary focus:ring-theme-focus border-theme rounded"
          />
          <div className="flex-1">
            <div className="text-sm font-medium text-theme-primary">
              {label}
              {required && <span className="text-theme-error ml-1">*</span>}
            </div>
            {helpText && (
              <div className="mt-1 text-sm text-theme-secondary">
                {helpText}
              </div>
            )}
          </div>
        </label>
        
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
      </div>
    );
  }

  return (
    <div className={className}>
      <div className="flex items-start space-x-3">
        <input
          {...fieldProps}
          type="checkbox"
          id={name}
          disabled={disabled || form.isSubmitting}
          className={`mt-1 h-4 w-4 text-theme-interactive-primary focus:ring-theme-focus border-theme rounded ${
            disabled || form.isSubmitting 
              ? 'opacity-60 cursor-not-allowed' 
              : ''
          }`}
        />
        <label 
          htmlFor={name}
          className={`text-sm text-theme-primary ${
            disabled || form.isSubmitting 
              ? 'opacity-60 cursor-not-allowed' 
              : 'cursor-pointer'
          }`}
        >
          {label}
          {required && <span className="text-theme-error ml-1">*</span>}
        </label>
      </div>
      
      {helpText && !hasError && (
        <p className="mt-1 ml-7 text-sm text-theme-tertiary">
          {helpText}
        </p>
      )}
      
      {hasError && (
        <p 
          id={`${name}-error`} 
          className="mt-1 ml-7 text-sm text-theme-error flex items-center space-x-1"
          role="alert"
        >
          <svg className="w-4 h-4 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20">
            <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
          </svg>
          <span>{fieldProps.error}</span>
        </p>
      )}
    </div>
  );
};