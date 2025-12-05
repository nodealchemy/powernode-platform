import React from 'react';

export interface InputProps extends React.InputHTMLAttributes<HTMLInputElement> {
  label?: string;
  error?: string;
  fullWidth?: boolean;
}

export const Input: React.FC<InputProps> = ({
  label,
  error,
  fullWidth = true,
  className = '',
  ...props
}) => {
  const inputId = props.id || `input-${Math.random().toString(36).substr(2, 9)}`;
  const baseClassName = `
    px-3 py-2 border border-theme rounded-md 
    bg-theme-surface text-theme-primary 
    placeholder-theme-tertiary 
    focus:outline-none focus:ring-2 focus:ring-theme-primary focus:border-transparent
    disabled:bg-theme-background disabled:text-theme-secondary
    ${fullWidth ? 'w-full' : ''}
    ${error ? 'border-theme-error focus:ring-theme-error' : ''}
    ${className}
  `.trim();

  return (
    <div className={fullWidth ? 'w-full' : ''}>
      {label && (
        <label 
          htmlFor={inputId}
          className="block text-sm font-medium text-theme-primary mb-1"
        >
          {label}
        </label>
      )}
      <input
        id={inputId}
        className={baseClassName}
        aria-describedby={error ? `${inputId}-error` : undefined}
        {...props}
      />
      {error && (
        <p id={`${inputId}-error`} className="mt-1 text-sm text-theme-error" role="alert">
          {error}
        </p>
      )}
    </div>
  );
};