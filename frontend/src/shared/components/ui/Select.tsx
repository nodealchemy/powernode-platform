import React from 'react';

export interface SelectOption {
  value: string;
  label: string;
  disabled?: boolean;
}

export interface SelectProps extends Omit<React.SelectHTMLAttributes<HTMLSelectElement>, 'onChange'> {
  label?: string;
  error?: string;
  fullWidth?: boolean;
  options?: SelectOption[];
  onChange?: (value: string) => void;
  onValueChange?: (value: string) => void;
}

export const Select: React.FC<SelectProps> = ({
  label,
  error,
  fullWidth = true,
  className = '',
  children,
  options,
  onChange,
  onValueChange,
  value,
  ...props
}) => {
  const handleChange = (event: React.ChangeEvent<HTMLSelectElement>) => {
    const newValue = event.target.value;
    if (onChange) {
      onChange(newValue);
    }
    if (onValueChange) {
      onValueChange(newValue);
    }
  };

  const baseClassName = `
    px-3 py-2 border border-theme rounded-md 
    bg-theme-surface text-theme-primary 
    focus:outline-none focus:ring-2 focus:ring-theme-primary focus:border-transparent
    disabled:bg-theme-background disabled:text-theme-secondary
    ${fullWidth ? 'w-full' : ''}
    ${error ? 'border-theme-error focus:ring-theme-error' : ''}
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
        value={value}
        onChange={handleChange}
        {...props}
      >
        {options ? (
          options.map((option) => (
            <option
              key={option.value}
              value={option.value}
              disabled={option.disabled}
            >
              {option.label}
            </option>
          ))
        ) : (
          children
        )}
      </select>
      {error && (
        <p className="mt-1 text-sm text-theme-error">
          {error}
        </p>
      )}
    </div>
  );
};