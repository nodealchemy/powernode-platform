/**
 * Specialized email input field with built-in validation
 */

import { EnvelopeIcon } from '@heroicons/react/24/outline';
import React from 'react';

interface EmailFieldProps {
  name: string;
  label?: string;
  placeholder?: string;
  required?: boolean;
  value: string;
  error?: string;
  touched?: boolean;
  onChange: (e: React.ChangeEvent<HTMLInputElement>) => void;
  onBlur: (e: React.FocusEvent<HTMLInputElement>) => void;
  disabled?: boolean;
  className?: string;
  autoComplete?: string;
}

export const EmailField: React.FC<EmailFieldProps> = ({
  name,
  label = 'Email Address',
  placeholder = 'Enter your email address',
  required = false,
  value,
  error,
  touched,
  onChange,
  onBlur,
  disabled = false,
  className = '',
  autoComplete = 'email'
}) => {
  const hasError = touched && error;

  return (
    <div className={className}>
      {label && (
        <label 
          htmlFor={name} 
          className="block text-sm font-medium text-theme-primary mb-1"
        >
          {label}
          {required && <span className="text-theme-error ml-1">*</span>}
        </label>
      )}
      
      <div className="relative">
        <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
          <EnvelopeIcon className="h-5 w-5 text-theme-secondary" />
        </div>
        
        <input
          id={name}
          name={name}
          type="email"
          value={value}
          onChange={(e) => void onChange(e)}
          onBlur={onBlur}
          disabled={disabled}
          placeholder={placeholder}
          autoComplete={autoComplete}
          aria-invalid={hasError ? "true" : "false"}
          aria-describedby={hasError ? `${name}-error` : undefined}
          className={`
            w-full pl-10 pr-3 py-2 
            border rounded-lg 
            bg-theme-surface 
            text-theme-primary
            placeholder-theme-tertiary
            transition-all duration-200
            focus:outline-none focus:ring-2 focus:ring-offset-0
            ${hasError 
              ? 'border-theme-error focus:ring-theme-error focus:border-theme-error' 
              : 'border-theme focus:ring-theme-focus focus:border-theme-focus'
            }
            ${disabled ? 'opacity-60 cursor-not-allowed' : ''}
          `}
        />
      </div>
      
      {hasError && (
        <p 
          id={`${name}-error`}
          className="mt-1 text-sm text-theme-error"
          role="alert"
        >
          {error}
        </p>
      )}
    </div>
  );
};