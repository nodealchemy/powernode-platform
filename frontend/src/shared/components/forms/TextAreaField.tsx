import React from 'react';
import { UseFormReturn } from '@/shared/hooks/useForm';

interface TextAreaFieldProps {
  label: string;
  name: string;
  placeholder?: string;
  required?: boolean;
  form: UseFormReturn<any>;
  className?: string;
  disabled?: boolean;
  helpText?: string;
  rows?: number;
  maxLength?: number;
  showCharacterCount?: boolean;
  resize?: 'none' | 'both' | 'horizontal' | 'vertical';
}

/**
 * Standardized textarea field component that works with the useForm hook
 * Provides consistent styling, validation display, character counting, and accessibility
 */
export const TextAreaField: React.FC<TextAreaFieldProps> = ({
  label,
  name,
  placeholder,
  required = false,
  form,
  className = '',
  disabled = false,
  helpText,
  rows = 4,
  maxLength,
  showCharacterCount = false,
  resize = 'vertical'
}) => {
  const fieldProps = form.getFieldProps(name);
  const hasError = !!fieldProps.error;
  const value = fieldProps.value || '';
  const characterCount = typeof value === 'string' ? value.length : 0;

  const resizeClasses = {
    none: 'resize-none',
    both: 'resize',
    horizontal: 'resize-x',
    vertical: 'resize-y'
  };
  const resizeClass = Object.prototype.hasOwnProperty.call(resizeClasses, resize) ? resizeClasses[resize as keyof typeof resizeClasses] : 'resize-none';

  return (
    <div className={className}>
      <label 
        htmlFor={name} 
        className="block text-sm font-semibold text-theme-primary mb-2"
      >
        {label}
        {required && <span className="text-theme-error ml-1">*</span>}
      </label>
      
      <textarea
        {...fieldProps}
        id={name}
        placeholder={placeholder}
        disabled={disabled || form.isSubmitting}
        rows={rows}
        maxLength={maxLength}
        className={`w-full px-4 py-3 border rounded-lg bg-theme-surface focus:ring-2 focus:ring-theme-focus focus:border-transparent transition-colors ${resizeClass} ${
          hasError 
            ? 'border-theme-error focus:ring-theme-error-focus' 
            : 'border-theme'
        } ${
          disabled || form.isSubmitting 
            ? 'opacity-60 cursor-not-allowed' 
            : ''
        }`}
      />
      
      {(showCharacterCount || maxLength) && (
        <div className="mt-1 text-xs text-theme-tertiary text-right">
          {characterCount}{maxLength && `/${maxLength}`} character{characterCount !== 1 ? 's' : ''}
        </div>
      )}
      
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