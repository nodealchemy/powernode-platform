import React, { useState, useEffect, useRef } from 'react';
import { ChevronLeft, ChevronRight, Calendar, X } from 'lucide-react';

interface ReactDatePickerProps {
  selected: Date | null;
  onChange: (date: Date | null) => void;
  placeholderText?: string;
  minDate?: Date;
  maxDate?: Date;
  disabled?: boolean;
  className?: string;
  id?: string;
  name?: string;
  required?: boolean;
  showTimeSelect?: boolean;
}

const DAYS_OF_WEEK = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
const MONTHS = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];

export const ReactDatePicker: React.FC<ReactDatePickerProps> = ({
  selected,
  onChange,
  placeholderText = 'Select a date',
  minDate,
  maxDate,
  disabled = false,
  className = '',
  id,
  name,
  required = false,
  showTimeSelect = false,
}) => {
  const [isOpen, setIsOpen] = useState(false);
  const [viewDate, setViewDate] = useState(() => selected || new Date());
  const [timeValue, setTimeValue] = useState(() => {
    if (selected && showTimeSelect) {
      const hours = selected.getHours().toString().padStart(2, '0');
      const minutes = selected.getMinutes().toString().padStart(2, '0');
      return `${hours}:${minutes}`;
    }
    return '00:00';
  });

  const containerRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  // Close calendar when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(event.target as Node)) {
        setIsOpen(false);
      }
    };

    if (isOpen) {
      document.addEventListener('mousedown', handleClickOutside);
      return () => document.removeEventListener('mousedown', handleClickOutside);
    }
  }, [isOpen]);

  // Format date for display
  const formatDate = (date: Date | null): string => {
    if (!date) return '';
    const month = (date.getMonth() + 1).toString().padStart(2, '0');
    const day = date.getDate().toString().padStart(2, '0');
    const year = date.getFullYear();
    
    if (showTimeSelect) {
      const hours = date.getHours().toString().padStart(2, '0');
      const minutes = date.getMinutes().toString().padStart(2, '0');
      return `${month}/${day}/${year} ${hours}:${minutes}`;
    }
    
    return `${month}/${day}/${year}`;
  };

  // Get days in month
  const getDaysInMonth = (date: Date) => {
    const year = date.getFullYear();
    const month = date.getMonth();
    const firstDay = new Date(year, month, 1);
    const lastDay = new Date(year, month + 1, 0);
    const daysInMonth = lastDay.getDate();
    const startingDayOfWeek = firstDay.getDay();

    const days: (Date | null)[] = [];
    
    // Add empty cells for days from previous month
    for (let i = 0; i < startingDayOfWeek; i++) {
      days.push(null);
    }
    
    // Add days of the month
    for (let day = 1; day <= daysInMonth; day++) {
      days.push(new Date(year, month, day));
    }
    
    return days;
  };

  // Check if date is disabled
  const isDateDisabled = (date: Date) => {
    if (minDate && date < minDate) return true;
    if (maxDate && date > maxDate) return true;
    return false;
  };

  // Check if date is selected
  const isDateSelected = (date: Date) => {
    if (!selected) return false;
    return (
      date.getDate() === selected.getDate() &&
      date.getMonth() === selected.getMonth() &&
      date.getFullYear() === selected.getFullYear()
    );
  };

  // Check if date is today
  const isToday = (date: Date) => {
    const today = new Date();
    return (
      date.getDate() === today.getDate() &&
      date.getMonth() === today.getMonth() &&
      date.getFullYear() === today.getFullYear()
    );
  };

  // Handle date selection
  const handleDateSelect = (date: Date) => {
    if (isDateDisabled(date)) return;

    const newDate = new Date(date);
    
    if (showTimeSelect && timeValue) {
      const [hours, minutes] = timeValue.split(':').map(Number);
      newDate.setHours(hours, minutes, 0, 0);
    }
    
    onChange(newDate);
    if (!showTimeSelect) {
      setIsOpen(false);
    }
  };

  // Handle time change
  const handleTimeChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    const newTimeValue = event.target.value;
    setTimeValue(newTimeValue);
    
    if (selected) {
      const [hours, minutes] = newTimeValue.split(':').map(Number);
      const newDate = new Date(selected);
      newDate.setHours(hours, minutes, 0, 0);
      onChange(newDate);
    }
  };

  // Navigate months
  const navigateMonth = (direction: 'prev' | 'next') => {
    setViewDate(prev => {
      const newDate = new Date(prev);
      if (direction === 'prev') {
        newDate.setMonth(prev.getMonth() - 1);
      } else {
        newDate.setMonth(prev.getMonth() + 1);
      }
      return newDate;
    });
  };

  // Clear selection
  const handleClear = () => {
    onChange(null);
    setIsOpen(false);
  };

  // Toggle calendar
  const toggleCalendar = () => {
    if (disabled) return;
    setIsOpen(!isOpen);
  };

  const days = getDaysInMonth(viewDate);

  return (
    <div ref={containerRef} className="relative">
      {/* Input field */}
      <div className="relative">
        <input
          ref={inputRef}
          type="text"
          id={id}
          name={name}
          value={formatDate(selected)}
          onClick={toggleCalendar}
          placeholder={placeholderText}
          readOnly
          disabled={disabled}
          required={required}
          className={`w-full px-3 py-2 text-sm bg-theme-surface border border-theme rounded-md shadow-sm placeholder-theme-tertiary text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary focus:border-theme-interactive-primary pr-14 cursor-pointer ${className} ${disabled ? 'opacity-50 cursor-not-allowed bg-theme-surface-disabled' : ''}`}
        />
        
        {/* Calendar icon */}
        <button
          type="button"
          onClick={toggleCalendar}
          disabled={disabled}
          className="absolute right-8 top-1/2 transform -translate-y-1/2 text-theme-secondary hover:text-theme-primary disabled:opacity-50 focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary rounded p-1"
          aria-label="Open calendar"
        >
          <Calendar className="w-5 h-5" />
        </button>
        
        {/* Clear button */}
        {selected && !disabled && (
          <button
            type="button"
            onClick={handleClear}
            className="absolute right-2 top-1/2 transform -translate-y-1/2 text-theme-secondary hover:text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary rounded p-0.5"
            aria-label="Clear date"
          >
            <X className="w-4 h-4" />
          </button>
        )}
      </div>

      {/* Calendar popup */}
      {isOpen && !disabled && (
        <div className="absolute top-full left-0 mt-1 bg-theme-surface border border-theme rounded-lg shadow-lg z-50 p-4 min-w-80">
          {/* Header with month navigation */}
          <div className="flex items-center justify-between mb-4">
            <button
              type="button"
              onClick={() => navigateMonth('prev')}
              className="p-1 hover:bg-theme-surface-hover rounded text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
              aria-label="Previous month"
            >
              <ChevronLeft className="w-4 h-4" />
            </button>
            
            <div className="font-semibold text-theme-primary">
              {MONTHS[viewDate.getMonth()]} {viewDate.getFullYear()}
            </div>
            
            <button
              type="button"
              onClick={() => navigateMonth('next')}
              className="p-1 hover:bg-theme-surface-hover rounded text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
              aria-label="Next month"
            >
              <ChevronRight className="w-4 h-4" />
            </button>
          </div>

          {/* Days of week header */}
          <div className="grid grid-cols-7 gap-1 mb-2">
            {DAYS_OF_WEEK.map(day => (
              <div key={day} className="text-xs font-medium text-theme-secondary text-center p-2">
                {day}
              </div>
            ))}
          </div>

          {/* Calendar grid */}
          <div className="grid grid-cols-7 gap-1 mb-4">
            {days.map((day, index) => (
              <div key={index} className="aspect-square">
                {day && (
                  <button
                    type="button"
                    onClick={() => handleDateSelect(day)}
                    disabled={isDateDisabled(day)}
                    className={`
                      w-full h-full rounded text-sm transition-colors focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary
                      ${isDateSelected(day)
                        ? 'bg-theme-interactive-primary text-white shadow-sm'
                        : isToday(day)
                        ? 'bg-theme-warning text-white shadow-sm'
                        : 'text-theme-primary hover:bg-theme-surface-hover'
                      }
                      ${isDateDisabled(day)
                        ? 'opacity-50 cursor-not-allowed text-theme-tertiary'
                        : 'cursor-pointer hover:shadow-sm'
                      }
                    `}
                  >
                    {day.getDate()}
                  </button>
                )}
              </div>
            ))}
          </div>

          {/* Time selection */}
          {showTimeSelect && (
            <div className="border-t border-theme pt-4">
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Select Time
              </label>
              <input
                type="time"
                value={timeValue}
                onChange={handleTimeChange}
                className="w-full px-3 py-2 text-sm bg-theme-surface border border-theme rounded-md shadow-sm text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary focus:border-theme-interactive-primary"
              />
            </div>
          )}
        </div>
      )}
    </div>
  );
};

export default ReactDatePicker;