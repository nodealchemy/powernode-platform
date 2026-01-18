---
Last Updated: 2026-01-17
Platform Version: 1.0.0
---

# UI Component Developer Specialist Guide

## Related References

For common patterns used across multiple specialists, see these consolidated references:
- **[Theme System Reference](../platform/THEME_SYSTEM_REFERENCE.md)** - Theme-aware styling classes and patterns
- **[Permission System Reference](../platform/PERMISSION_SYSTEM_REFERENCE.md)** - Permission-based UI control

## Role & Responsibilities

The UI Component Developer specializes in building reusable React components, implementing responsive design, and creating accessible interfaces for Powernode's subscription platform.

### Core Responsibilities
- Building reusable React components
- Implementing responsive design
- Creating form components with validation
- Handling user interactions and events
- Implementing accessibility features

### Key Focus Areas
- Component reusability and composition
- WCAG AA compliance and accessibility
- Responsive design and mobile optimization
- Theme-aware styling with Tailwind CSS
- Form handling and validation patterns

## UI Component Standards

### 1. Design System Architecture (MANDATORY)

#### Component Library Structure
```
src/shared/components/
├── ui/                     # Primitive UI components
│   ├── Button.tsx
│   ├── Input.tsx
│   ├── Modal.tsx
│   ├── Card.tsx
│   ├── Badge.tsx
│   └── index.ts
├── forms/                  # Form-specific components
│   ├── FormField.tsx
│   ├── SelectField.tsx
│   ├── CheckboxField.tsx
│   └── index.ts
├── layout/                 # Layout components
│   ├── PageContainer.tsx   # MANDATORY: Standard page wrapper
│   ├── Header.tsx
│   ├── Sidebar.tsx
│   ├── TabContainer.tsx
│   └── index.ts
├── data-display/          # Data visualization
│   ├── Table.tsx
│   ├── DataGrid.tsx
│   ├── Chart.tsx
│   └── index.ts
└── navigation/            # Navigation components
    ├── NavigationItem.tsx
    ├── Breadcrumb.tsx
    └── index.ts
```

#### Theme-Aware Component Base
```tsx
// src/shared/components/ui/Button.tsx
import React, { forwardRef } from 'react';
import { cn } from '@/shared/utils/cn';
import { Slot } from '@radix-ui/react-slot';

export interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'primary' | 'secondary' | 'danger' | 'ghost' | 'link';
  size?: 'sm' | 'md' | 'lg' | 'xl';
  loading?: boolean;
  asChild?: boolean;
  icon?: React.ReactNode;
  iconPosition?: 'left' | 'right';
}

const buttonVariants = {
  variant: {
    primary: 'bg-theme-interactive-primary text-white hover:bg-theme-interactive-primary/90 focus:ring-theme-interactive-primary/20',
    secondary: 'bg-theme-surface text-theme-primary border border-theme hover:bg-theme-background',
    danger: 'bg-theme-error text-white hover:bg-theme-error/90 focus:ring-theme-error/20',
    ghost: 'text-theme-primary hover:bg-theme-background',
    link: 'text-theme-link hover:text-theme-link/80 underline-offset-4 hover:underline'
  },
  size: {
    sm: 'h-8 px-3 text-sm',
    md: 'h-9 px-4 text-sm',
    lg: 'h-10 px-6 text-base',
    xl: 'h-11 px-8 text-base'
  }
};

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(({
  className,
  variant = 'primary',
  size = 'md',
  loading = false,
  disabled,
  asChild = false,
  icon,
  iconPosition = 'left',
  children,
  ...props
}, ref) => {
  const Comp = asChild ? Slot : 'button';
  
  const isDisabled = disabled || loading;
  
  return (
    <Comp
      className={cn(
        // Base styles
        'inline-flex items-center justify-center rounded-md font-medium transition-colors',
        'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-offset-2',
        'disabled:pointer-events-none disabled:opacity-50',
        // Variant styles
        buttonVariants.variant[variant],
        buttonVariants.size[size],
        className
      )}
      ref={ref}
      disabled={isDisabled}
      {...props}
    >
      {loading && (
        <svg 
          className="mr-2 h-4 w-4 animate-spin" 
          xmlns="http://www.w3.org/2000/svg" 
          fill="none" 
          viewBox="0 0 24 24"
        >
          <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"/>
          <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"/>
        </svg>
      )}
      
      {icon && iconPosition === 'left' && !loading && (
        <span className="mr-2 h-4 w-4">{icon}</span>
      )}
      
      {children}
      
      {icon && iconPosition === 'right' && !loading && (
        <span className="ml-2 h-4 w-4">{icon}</span>
      )}
    </Comp>
  );
});

Button.displayName = 'Button';
```

#### Input Component with Validation
```tsx
// src/shared/components/ui/Input.tsx
import React, { forwardRef, useState } from 'react';
import { cn } from '@/shared/utils/cn';
import { EyeIcon, EyeSlashIcon } from '@heroicons/react/24/outline';

export interface InputProps extends React.InputHTMLAttributes<HTMLInputElement> {
  label?: string;
  error?: string;
  description?: string;
  leftIcon?: React.ReactNode;
  rightIcon?: React.ReactNode;
  variant?: 'default' | 'ghost';
  inputSize?: 'sm' | 'md' | 'lg';
}

const inputVariants = {
  variant: {
    default: 'border border-theme bg-theme-surface',
    ghost: 'border-0 bg-transparent'
  },
  size: {
    sm: 'h-8 px-3 text-sm',
    md: 'h-9 px-3 text-sm',
    lg: 'h-10 px-4 text-base'
  }
};

export const Input = forwardRef<HTMLInputElement, InputProps>(({
  className,
  label,
  error,
  description,
  leftIcon,
  rightIcon,
  variant = 'default',
  inputSize = 'md',
  type = 'text',
  id,
  ...props
}, ref) => {
  const [showPassword, setShowPassword] = useState(false);
  const [focused, setFocused] = useState(false);
  
  const inputId = id || `input-${Math.random().toString(36).substr(2, 9)}`;
  const isPassword = type === 'password';
  const actualType = isPassword && showPassword ? 'text' : type;
  
  const hasError = Boolean(error);
  const hasLeftIcon = Boolean(leftIcon);
  const hasRightIcon = Boolean(rightIcon) || isPassword;

  return (
    <div className="w-full">
      {label && (
        <label 
          htmlFor={inputId}
          className="block text-sm font-medium text-theme-primary mb-1.5"
        >
          {label}
          {props.required && <span className="text-theme-error ml-1">*</span>}
        </label>
      )}
      
      <div className="relative">
        {hasLeftIcon && (
          <div className="absolute left-3 top-1/2 transform -translate-y-1/2 text-theme-secondary">
            {leftIcon}
          </div>
        )}
        
        <input
          ref={ref}
          type={actualType}
          id={inputId}
          className={cn(
            // Base styles
            'w-full rounded-md text-theme-primary placeholder:text-theme-tertiary',
            'transition-colors duration-200',
            'focus:outline-none focus:ring-2 focus:ring-theme-link focus:ring-offset-0',
            'disabled:cursor-not-allowed disabled:opacity-50',
            // Variant styles
            inputVariants.variant[variant],
            inputVariants.size[inputSize],
            // Icon padding
            hasLeftIcon && 'pl-9',
            hasRightIcon && 'pr-9',
            // Error styles
            hasError && 'border-theme-error focus:ring-theme-error',
            // Focus styles
            focused && !hasError && 'border-theme-link',
            className
          )}
          onFocus={(e) => {
            setFocused(true);
            props.onFocus?.(e);
          }}
          onBlur={(e) => {
            setFocused(false);
            props.onBlur?.(e);
          }}
          {...props}
        />
        
        {isPassword && (
          <button
            type="button"
            className="absolute right-3 top-1/2 transform -translate-y-1/2 text-theme-secondary hover:text-theme-primary"
            onClick={() => setShowPassword(!showPassword)}
            tabIndex={-1}
          >
            {showPassword ? (
              <EyeSlashIcon className="h-4 w-4" />
            ) : (
              <EyeIcon className="h-4 w-4" />
            )}
          </button>
        )}
        
        {rightIcon && !isPassword && (
          <div className="absolute right-3 top-1/2 transform -translate-y-1/2 text-theme-secondary">
            {rightIcon}
          </div>
        )}
      </div>
      
      {error && (
        <p className="mt-1.5 text-sm text-theme-error" role="alert">
          {error}
        </p>
      )}
      
      {description && !error && (
        <p className="mt-1.5 text-sm text-theme-secondary">
          {description}
        </p>
      )}
    </div>
  );
});

Input.displayName = 'Input';
```

### 2. Modal and Dialog Components (MANDATORY)

#### Accessible Modal Component
```tsx
// src/shared/components/ui/Modal.tsx
import React, { useEffect, useRef } from 'react';
import { createPortal } from 'react-dom';
import { cn } from '@/shared/utils/cn';
import { XMarkIcon } from '@heroicons/react/24/outline';

export interface ModalProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  title?: string;
  description?: string;
  children: React.ReactNode;
  size?: 'sm' | 'md' | 'lg' | 'xl' | 'full';
  closeOnOverlayClick?: boolean;
  closeOnEscape?: boolean;
  showCloseButton?: boolean;
  className?: string;
}

const modalSizes = {
  sm: 'max-w-sm',
  md: 'max-w-md',
  lg: 'max-w-lg',
  xl: 'max-w-2xl',
  full: 'max-w-7xl'
};

export const Modal: React.FC<ModalProps> = ({
  open,
  onOpenChange,
  title,
  description,
  children,
  size = 'md',
  closeOnOverlayClick = true,
  closeOnEscape = true,
  showCloseButton = true,
  className
}) => {
  const overlayRef = useRef<HTMLDivElement>(null);
  const modalRef = useRef<HTMLDivElement>(null);
  const previousFocusRef = useRef<HTMLElement | null>(null);

  // Handle escape key
  useEffect(() => {
    if (!open || !closeOnEscape) return;

    const handleEscape = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        onOpenChange(false);
      }
    };

    document.addEventListener('keydown', handleEscape);
    return () => document.removeEventListener('keydown', handleEscape);
  }, [open, closeOnEscape, onOpenChange]);

  // Focus management
  useEffect(() => {
    if (!open) return;

    // Store previous focus
    previousFocusRef.current = document.activeElement as HTMLElement;

    // Focus modal
    const focusableElements = modalRef.current?.querySelectorAll(
      'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
    );

    if (focusableElements && focusableElements.length > 0) {
      (focusableElements[0] as HTMLElement).focus();
    } else {
      modalRef.current?.focus();
    }

    // Restore focus on close
    return () => {
      if (previousFocusRef.current) {
        previousFocusRef.current.focus();
      }
    };
  }, [open]);

  // Trap focus within modal
  useEffect(() => {
    if (!open) return;

    const handleTabKey = (e: KeyboardEvent) => {
      if (e.key !== 'Tab') return;

      const focusableElements = modalRef.current?.querySelectorAll(
        'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
      ) as NodeListOf<HTMLElement>;

      if (!focusableElements || focusableElements.length === 0) return;

      const firstElement = focusableElements[0];
      const lastElement = focusableElements[focusableElements.length - 1];

      if (e.shiftKey) {
        if (document.activeElement === firstElement) {
          e.preventDefault();
          lastElement.focus();
        }
      } else {
        if (document.activeElement === lastElement) {
          e.preventDefault();
          firstElement.focus();
        }
      }
    };

    document.addEventListener('keydown', handleTabKey);
    return () => document.removeEventListener('keydown', handleTabKey);
  }, [open]);

  // Prevent body scroll
  useEffect(() => {
    if (open) {
      document.body.style.overflow = 'hidden';
    } else {
      document.body.style.overflow = '';
    }

    return () => {
      document.body.style.overflow = '';
    };
  }, [open]);

  if (!open) return null;

  const handleOverlayClick = (e: React.MouseEvent) => {
    if (closeOnOverlayClick && e.target === overlayRef.current) {
      onOpenChange(false);
    }
  };

  return createPortal(
    <div
      ref={overlayRef}
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50"
      onClick={handleOverlayClick}
      role="dialog"
      aria-modal="true"
      aria-labelledby={title ? 'modal-title' : undefined}
      aria-describedby={description ? 'modal-description' : undefined}
    >
      <div
        ref={modalRef}
        className={cn(
          'relative w-full bg-theme-surface rounded-lg shadow-xl',
          'transform transition-all duration-200 ease-out',
          modalSizes[size],
          className
        )}
        tabIndex={-1}
      >
        {/* Header */}
        {(title || showCloseButton) && (
          <div className="flex items-center justify-between p-6 border-b border-theme">
            <div>
              {title && (
                <h2 id="modal-title" className="text-lg font-semibold text-theme-primary">
                  {title}
                </h2>
              )}
              {description && (
                <p id="modal-description" className="mt-1 text-sm text-theme-secondary">
                  {description}
                </p>
              )}
            </div>
            
            {showCloseButton && (
              <button
                onClick={() => onOpenChange(false)}
                className="p-2 text-theme-secondary hover:text-theme-primary hover:bg-theme-background rounded-md transition-colors"
                aria-label="Close modal"
              >
                <XMarkIcon className="h-5 w-5" />
              </button>
            )}
          </div>
        )}

        {/* Content */}
        <div className="p-6">
          {children}
        </div>
      </div>
    </div>,
    document.body
  );
};

// Modal trigger hook for state management
export const useModal = (defaultOpen = false) => {
  const [open, setOpen] = React.useState(defaultOpen);

  const openModal = React.useCallback(() => setOpen(true), []);
  const closeModal = React.useCallback(() => setOpen(false), []);
  const toggleModal = React.useCallback(() => setOpen(prev => !prev), []);

  return {
    open,
    openModal,
    closeModal,
    toggleModal,
    setOpen
  };
};
```

### 3. Form Components (MANDATORY)

#### Form Field Wrapper
```tsx
// src/shared/components/forms/FormField.tsx
import React from 'react';
import { cn } from '@/shared/utils/cn';
import { Input, InputProps } from '@/shared/components/ui/Input';
import { Select, SelectProps } from '@/shared/components/ui/Select';
import { Textarea, TextareaProps } from '@/shared/components/ui/Textarea';
import { Checkbox, CheckboxProps } from '@/shared/components/ui/Checkbox';

type BaseProps = {
  name: string;
  label?: string;
  error?: string;
  description?: string;
  required?: boolean;
  className?: string;
};

type FormFieldProps = BaseProps & (
  | ({ type: 'input' } & Omit<InputProps, 'name' | 'label' | 'error' | 'required'>)
  | ({ type: 'select' } & Omit<SelectProps, 'name' | 'label' | 'error' | 'required'>)
  | ({ type: 'textarea' } & Omit<TextareaProps, 'name' | 'label' | 'error' | 'required'>)
  | ({ type: 'checkbox' } & Omit<CheckboxProps, 'name' | 'label' | 'error' | 'required'>)
);

export const FormField: React.FC<FormFieldProps> = ({
  type,
  name,
  label,
  error,
  description,
  required,
  className,
  ...props
}) => {
  const fieldId = `field-${name}`;

  const renderField = () => {
    const commonProps = {
      id: fieldId,
      name,
      required,
      'aria-invalid': Boolean(error),
      'aria-describedby': description ? `${fieldId}-description` : undefined
    };

    switch (type) {
      case 'input':
        return (
          <Input 
            {...commonProps}
            label={label}
            error={error}
            description={description}
            {...(props as InputProps)}
          />
        );
        
      case 'select':
        return (
          <Select 
            {...commonProps}
            label={label}
            error={error}
            description={description}
            {...(props as SelectProps)}
          />
        );
        
      case 'textarea':
        return (
          <Textarea 
            {...commonProps}
            label={label}
            error={error}
            description={description}
            {...(props as TextareaProps)}
          />
        );
        
      case 'checkbox':
        return (
          <Checkbox 
            {...commonProps}
            label={label}
            error={error}
            description={description}
            {...(props as CheckboxProps)}
          />
        );
        
      default:
        return null;
    }
  };

  return (
    <div className={cn('space-y-1', className)}>
      {renderField()}
    </div>
  );
};

// Form validation hook
export const useFormValidation = <T extends Record<string, any>>(
  schema: Record<keyof T, (value: any) => string | null>
) => {
  const validate = (values: T): Record<keyof T, string> => {
    const errors = {} as Record<keyof T, string>;
    
    Object.keys(schema).forEach(key => {
      const fieldKey = key as keyof T;
      const validator = schema[fieldKey];
      const error = validator(values[fieldKey]);
      
      if (error) {
        errors[fieldKey] = error;
      }
    });
    
    return errors;
  };

  return { validate };
};

// Common validation functions
export const validators = {
  required: (value: any) => {
    if (!value || (typeof value === 'string' && !value.trim())) {
      return 'This field is required';
    }
    return null;
  },
  
  email: (value: string) => {
    if (!value) return null;
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailRegex.test(value) ? null : 'Please enter a valid email address';
  },
  
  minLength: (min: number) => (value: string) => {
    if (!value) return null;
    return value.length >= min ? null : `Must be at least ${min} characters`;
  },
  
  maxLength: (max: number) => (value: string) => {
    if (!value) return null;
    return value.length <= max ? null : `Must be no more than ${max} characters`;
  },
  
  password: (value: string) => {
    if (!value) return null;
    
    const checks = [
      { test: /.{12,}/, message: 'At least 12 characters' },
      { test: /[a-z]/, message: 'One lowercase letter' },
      { test: /[A-Z]/, message: 'One uppercase letter' },
      { test: /\d/, message: 'One number' },
      { test: /[!@#$%^&*(),.?":{}|<>]/, message: 'One special character' }
    ];
    
    for (const check of checks) {
      if (!check.test.test(value)) {
        return `Password must contain ${check.message}`;
      }
    }
    
    return null;
  }
};
```

### 4. Data Display Components (MANDATORY)

#### Table Component with Sorting and Pagination
```tsx
// src/shared/components/data-display/Table.tsx
import React, { useState } from 'react';
import { cn } from '@/shared/utils/cn';
import { ChevronUpIcon, ChevronDownIcon } from '@heroicons/react/24/outline';

export interface Column<T> {
  key: keyof T;
  header: string;
  sortable?: boolean;
  width?: string;
  render?: (value: T[keyof T], row: T) => React.ReactNode;
}

export interface TableProps<T> {
  data: T[];
  columns: Column<T>[];
  loading?: boolean;
  emptyMessage?: string;
  onSort?: (column: keyof T, direction: 'asc' | 'desc') => void;
  sortColumn?: keyof T;
  sortDirection?: 'asc' | 'desc';
  onRowClick?: (row: T) => void;
  className?: string;
}

export function Table<T extends { id: string }>({
  data,
  columns,
  loading = false,
  emptyMessage = 'No data available',
  onSort,
  sortColumn,
  sortDirection,
  onRowClick,
  className
}: TableProps<T>) {
  const [hoveredRow, setHoveredRow] = useState<string | null>(null);

  const handleSort = (column: Column<T>) => {
    if (!column.sortable || !onSort) return;
    
    const newDirection = sortColumn === column.key && sortDirection === 'asc' ? 'desc' : 'asc';
    onSort(column.key, newDirection);
  };

  const getSortIcon = (column: Column<T>) => {
    if (!column.sortable) return null;
    
    const isActive = sortColumn === column.key;
    
    if (!isActive) {
      return (
        <div className="flex flex-col opacity-30">
          <ChevronUpIcon className="h-3 w-3" />
          <ChevronDownIcon className="h-3 w-3 -mt-1" />
        </div>
      );
    }
    
    return sortDirection === 'asc' ? (
      <ChevronUpIcon className="h-4 w-4" />
    ) : (
      <ChevronDownIcon className="h-4 w-4" />
    );
  };

  if (loading) {
    return (
      <div className="animate-pulse">
        <div className="h-12 bg-theme-background rounded mb-4" />
        {[...Array(5)].map((_, i) => (
          <div key={i} className="h-16 bg-theme-background rounded mb-2" />
        ))}
      </div>
    );
  }

  return (
    <div className={cn('overflow-hidden rounded-lg border border-theme', className)}>
      <div className="overflow-x-auto">
        <table className="w-full divide-y divide-theme">
          <thead className="bg-theme-background">
            <tr>
              {columns.map((column) => (
                <th
                  key={String(column.key)}
                  scope="col"
                  className={cn(
                    'px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider',
                    column.sortable && 'cursor-pointer select-none hover:bg-theme-surface',
                    column.width && `w-${column.width}`
                  )}
                  onClick={() => handleSort(column)}
                >
                  <div className="flex items-center space-x-1">
                    <span>{column.header}</span>
                    {getSortIcon(column)}
                  </div>
                </th>
              ))}
            </tr>
          </thead>
          
          <tbody className="bg-theme-surface divide-y divide-theme">
            {data.length === 0 ? (
              <tr>
                <td 
                  colSpan={columns.length} 
                  className="px-6 py-12 text-center text-theme-secondary"
                >
                  {emptyMessage}
                </td>
              </tr>
            ) : (
              data.map((row) => (
                <tr
                  key={row.id}
                  className={cn(
                    'transition-colors duration-150',
                    onRowClick && 'cursor-pointer hover:bg-theme-background',
                    hoveredRow === row.id && 'bg-theme-background'
                  )}
                  onClick={() => onRowClick?.(row)}
                  onMouseEnter={() => setHoveredRow(row.id)}
                  onMouseLeave={() => setHoveredRow(null)}
                >
                  {columns.map((column) => (
                    <td
                      key={String(column.key)}
                      className="px-6 py-4 whitespace-nowrap text-sm text-theme-primary"
                    >
                      {column.render
                        ? column.render(row[column.key], row)
                        : String(row[column.key])
                      }
                    </td>
                  ))}
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

// Pagination component for tables
export interface PaginationProps {
  currentPage: number;
  totalPages: number;
  totalItems: number;
  itemsPerPage: number;
  onPageChange: (page: number) => void;
  onItemsPerPageChange: (itemsPerPage: number) => void;
}

export const Pagination: React.FC<PaginationProps> = ({
  currentPage,
  totalPages,
  totalItems,
  itemsPerPage,
  onPageChange,
  onItemsPerPageChange
}) => {
  const startItem = (currentPage - 1) * itemsPerPage + 1;
  const endItem = Math.min(currentPage * itemsPerPage, totalItems);

  const getPageNumbers = () => {
    const pages: (number | string)[] = [];
    const showPages = 5; // Show up to 5 page numbers
    
    if (totalPages <= showPages) {
      return Array.from({ length: totalPages }, (_, i) => i + 1);
    }
    
    const start = Math.max(1, currentPage - 2);
    const end = Math.min(totalPages, currentPage + 2);
    
    if (start > 1) {
      pages.push(1);
      if (start > 2) pages.push('...');
    }
    
    for (let i = start; i <= end; i++) {
      pages.push(i);
    }
    
    if (end < totalPages) {
      if (end < totalPages - 1) pages.push('...');
      pages.push(totalPages);
    }
    
    return pages;
  };

  return (
    <div className="flex items-center justify-between px-6 py-4 border-t border-theme bg-theme-surface">
      <div className="flex items-center space-x-2 text-sm text-theme-secondary">
        <span>Show</span>
        <select
          value={itemsPerPage}
          onChange={(e) => onItemsPerPageChange(Number(e.target.value))}
          className="border border-theme rounded px-2 py-1 bg-theme-surface text-theme-primary"
        >
          <option value={10}>10</option>
          <option value={20}>20</option>
          <option value={50}>50</option>
          <option value={100}>100</option>
        </select>
        <span>of {totalItems} results</span>
      </div>
      
      <div className="flex items-center space-x-2 text-sm">
        <span className="text-theme-secondary">
          {startItem}-{endItem} of {totalItems}
        </span>
        
        <div className="flex space-x-1">
          <button
            onClick={() => onPageChange(currentPage - 1)}
            disabled={currentPage <= 1}
            className="px-3 py-1 border border-theme rounded disabled:opacity-50 disabled:cursor-not-allowed hover:bg-theme-background"
          >
            Previous
          </button>
          
          {getPageNumbers().map((page, index) => (
            <React.Fragment key={index}>
              {page === '...' ? (
                <span className="px-3 py-1">...</span>
              ) : (
                <button
                  onClick={() => onPageChange(page as number)}
                  className={cn(
                    'px-3 py-1 border rounded',
                    currentPage === page
                      ? 'bg-theme-interactive-primary text-white border-theme-interactive-primary'
                      : 'border-theme hover:bg-theme-background'
                  )}
                >
                  {page}
                </button>
              )}
            </React.Fragment>
          ))}
          
          <button
            onClick={() => onPageChange(currentPage + 1)}
            disabled={currentPage >= totalPages}
            className="px-3 py-1 border border-theme rounded disabled:opacity-50 disabled:cursor-not-allowed hover:bg-theme-background"
          >
            Next
          </button>
        </div>
      </div>
    </div>
  );
};
```

### 5. Responsive Design Standards (MANDATORY)

#### Mobile-First Utility Classes
```tsx
// src/shared/utils/responsive.ts
export const responsiveClasses = {
  // Layout containers
  container: 'container mx-auto px-4 sm:px-6 lg:px-8',
  
  // Grid systems
  grid: {
    cols1: 'grid grid-cols-1',
    cols2: 'grid grid-cols-1 md:grid-cols-2',
    cols3: 'grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3',
    cols4: 'grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4',
    autoFit: 'grid grid-cols-[repeat(auto-fit,minmax(250px,1fr))]'
  },
  
  // Spacing
  spacing: {
    section: 'py-12 sm:py-16 lg:py-20',
    content: 'space-y-8 sm:space-y-12 lg:space-y-16',
    items: 'space-y-4 sm:space-y-6',
    gap: 'gap-4 sm:gap-6 lg:gap-8'
  },
  
  // Typography
  text: {
    h1: 'text-2xl sm:text-3xl lg:text-4xl xl:text-5xl font-bold',
    h2: 'text-xl sm:text-2xl lg:text-3xl font-semibold',
    h3: 'text-lg sm:text-xl lg:text-2xl font-medium',
    body: 'text-sm sm:text-base',
    small: 'text-xs sm:text-sm'
  },
  
  // Flex layouts
  flex: {
    center: 'flex items-center justify-center',
    between: 'flex items-center justify-between',
    start: 'flex items-center justify-start',
    column: 'flex flex-col',
    columnCenter: 'flex flex-col items-center justify-center',
    wrap: 'flex flex-wrap',
    stack: 'flex flex-col sm:flex-row sm:items-center'
  }
};

// Responsive breakpoint hook
export const useBreakpoint = () => {
  const [breakpoint, setBreakpoint] = useState<'sm' | 'md' | 'lg' | 'xl' | '2xl'>('sm');
  
  useEffect(() => {
    const updateBreakpoint = () => {
      const width = window.innerWidth;
      
      if (width >= 1536) setBreakpoint('2xl');
      else if (width >= 1280) setBreakpoint('xl');
      else if (width >= 1024) setBreakpoint('lg');
      else if (width >= 768) setBreakpoint('md');
      else setBreakpoint('sm');
    };
    
    updateBreakpoint();
    window.addEventListener('resize', updateBreakpoint);
    
    return () => window.removeEventListener('resize', updateBreakpoint);
  }, []);
  
  return {
    breakpoint,
    isMobile: breakpoint === 'sm',
    isTablet: breakpoint === 'md',
    isDesktop: ['lg', 'xl', '2xl'].includes(breakpoint)
  };
};
```

#### Responsive Component Examples
```tsx
// Example responsive card component
export const ResponsiveCard: React.FC<{
  title: string;
  children: React.ReactNode;
  actions?: React.ReactNode;
}> = ({ title, children, actions }) => {
  const { isMobile } = useBreakpoint();
  
  return (
    <div className={cn(
      'bg-theme-surface rounded-lg border border-theme overflow-hidden',
      'shadow-sm hover:shadow-md transition-shadow'
    )}>
      {/* Header */}
      <div className={cn(
        'px-4 py-3 border-b border-theme',
        'sm:px-6 sm:py-4',
        'flex items-center justify-between'
      )}>
        <h3 className="text-lg font-medium text-theme-primary">
          {title}
        </h3>
        {actions && (
          <div className={cn(
            'flex items-center',
            isMobile ? 'space-x-2' : 'space-x-3'
          )}>
            {actions}
          </div>
        )}
      </div>
      
      {/* Content */}
      <div className={cn(
        'px-4 py-4',
        'sm:px-6 sm:py-5'
      )}>
        {children}
      </div>
    </div>
  );
};

// Responsive navigation example
export const ResponsiveNavigation: React.FC = () => {
  const { isMobile } = useBreakpoint();
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  
  if (isMobile) {
    return (
      <>
        {/* Mobile menu button */}
        <button
          onClick={() => setMobileMenuOpen(true)}
          className="p-2 text-theme-primary"
        >
          <MenuIcon className="h-6 w-6" />
        </button>
        
        {/* Mobile slide-out menu */}
        <Modal 
          open={mobileMenuOpen} 
          onOpenChange={setMobileMenuOpen}
          size="full"
          className="slide-in-from-left"
        >
          <NavigationMenu />
        </Modal>
      </>
    );
  }
  
  return (
    <nav className="hidden md:flex space-x-8">
      <NavigationMenu />
    </nav>
  );
};
```

## Development Commands

### Component Development
```bash
# Create new component with template
mkdir -p src/shared/components/ui
touch src/shared/components/ui/NewComponent.tsx

# Run Storybook for component development
npm run storybook

# Test components
npm run test -- --testPathPattern=components

# Lint component code
npm run lint -- --fix

# Build component library
npm run build-components
```

### Accessibility Testing
```bash
# Install accessibility testing tools
npm install --save-dev @axe-core/react jest-axe

# Run accessibility tests
npm run test:a11y

# Test with screen reader simulation
npm install --save-dev @testing-library/jest-dom
```

## Integration Points

### UI Component Developer Coordinates With:
- **React Architect**: Component architecture, design system structure
- **Dashboard Specialist**: Chart components, data visualization UI
- **Admin Panel Developer**: Admin-specific components, complex forms
- **Frontend Test Engineer**: Component testing, accessibility testing
- **Design Team**: Design system implementation, theme integration

## Quick Reference

### Component Template
```tsx
import React, { forwardRef } from 'react';
import { cn } from '@/shared/utils/cn';

export interface ComponentProps extends React.HTMLAttributes<HTMLDivElement> {
  variant?: 'default' | 'primary' | 'secondary';
  size?: 'sm' | 'md' | 'lg';
  children: React.ReactNode;
}

export const Component = forwardRef<HTMLDivElement, ComponentProps>(({
  variant = 'default',
  size = 'md',
  className,
  children,
  ...props
}, ref) => {
  return (
    <div
      ref={ref}
      className={cn(
        'base-styles',
        `variant-${variant}`,
        `size-${size}`,
        className
      )}
      {...props}
    >
      {children}
    </div>
  );
});

Component.displayName = 'Component';
```

## Critical Styling Standards (MANDATORY)

### 1. Theme-Aware Styling Requirements (ABSOLUTE)

**CRITICAL PROHIBITION**: Hardcoded color classes are FORBIDDEN across all components except `text-white` on colored backgrounds.

#### Standard Theme Class Mapping
```typescript
// ❌ FORBIDDEN: Hardcoded color usage
const FORBIDDEN_CLASSES = [
  'bg-yellow-100', 'bg-yellow-400', 'text-yellow-800',
  'bg-red-500', 'bg-red-600', 'border-red-300',
  'bg-green-50', 'bg-green-200', 'text-green-600',
  'bg-blue-500', 'text-blue-600', 'border-blue-400',
  'bg-gray-100', 'text-gray-900', 'border-gray-300'
];

// ✅ MANDATORY: Theme-aware replacements
const THEME_CLASSES = {
  // Background colors
  surface: 'bg-theme-surface',
  background: 'bg-theme-background',
  surfaceHover: 'bg-theme-surface-hover',
  surfaceSubtle: 'bg-theme-surface-subtle',
  
  // Primary colors
  primary: 'bg-theme-primary',
  primaryHover: 'bg-theme-primary-hover',
  primaryDark: 'bg-theme-primary-dark',
  
  // State colors
  error: 'bg-theme-error',
  errorBackground: 'bg-theme-error-background',
  warning: 'bg-theme-warning',
  warningBackground: 'bg-theme-warning-background',
  success: 'bg-theme-success', 
  successBackground: 'bg-theme-success-background',
  
  // Text colors
  textPrimary: 'text-theme-primary',
  textSecondary: 'text-theme-secondary',
  textTertiary: 'text-theme-tertiary',
  textError: 'text-theme-error',
  textErrorDark: 'text-theme-error-dark',
  textWarning: 'text-theme-warning',
  textWarningDark: 'text-theme-warning-dark',
  textSuccess: 'text-theme-success',
  textSuccessDark: 'text-theme-success-dark',
  
  // Borders
  border: 'border-theme',
  borderError: 'border-theme-error',
  borderWarning: 'border-theme-warning',
  borderSuccess: 'border-theme-success',
  
  // Interactive elements
  interactivePrimary: 'bg-theme-interactive-primary',
  link: 'text-theme-link',
  
  // Special case - only exception
  textWhite: 'text-white' // ONLY on colored backgrounds
} as const;
```

#### Component Theme Integration Pattern
```tsx
// ✅ CORRECT: Theme-aware button with consistent variants
const Button = forwardRef<HTMLButtonElement, ButtonProps>(({ variant, size, className, ...props }, ref) => {
  const themeClasses = cn(
    // Base theme-aware styles
    'inline-flex items-center justify-center font-medium transition-colors rounded-md',
    'bg-theme-surface text-theme-primary border border-theme',
    'hover:bg-theme-surface-hover focus:ring-2 focus:ring-theme-primary focus:ring-offset-2',
    'disabled:opacity-50 disabled:pointer-events-none',
    
    // Variant-specific theme classes
    {
      'bg-theme-interactive-primary text-white hover:bg-theme-primary-hover': variant === 'primary',
      'bg-theme-surface text-theme-primary hover:bg-theme-background': variant === 'secondary', 
      'bg-theme-error text-white hover:bg-theme-error/90': variant === 'danger',
      'bg-theme-warning text-white hover:bg-theme-warning/90': variant === 'warning',
      'bg-theme-success text-white hover:bg-theme-success/90': variant === 'success'
    },
    
    className
  );
  
  return <button ref={ref} className={themeClasses} {...props} />;
});
```

### 2. Accessibility Standards (WCAG AA MANDATORY)

#### Contrast Compliance (CRITICAL)
**ABSOLUTE REQUIREMENT**: All interactive elements must meet WCAG AA contrast standards.

```tsx
// ✅ CORRECT: Form input with sufficient contrast
const Input = forwardRef<HTMLInputElement, InputProps>(({ error, className, ...props }, ref) => {
  const inputClasses = cn(
    // Base contrast-compliant styling
    'w-full px-3 py-2 rounded-md border transition-colors',
    'bg-theme-surface text-theme-primary placeholder:text-theme-tertiary',
    'border-theme focus:border-theme-primary focus:ring-2 focus:ring-theme-primary focus:ring-offset-0',
    
    // Error state with proper contrast
    error && 'border-theme-error focus:border-theme-error focus:ring-theme-error',
    
    // Disabled state maintains readability  
    'disabled:opacity-50 disabled:cursor-not-allowed disabled:bg-theme-background',
    
    className
  );
  
  return <input ref={ref} className={inputClasses} {...props} />;
});
```

#### Emergency Controls Pattern (CRITICAL)
```tsx
// ✅ CORRECT: Emergency control with theme-aware danger styling
const EmergencyControl: React.FC = () => {
  return (
    <div className="p-4 border border-theme bg-theme-warning-background rounded-lg">
      <h4 className="font-medium text-theme-warning mb-2">Temporarily Disable</h4>
      <p className="text-sm text-theme-warning-dark mb-3">Emergency maintenance control</p>
      
      <div className="flex items-center gap-3">
        <input
          type="number"
          min="1"
          max="480"
          className="w-20 px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:ring-2 focus:ring-theme-warning focus:border-theme-warning text-sm font-medium"
        />
        <span className="text-sm text-theme-warning-dark font-medium">minutes</span>
        
        <Button variant="warning" size="sm" className="ml-auto">
          <Ban className="w-4 h-4 mr-1" />
          Disable
        </Button>
      </div>
    </div>
  );
};
```

#### Status Indicators with Theme Awareness
```tsx
// ✅ CORRECT: Status indicators using theme classes
const StatusIndicator: React.FC<{ status: 'error' | 'warning' | 'success' }> = ({ status }) => {
  const statusConfig = {
    error: {
      bg: 'bg-theme-error-background',
      border: 'border-theme-error', 
      text: 'text-theme-error',
      icon: 'text-theme-error'
    },
    warning: {
      bg: 'bg-theme-warning-background',
      border: 'border-theme-warning',
      text: 'text-theme-warning-dark', 
      icon: 'text-theme-warning'
    },
    success: {
      bg: 'bg-theme-success-background',
      border: 'border-theme-success',
      text: 'text-theme-success-dark',
      icon: 'text-theme-success'
    }
  };
  
  const config = statusConfig[status];
  
  return (
    <div className={cn('p-4 border rounded-lg', config.bg, config.border)}>
      <div className="flex items-center gap-3">
        <AlertTriangle className={cn('w-5 h-5', config.icon)} />
        <div className={cn('font-medium', config.text)}>
          Status: {status}
        </div>
      </div>
    </div>
  );
};
```

### 3. Form Component Standards (MANDATORY)

#### Standard Button Component Usage
**CRITICAL**: ALL interactive elements must use the standard Button component.

```tsx
// ❌ FORBIDDEN: Custom button implementations
<button
  onClick={handleRefresh}
  className="inline-flex items-center px-3 py-2 border border-gray-300 text-sm font-medium rounded-md"
>
  Refresh
</button>

// ✅ MANDATORY: Standard Button component
<Button
  onClick={handleRefresh}
  variant="secondary"
  size="sm"
>
  <RefreshIcon className="w-4 h-4 mr-2" />
  Refresh
</Button>
```

#### Button Variant Standards
```tsx
// Action type mapping for consistent UX
const BUTTON_USAGE = {
  // Primary actions - main user flows
  primary: ['Save Changes', 'Create User', 'Submit', 'Continue'],
  
  // Secondary actions - supporting actions
  secondary: ['Cancel', 'Back', 'Refresh Stats', 'Show/Hide'],
  
  // Danger actions - destructive operations
  danger: ['Delete', 'Remove', 'Permanently Delete'],
  
  // Warning actions - potentially risky
  warning: ['Disable', 'Suspend', 'Temporarily Disable'],
  
  // Success actions - positive confirmations
  success: ['Enable', 'Activate', 'Re-enable', 'Approve']
} as const;

// ✅ CORRECT: Proper button variant usage
<Button variant="primary" loading={saving}>
  <Save className="w-5 h-5 mr-2" />
  Save Rate Limiting Settings
</Button>

<Button variant="warning" size="sm">
  <Ban className="w-4 h-4 mr-1" /> 
  Temporarily Disable
</Button>

<Button variant="success" size="sm">
  <Play className="w-4 h-4 mr-1" />
  Re-enable
</Button>
```

### 4. Component Validation Commands

#### Theme Compliance Audits
```bash
# Critical hardcoded color detection (should return empty)
grep -r "bg-red-\|bg-green-\|bg-yellow-\|bg-blue-\|bg-gray-" src/shared/components/ | grep -v "text-white"
grep -r "text-red-\|text-green-\|text-yellow-\|text-blue-" src/shared/components/ | grep -v "text-white"
grep -r "border-red-\|border-green-\|border-yellow-\|border-blue-" src/shared/components/

# Theme class usage verification (should be substantial)
grep -r "bg-theme-\|text-theme-\|border-theme" src/shared/components/ | wc -l

# Button component standardization
grep -r "<button[^>]*className=" src/shared/components/ | wc -l  # Should be minimal
grep -r "<Button" src/shared/components/ | wc -l                # Should be primary

# Accessibility features verification
grep -r "aria-label\|aria-describedby\|htmlFor" src/shared/components/ | wc -l
grep -r "focus:ring-2.*focus:ring-theme-" src/shared/components/ | wc -l
```

#### Component Pattern Validation
```bash
# Standard component structure verification
grep -r "forwardRef<HTML.*Props>" src/shared/components/ | wc -l
grep -r "displayName = " src/shared/components/ | wc -l

# Theme integration pattern
grep -r "variant.*primary\|secondary\|danger\|warning\|success" src/shared/components/ | wc -l

# Proper className composition
grep -r "cn(" src/shared/components/ | wc -l
```

#### Form Component Standards
```bash
# Form input contrast compliance
grep -r "bg-theme-surface.*text-theme-primary" src/shared/components/forms/ | wc -l

# Focus state implementation
grep -r "focus:border-theme-primary" src/shared/components/forms/ | wc -l

# Error state styling
grep -r "border-theme-error.*focus:ring-theme-error" src/shared/components/forms/ | wc -l
```

### Accessibility Checklist (WCAG AA COMPLIANCE)
- ✅ **Contrast ratios**: 4.5:1 normal text, 3:1 large text
- ✅ **Theme-aware colors**: NO hardcoded colors except `text-white`
- ✅ **Focus indicators**: Visible 2px focus rings with theme colors
- ✅ **Semantic HTML**: Proper heading hierarchy, form labels
- ✅ **ARIA attributes**: Labels, descriptions, roles where needed
- ✅ **Keyboard navigation**: Tab order, escape key handling
- ✅ **Screen reader support**: Descriptive text, status announcements
- ✅ **Touch targets**: Minimum 44px for interactive elements
- ✅ **Form validation**: Clear error messages, field associations
- ✅ **Loading states**: Accessible progress indicators

### 6. Page Layout Standards (MANDATORY)

#### PageContainer - Standard Page Wrapper
**CRITICAL**: ALL application pages MUST use PageContainer for consistent layout and navigation.

```tsx
// src/shared/components/layout/PageContainer.tsx
import { PageContainer, BreadcrumbItem, PageAction } from '@/shared/components/layout/PageContainer';

// MANDATORY Pattern for ALL Pages
export function MyPage() {
  const breadcrumbs: BreadcrumbItem[] = [
    {
      label: 'Dashboard',
      href: '/app',
      icon: HomeIcon
    },
    {
      label: 'Section Name',
      href: '/app/section'
    },
    {
      label: 'Current Page'  // No href for current page
    }
  ];

  const actions: PageAction[] = [
    {
      id: 'create',
      label: 'Create New',
      onClick: handleCreate,
      variant: 'primary',
      icon: PlusIcon
    }
  ];

  return (
    <PageContainer
      title="Page Title"
      description="Clear description of page purpose"
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      {/* Page content */}
    </PageContainer>
  );
}
```

#### Breadcrumb System Integration
**REQUIRED**: Use hierarchical breadcrumbs following this pattern:
- **Dashboard** → **Section** → **Category/Filter** → **Current Page**
- **Clickable navigation** back to parent levels
- **Icon support** for visual hierarchy
- **Theme-aware styling** using SharedBreadcrumbs component

#### Page Action Standards
```tsx
// Standard action patterns
const actions: PageAction[] = [
  {
    id: 'back',           // Navigation actions
    label: 'Back',
    onClick: () => navigate(-1),
    variant: 'outline',
    icon: ArrowLeftIcon
  },
  {
    id: 'edit',           // Modification actions
    label: 'Edit',
    onClick: handleEdit,
    variant: 'secondary',
    icon: PencilIcon
  },
  {
    id: 'create',         // Primary actions
    label: 'Create New',
    onClick: handleCreate,
    variant: 'primary',   // Always right-most
    icon: PlusIcon
  }
];
```

#### Content Organization Patterns
```tsx
// Standard content structure within PageContainer
<PageContainer title="..." breadcrumbs={...} actions={...}>
  {/* 1. Filters/Search (if applicable) */}
  <div className="bg-theme-surface rounded-lg border border-theme p-6">
    <SearchAndFilters />
  </div>

  {/* 2. Main Content Grid */}
  <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
    <div className="lg:col-span-2">
      <MainContent />
    </div>
    <div className="sidebar space-y-6">
      <Sidebar />
    </div>
  </div>

  {/* 3. Additional Sections */}
  <div className="space-y-6">
    <RelatedContent />
  </div>
</PageContainer>
```

#### Loading and Error States
```tsx
// MANDATORY: Consistent loading/error patterns
if (loading) {
  return (
    <PageContainer
      title="Loading..."
      breadcrumbs={baseBreadcrumbs}
    >
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-theme-primary"></div>
      </div>
    </PageContainer>
  );
}

if (error) {
  return (
    <PageContainer
      title="Error"
      breadcrumbs={baseBreadcrumbs}
      actions={[{ id: 'back', label: 'Go Back', onClick: () => navigate(-1), variant: 'primary' }]}
    >
      <div className="text-center py-12">
        <h3 className="text-lg font-medium text-theme-primary mb-2">{error}</h3>
      </div>
    </PageContainer>
  );
}
```

#### Text Rendering Standards
**CRITICAL**: For displaying user content that may contain markdown:

```tsx
import { stripMarkdown } from '@/shared/utils/markdownUtils';

// Card previews and excerpts - ALWAYS strip markdown
<p className="text-theme-secondary line-clamp-2">
  {stripMarkdown(article.excerpt)}
</p>

// Full content areas - Render markdown with ReactMarkdown
<ReactMarkdown
  remarkPlugins={[remarkGfm, remarkBreaks]}
  rehypePlugins={[rehypeHighlight, rehypeRaw]}
  components={markdownComponents}
>
  {article.content}
</ReactMarkdown>
```

### Component Standards Enforcement
- ✅ **PageContainer wrapper**: MANDATORY for ALL application pages
- ✅ **Hierarchical breadcrumbs**: Dashboard → Section → Current
- ✅ **Consistent page actions**: Primary actions right-aligned
- ✅ **Standard loading states**: Spinner with breadcrumb hierarchy
- ✅ **Error state handling**: Breadcrumbs + back navigation
- ✅ **Text rendering**: stripMarkdown() for previews, ReactMarkdown for content
- ✅ **Standard Button component**: ALL interactive elements
- ✅ **Theme integration**: Consistent variant mapping
- ✅ **Proper sizing**: xs, sm, md, lg with appropriate spacing
- ✅ **Loading states**: Built-in spinner and disabled states
- ✅ **Icon integration**: Consistent positioning and sizing
- ✅ **Accessibility props**: ARIA labels, keyboard support

**ALWAYS REFERENCE ../TODO.md FOR CURRENT TASKS AND PRIORITIES**