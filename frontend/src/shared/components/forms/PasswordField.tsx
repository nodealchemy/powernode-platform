/**
 * Password input field with visibility toggle and strength indicator
 */

import { EyeIcon, EyeSlashIcon, LockClosedIcon } from '@heroicons/react/24/outline';
import React, { useMemo,useState } from 'react';

interface PasswordFieldProps {
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
  showStrengthIndicator?: boolean;
  minLength?: number;
}

interface PasswordStrength {
  score: number;
  label: string;
  color: string;
}

export const PasswordField: React.FC<PasswordFieldProps> = ({
  name,
  label = 'Password',
  placeholder = 'Enter your password',
  required = false,
  value,
  error,
  touched,
  onChange,
  onBlur,
  disabled = false,
  className = '',
  autoComplete = 'current-password',
  showStrengthIndicator = false,
  minLength = 8
}) => {
  const [showPassword, setShowPassword] = useState(false);
  const hasError = touched && error;

  const passwordStrength = useMemo((): PasswordStrength | null => {
    if (!showStrengthIndicator || !value) return null;

    let score = 0;
    const checks = [
      { test: value.length >= minLength, weight: 1 },
      { test: value.length >= 12, weight: 1 },
      { test: /[A-Z]/.test(value), weight: 1 },
      { test: /[a-z]/.test(value), weight: 1 },
      { test: /[0-9]/.test(value), weight: 1 },
      { test: /[^A-Za-z0-9]/.test(value), weight: 1 }
    ];

    checks.forEach(check => {
      if (check.test) score += check.weight;
    });

    const strengthLevels: PasswordStrength[] = [
      { score: 0, label: 'Very Weak', color: 'bg-theme-error' },
      { score: 1, label: 'Weak', color: 'bg-theme-error' },
      { score: 2, label: 'Fair', color: 'bg-theme-warning' },
      { score: 3, label: 'Good', color: 'bg-theme-info' },
      { score: 4, label: 'Strong', color: 'bg-theme-success' },
      { score: 5, label: 'Very Strong', color: 'bg-theme-success' }
    ];

    return strengthLevels[Math.min(score, strengthLevels.length - 1)];
  }, [value, showStrengthIndicator, minLength]);

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
          <LockClosedIcon className="h-5 w-5 text-theme-secondary" />
        </div>
        
        <input
          id={name}
          name={name}
          type={showPassword ? 'text' : 'password'}
          value={value}
          onChange={(e) => void onChange(e)}
          onBlur={onBlur}
          disabled={disabled}
          placeholder={placeholder}
          autoComplete={autoComplete}
          aria-invalid={hasError ? "true" : "false"}
          aria-describedby={hasError ? `${name}-error` : undefined}
          className={`
            w-full pl-10 pr-10 py-2 
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
        
        <button
          type="button"
          onClick={() => setShowPassword(!showPassword)}
          disabled={disabled}
          className="absolute inset-y-0 right-0 pr-3 flex items-center text-theme-secondary hover:text-theme-primary transition-colors"
          tabIndex={-1}
          aria-label={showPassword ? 'Hide password' : 'Show password'}
        >
          {showPassword ? (
            <EyeSlashIcon className="h-5 w-5" />
          ) : (
            <EyeIcon className="h-5 w-5" />
          )}
        </button>
      </div>
      
      {showStrengthIndicator && value && passwordStrength && (
        <div className="mt-2">
          <div className="flex items-center gap-2">
            <div className="flex-1 bg-theme-background-tertiary rounded-full h-1.5">
              <div 
                className={`h-1.5 rounded-full transition-all duration-300 ${passwordStrength.color}`}
                style={{ width: `${(passwordStrength.score / 5) * 100}%` }}
              />
            </div>
            <span className="text-xs text-theme-secondary">
              {passwordStrength.label}
            </span>
          </div>
        </div>
      )}
      
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