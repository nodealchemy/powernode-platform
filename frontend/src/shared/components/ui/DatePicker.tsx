import React from 'react';
import { ReactDatePicker } from '@/shared/components/ui/ReactDatePicker';

interface DatePickerProps {
  selected: Date | null;
  onChange: (date: Date | null) => void;
  placeholderText?: string;
  dateFormat?: string;
  showTimeSelect?: boolean;
  timeFormat?: string;
  timeIntervals?: number;
  minDate?: Date;
  maxDate?: Date;
  disabled?: boolean;
  className?: string;
  isClearable?: boolean;
  showMonthDropdown?: boolean;
  showYearDropdown?: boolean;
  dropdownMode?: 'scroll' | 'select';
  id?: string;
  name?: string;
  autoComplete?: string;
  required?: boolean;
  useNativeInput?: boolean; // New prop to choose between native and React picker
}

// Helper function to format date for input value
const formatDateForInput = (date: Date | null, showTime: boolean = false): string => {
  if (!date) return '';
  
  if (showTime) {
    // Format as datetime-local input value
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    const hours = String(date.getHours()).padStart(2, '0');
    const minutes = String(date.getMinutes()).padStart(2, '0');
    return `${year}-${month}-${day}T${hours}:${minutes}`;
  } else {
    // Format as date input value
    return date.toISOString().split('T')[0];
  }
};

// Helper function to parse input value to Date
const parseDateFromInput = (value: string, showTime: boolean = false): Date | null => {
  if (!value) return null;
  
  if (showTime) {
    return new Date(value);
  } else {
    // For date-only inputs, create date at midnight local time to avoid timezone issues
    const [year, month, day] = value.split('-').map(Number);
    return new Date(year, month - 1, day);
  }
};

export const DatePicker: React.FC<DatePickerProps> = ({
  selected,
  onChange,
  placeholderText = 'Select a date',
  showTimeSelect = false,
  minDate,
  maxDate,
  disabled = false,
  className = '',
  id,
  name,
  autoComplete,
  required = false,
  useNativeInput = true, // Default to native input for reliability
}) => {
  // Use custom React picker if requested
  if (!useNativeInput) {
    return (
      <ReactDatePicker
        selected={selected}
        onChange={onChange}
        placeholderText={placeholderText}
        showTimeSelect={showTimeSelect}
        minDate={minDate}
        maxDate={maxDate}
        disabled={disabled}
        className={className}
        id={id}
        name={name}
        required={required}
      />
    );
  }

  // Use native HTML input (default, most reliable)
  const inputType = showTimeSelect ? 'datetime-local' : 'date';
  const inputValue = formatDateForInput(selected, showTimeSelect);
  
  const handleChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    const value = event.target.value;
    const newDate = parseDateFromInput(value, showTimeSelect);
    onChange(newDate);
  };

  const handleClear = () => {
    onChange(null);
  };

  return (
    <div className="relative">
      <input
        type={inputType}
        id={id}
        name={name}
        value={inputValue}
        onChange={handleChange}
        min={minDate ? formatDateForInput(minDate, showTimeSelect) : undefined}
        max={maxDate ? formatDateForInput(maxDate, showTimeSelect) : undefined}
        disabled={disabled}
        required={required}
        autoComplete={autoComplete}
        placeholder={placeholderText}
        className={`w-full px-3 py-2 text-sm bg-theme-surface border border-theme rounded-md shadow-sm placeholder-theme-tertiary text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary focus:border-theme-interactive-primary ${disabled ? 'opacity-50 cursor-not-allowed bg-theme-surface-disabled' : ''} ${className}`}
      />
      
      {/* Clear button if value exists and component supports clearing */}
      {inputValue && !disabled && (
        <button
          type="button"
          onClick={handleClear}
          className="absolute right-2 top-1/2 transform -translate-y-1/2 text-theme-secondary hover:text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary rounded p-0.5"
          aria-label="Clear date"
        >
          ×
        </button>
      )}
    </div>
  );
};

export default DatePicker;