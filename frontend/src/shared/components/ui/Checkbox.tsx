import React from 'react';

export interface CheckboxProps extends Omit<React.InputHTMLAttributes<HTMLInputElement>, 'onChange'> {
  label?: string;
  error?: string;
  description?: string;
  id?: string;
  onCheckedChange?: (checked: boolean) => void;
  indeterminate?: boolean;
}

export const Checkbox: React.FC<CheckboxProps> = ({
  label,
  error,
  description,
  className = '',
  id,
  onCheckedChange,
  indeterminate,
  checked,
  ...props
}) => {
  const checkboxRef = React.useRef<HTMLInputElement>(null);
  const checkboxId = id || `checkbox-${Math.random().toString(36).substr(2, 9)}`;
  
  // Handle indeterminate state
  React.useEffect(() => {
    if (checkboxRef.current) {
      checkboxRef.current.indeterminate = !!indeterminate;
    }
  }, [indeterminate]);

  const checkboxClassName = `
    h-4 w-4 rounded border-theme 
    text-theme-primary focus:ring-theme-primary focus:ring-2 focus:ring-offset-0
    bg-theme-surface 
    disabled:bg-theme-background disabled:text-theme-secondary
    ${error ? 'border-theme-error focus:ring-theme-error' : ''}
    ${className}
  `.trim();

  const handleChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    if (onCheckedChange) {
      onCheckedChange(event.target.checked);
    }
  };

  return (
    <div className="flex items-start gap-3">
      <input
        ref={checkboxRef}
        type="checkbox"
        id={checkboxId}
        className={checkboxClassName}
        aria-describedby={error ? `${checkboxId}-error` : description ? `${checkboxId}-description` : undefined}
        checked={checked}
        onChange={handleChange}
        {...props}
      />
      {(label || description) && (
        <div className="flex-1">
          {label && (
            <label 
              htmlFor={checkboxId}
              className="text-sm font-medium text-theme-primary cursor-pointer"
            >
              {label}
            </label>
          )}
          {description && (
            <p id={`${checkboxId}-description`} className="text-sm text-theme-muted">
              {description}
            </p>
          )}
          {error && (
            <p id={`${checkboxId}-error`} className="mt-1 text-sm text-theme-error" role="alert">
              {error}
            </p>
          )}
        </div>
      )}
    </div>
  );
};