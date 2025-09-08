import React from 'react';

export interface SelectProps extends React.SelectHTMLAttributes<HTMLSelectElement> {
  label?: string;
  error?: string;
  fullWidth?: boolean;
}

export const Select: React.FC<SelectProps> = ({
  label,
  error,
  fullWidth = true,
  className = '',
  children,
  ...props
}) => {
  const baseClassName = `
    px-3 py-2 border border-theme rounded-md 
    bg-theme-surface text-theme-primary 
    focus:outline-none focus:ring-2 focus:ring-theme-primary focus:border-transparent
    disabled:bg-theme-background disabled:text-theme-secondary
    ${fullWidth ? 'w-full' : ''}
    ${error ? 'border-red-500 focus:ring-red-500' : ''}
    ${className}
  `.trim();

  return (
    <div className={fullWidth ? 'w-full' : ''}>
      {label && (
        <label className="block text-sm font-medium text-theme-primary mb-1">
          {label}
        </label>
      )}
      <select
        className={baseClassName}
        {...props}
      >
        {children}
      </select>
      {error && (
        <p className="mt-1 text-sm text-red-600">
          {error}
        </p>
      )}
    </div>
  );
};