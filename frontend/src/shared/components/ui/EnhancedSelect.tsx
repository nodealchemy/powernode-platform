import React, { useState, useRef, useEffect } from 'react';
import { ChevronDown, Check } from 'lucide-react';

export interface SelectOption {
  value: string;
  label: string;
  description?: string;
  disabled?: boolean;
  icon?: React.ComponentType<any>;
}

export interface EnhancedSelectProps {
  value?: string;
  onChange?: (value: string) => void;
  onValueChange?: (value: string) => void; // Support both naming conventions
  options?: SelectOption[]; // Make optional to handle loading states
  renderOption?: (option: SelectOption) => React.ReactNode;
  placeholder?: string;
  label?: string;
  error?: string;
  fullWidth?: boolean;
  disabled?: boolean;
  className?: string;
}

export const EnhancedSelect: React.FC<EnhancedSelectProps> = ({
  value,
  onChange,
  onValueChange, // Support both naming conventions
  options,
  renderOption,
  placeholder = 'Select an option...',
  label,
  error,
  fullWidth = true,
  disabled = false,
  className = ''
}) => {
  const [isOpen, setIsOpen] = useState(false);
  const [selectedOption, setSelectedOption] = useState<SelectOption | null>(
    options?.find(option => option.value === value) || null
  );
  const containerRef = useRef<HTMLDivElement>(null);
  const selectId = `select-${Math.random().toString(36).substr(2, 9)}`;

  useEffect(() => {
    const option = options?.find(opt => opt.value === value);
    setSelectedOption(option || null);
  }, [value, options]);

  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(event.target as Node)) {
        setIsOpen(false);
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  const handleSelect = (option: SelectOption) => {
    if (option.disabled) return;

    setSelectedOption(option);
    setIsOpen(false);
    onChange?.(option.value);
    onValueChange?.(option.value); // Support both naming conventions
  };

  const handleKeyDown = (event: React.KeyboardEvent) => {
    if (disabled) return;

    switch (event.key) {
      case 'Enter':
      case ' ':
        event.preventDefault();
        setIsOpen(!isOpen);
        break;
      case 'Escape':
        setIsOpen(false);
        break;
      case 'ArrowDown':
        event.preventDefault();
        if (!isOpen) {
          setIsOpen(true);
        } else if (options && options.length > 0) {
          const currentIndex = selectedOption ? options.indexOf(selectedOption) : -1;
          const nextIndex = currentIndex < options.length - 1 ? currentIndex + 1 : 0;
          const nextOption = options[nextIndex];
          if (nextOption && !nextOption.disabled) {
            handleSelect(nextOption);
          }
        }
        break;
      case 'ArrowUp':
        event.preventDefault();
        if (isOpen && options && options.length > 0) {
          const currentIndex = selectedOption ? options.indexOf(selectedOption) : 0;
          const prevIndex = currentIndex > 0 ? currentIndex - 1 : options.length - 1;
          const prevOption = options[prevIndex];
          if (prevOption && !prevOption.disabled) {
            handleSelect(prevOption);
          }
        }
        break;
    }
  };

  const buttonClassName = `
    relative w-full px-3 py-2 text-left border rounded-md
    bg-theme-surface text-theme-primary cursor-pointer
    focus:outline-none focus:ring-2 focus:ring-theme-primary focus:border-transparent
    disabled:bg-theme-background disabled:text-theme-secondary disabled:cursor-not-allowed
    ${fullWidth ? 'w-full' : ''}
    ${error ? 'border-theme-error focus:ring-theme-error' : 'border-theme'}
    ${isOpen ? 'ring-2 ring-theme-primary border-transparent' : ''}
    ${className}
  `.trim();

  const dropdownClassName = `
    absolute z-50 w-full mt-1 bg-theme-surface border border-theme rounded-md shadow-lg
    max-h-60 overflow-auto
  `.trim();

  const optionClassName = (option: SelectOption, isSelected: boolean) => `
    relative cursor-pointer select-none py-2 pl-3 pr-9 group
    hover:bg-theme-surface-hover hover:text-theme-primary
    ${isSelected ? 'bg-theme-surface-selected text-theme-primary hover:bg-theme-surface-selected' : 'text-theme-primary'}
    ${option.disabled ? 'opacity-50 cursor-not-allowed hover:bg-transparent' : ''}
  `.trim();

  return (
    <div className={fullWidth ? 'w-full' : ''}>
      {label && (
        <label 
          htmlFor={selectId}
          className="block text-sm font-medium text-theme-primary mb-1"
        >
          {label}
        </label>
      )}
      
      <div ref={containerRef} className="relative">
        <button
          type="button"
          id={selectId}
          className={buttonClassName}
          onClick={() => !disabled && setIsOpen(!isOpen)}
          onKeyDown={handleKeyDown}
          disabled={disabled}
          aria-haspopup="listbox"
          aria-expanded={isOpen}
          aria-describedby={error ? `${selectId}-error` : undefined}
        >
          <span className="block truncate pr-8">
            {selectedOption ? selectedOption.label : placeholder}
          </span>
          <span className="absolute inset-y-0 right-0 flex items-center pr-2 pointer-events-none">
            <ChevronDown 
              className={`h-4 w-4 text-theme-secondary transition-transform duration-200 ${
                isOpen ? 'transform rotate-180' : ''
              }`} 
            />
          </span>
        </button>

        {isOpen && (
          <div className={dropdownClassName}>
            <ul role="listbox" className="py-1">
              {(options || []).map((option) => {
                const isSelected = selectedOption?.value === option.value;
                return (
                  <li
                    key={option.value}
                    role="option"
                    aria-selected={isSelected}
                    className={optionClassName(option, isSelected)}
                    onClick={() => handleSelect(option)}
                  >
                    {renderOption ? (
                      renderOption(option)
                    ) : (
                      <div>
                        <div className="font-medium">{option.label}</div>
                        {option.description && (
                          <div className="text-sm text-theme-muted group-hover:text-theme-secondary">{option.description}</div>
                        )}
                      </div>
                    )}
                    
                    {isSelected && (
                      <span className="absolute inset-y-0 right-0 flex items-center pr-3">
                        <Check className="h-4 w-4 text-theme-primary" />
                      </span>
                    )}
                  </li>
                );
              })}
            </ul>
          </div>
        )}
      </div>

      {error && (
        <p id={`${selectId}-error`} className="mt-1 text-sm text-theme-error" role="alert">
          {error}
        </p>
      )}
    </div>
  );
};