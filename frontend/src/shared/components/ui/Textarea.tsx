import React from 'react';

export interface TextareaProps extends React.TextareaHTMLAttributes<HTMLTextAreaElement> {
  label?: string;
  error?: string;
  description?: string;
  fullWidth?: boolean;
}

export const Textarea: React.FC<TextareaProps> = ({
  label,
  error,
  description,
  fullWidth = true,
  className = '',
  ...props
}) => {
  const textareaId = props.id || `textarea-${Math.random().toString(36).substr(2, 9)}`;
  const baseClassName = `
    px-3 py-2 border border-theme rounded-md
    bg-theme-surface text-theme-primary
    placeholder-theme-tertiary
    focus:outline-none focus:ring-2 focus:ring-theme-primary focus:border-transparent
    resize-vertical min-h-[80px]
    ${fullWidth ? 'w-full' : ''}
    ${error ? 'border-theme-error focus:ring-theme-error' : 'border-theme'}
    ${className}
  `.replace(/\s+/g, ' ').trim();

  return (
    <div className={fullWidth ? 'w-full' : ''}>
      {label && (
        <label
          htmlFor={textareaId}
          className="block text-sm font-medium text-theme-primary mb-1"
        >
          {label}
        </label>
      )}
      <textarea
        id={textareaId}
        className={baseClassName}
        aria-describedby={error ? `${textareaId}-error` : description ? `${textareaId}-description` : undefined}
        {...props}
      />
      {description && !error && (
        <p id={`${textareaId}-description`} className="mt-1 text-xs text-theme-muted">
          {description}
        </p>
      )}
      {error && (
        <p id={`${textareaId}-error`} className="mt-1 text-sm text-theme-error" role="alert">{error}</p>
      )}
    </div>
  );
};