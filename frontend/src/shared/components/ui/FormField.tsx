import React, { forwardRef, useState } from 'react';

export interface SelectOption {
  value: string;
  label: string;
  disabled?: boolean;
  icon?: string;
}

export interface FormFieldProps {
  label: string;
  type?: 'text' | 'email' | 'password' | 'tel' | 'url' | 'number' | 'select' | 'textarea' | 'date' | 'time' | 'datetime-local';
  value: string | undefined;
  onChange: (value: string) => void;
  placeholder?: string;
  required?: boolean;
  disabled?: boolean;
  error?: string;
  helpText?: string;
  options?: SelectOption[];
  rows?: number;
  className?: string;
  icon?: React.ReactNode;
  showPasswordToggle?: boolean;
  floatingLabel?: boolean;
  size?: 'sm' | 'md' | 'lg';
}

export const FormField = forwardRef<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement, FormFieldProps>(
  ({ 
    label,
    type = 'text',
    value,
    onChange,
    placeholder,
    required = false,
    disabled = false,
    error,
    helpText,
    options = [],
    rows = 3,
    className = '',
    icon,
    showPasswordToggle = true,
    floatingLabel = false,
    size = 'md',
    ...props
  }, ref) => {
    const [showPassword, setShowPassword] = useState(false);
    const [isFocused, setIsFocused] = useState(false);
    
    // Enhanced styling with modern design
    const baseInputClasses = `
      block w-full 
      bg-theme-surface 
      text-theme-primary 
      placeholder-theme-tertiary
      border-2 border-theme-surface
      rounded-xl
      transition-all duration-300 ease-out
      focus:outline-none 
      focus:border-theme-interactive-primary 
      focus:bg-theme-background
      focus:shadow-[0_0_0_4px_rgba(var(--color-primary-rgb),0.1)]
      hover:border-theme-interactive-primary/30
      disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:border-theme-surface
    `;
    
    const errorClasses = error 
      ? 'border-theme-error focus:border-theme-error focus:shadow-[0_0_0_4px_rgba(var(--color-error-rgb),0.1)] hover:border-theme-error-hover' 
      : '';
    
    const sizeClasses = {
      sm: 'px-3 py-2 text-sm',
      md: 'px-4 py-3 text-base',
      lg: 'px-5 py-4 text-lg'
    };
    
    const iconPaddingClasses = icon ? (size === 'sm' ? 'pl-9' : size === 'lg' ? 'pl-12' : 'pl-10') : '';
    
    // eslint-disable-next-line security/detect-object-injection
    const selectedSizeClasses = sizeClasses[size] || sizeClasses.md;
    
    const inputClasses = `${baseInputClasses} ${selectedSizeClasses} ${iconPaddingClasses} ${errorClasses} ${className}`.replace(/\s+/g, ' ').trim();
    
    const actualType = type === 'password' && showPassword ? 'text' : type;

    const renderInput = () => {
      switch (type) {
        case 'select':
          return (
            <div className="relative">
              <select
                ref={ref as React.Ref<HTMLSelectElement>}
                value={value || ''}
                onChange={(e) => onChange(e.target.value)}
                disabled={disabled}
                onFocus={() => setIsFocused(true)}
                onBlur={() => setIsFocused(false)}
                className={`${inputClasses} appearance-none cursor-pointer pr-10`}
                {...props}
              >
                {!value && placeholder && (
                  <option value="" disabled>{placeholder}</option>
                )}
                {options.map((option) => (
                  <option key={option.value} value={option.value} disabled={option.disabled}>
                    {option.icon && `${option.icon} `}{option.label}
                  </option>
                ))}
              </select>
              {/* Custom dropdown arrow */}
              <div className="pointer-events-none absolute inset-y-0 right-0 flex items-center pr-3">
                <svg className="h-5 w-5 text-theme-tertiary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
                </svg>
              </div>
            </div>
          );
        
        case 'textarea':
          return (
            <textarea
              ref={ref as React.Ref<HTMLTextAreaElement>}
              value={value || ''}
              onChange={(e) => onChange(e.target.value)}
              placeholder={placeholder}
              disabled={disabled}
              rows={rows}
              onFocus={() => setIsFocused(true)}
              onBlur={() => setIsFocused(false)}
              className={`${inputClasses} resize-none`}
              {...props}
            />
          );
        
        case 'password':
          return (
            <div className="relative">
              <input
                ref={ref as React.Ref<HTMLInputElement>}
                type={actualType}
                value={value || ''}
                onChange={(e) => onChange(e.target.value)}
                placeholder={placeholder}
                disabled={disabled}
                onFocus={() => setIsFocused(true)}
                onBlur={() => setIsFocused(false)}
                className={`${inputClasses} pr-10`}
                {...props}
              />
              {showPasswordToggle && (
                <button
                  type="button"
                  onClick={() => setShowPassword(!showPassword)}
                  className="absolute inset-y-0 right-0 flex items-center pr-3 text-theme-tertiary hover:text-theme-primary transition-colors"
                >
                  {showPassword ? (
                    <svg className="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z" />
                    </svg>
                  ) : (
                    <svg className="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13.875 18.825A10.05 10.05 0 0112 19c-4.478 0-8.268-2.943-9.543-7a9.97 9.97 0 011.563-3.029m5.858.908a3 3 0 114.243 4.243M9.878 9.878l4.242 4.242M9.88 9.88l-3.29-3.29m7.532 7.532l3.29 3.29M3 3l3.59 3.59m0 0A9.953 9.953 0 0112 5c4.478 0 8.268 2.943 9.543 7a10.025 10.025 0 01-4.132 5.411m0 0L21 21" />
                    </svg>
                  )}
                </button>
              )}
            </div>
          );
        
        default:
          return (
            <input
              ref={ref as React.Ref<HTMLInputElement>}
              type={actualType}
              value={value || ''}
              onChange={(e) => onChange(e.target.value)}
              placeholder={placeholder}
              disabled={disabled}
              onFocus={() => setIsFocused(true)}
              onBlur={() => setIsFocused(false)}
              className={inputClasses}
              {...props}
            />
          );
      }
    };

    const labelClasses = floatingLabel
      ? `
        absolute left-4 
        transition-all duration-200 pointer-events-none
        ${(isFocused || value) 
          ? '-top-2 text-xs bg-theme-surface px-2 text-theme-interactive-primary font-semibold' 
          : 'top-3 text-base text-theme-tertiary'
        }
      `
      : 'block text-sm font-semibold text-theme-primary mb-2';

    return (
      <div className={`${floatingLabel ? 'relative' : 'space-y-2'}`}>
        {!floatingLabel && (
          <label className={labelClasses}>
            <span className="flex items-center gap-1">
              {label}
              {required && (
                <span className="text-theme-error animate-pulse">*</span>
              )}
            </span>
          </label>
        )}
        
        <div className="relative">
          {/* Icon */}
          {icon && (
            <div className={`
              absolute inset-y-0 left-0 flex items-center pointer-events-none
              ${size === 'sm' ? 'pl-3' : size === 'lg' ? 'pl-4' : 'pl-3.5'}
              text-theme-tertiary
              ${isFocused ? 'text-theme-interactive-primary' : ''}
              transition-colors duration-200
            `}>
              {icon}
            </div>
          )}
          
          {renderInput()}
          
          {floatingLabel && (
            <label className={labelClasses}>
              {label}
              {required && <span className="text-theme-error ml-0.5">*</span>}
            </label>
          )}
        </div>
        
        {/* Error message with animation */}
        {error && (
          <p className="text-sm text-theme-error flex items-center gap-1 mt-1 animate-in slide-in-from-top-1 duration-200">
            <svg className="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            {error}
          </p>
        )}
        
        {/* Help text with subtle styling */}
        {helpText && !error && (
          <p className="text-sm text-theme-secondary mt-1 flex items-center gap-1">
            <svg className="h-4 w-4 opacity-60" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            {helpText}
          </p>
        )}
      </div>
    );
  }
);

FormField.displayName = 'FormField';

export default FormField;