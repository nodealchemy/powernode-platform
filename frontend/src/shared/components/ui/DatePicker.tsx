import React, { forwardRef } from 'react';
import ReactDatePicker from 'react-datepicker';
import { useThemeColors } from '@/shared/hooks/useThemeColors';
import 'react-datepicker/dist/react-datepicker.css';

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
}

// Custom input component that integrates with our theme system
const CustomInput = forwardRef<HTMLInputElement, any>(({ value, onClick, placeholder, className, ...props }, ref) => (
  <input
    {...props}
    ref={ref}
    value={value}
    onClick={onClick}
    placeholder={placeholder}
    className={`input-theme ${className || ''}`}
    readOnly
  />
));


export const DatePicker: React.FC<DatePickerProps> = ({
  selected,
  onChange,
  placeholderText = 'Select a date',
  dateFormat = 'MM/dd/yyyy',
  showTimeSelect = false,
  timeFormat = 'HH:mm',
  timeIntervals = 15,
  minDate,
  maxDate,
  disabled = false,
  className = '',
  isClearable = true,
  showMonthDropdown = true,
  showYearDropdown = true,
  dropdownMode = 'select',
  id,
  name,
  autoComplete,
  required = false,
}) => {
  const colors = useThemeColors();

  return (
    <div className="relative">
      <ReactDatePicker
        selected={selected}
        onChange={onChange}
        dateFormat={showTimeSelect ? `${dateFormat} ${timeFormat}` : dateFormat}
        showTimeSelect={showTimeSelect}
        timeFormat={timeFormat}
        timeIntervals={timeIntervals}
        minDate={minDate}
        maxDate={maxDate}
        disabled={disabled}
        isClearable={isClearable}
        showMonthDropdown={showMonthDropdown}
        showYearDropdown={showYearDropdown}
        dropdownMode={dropdownMode}
        placeholderText={placeholderText}
        customInput={<CustomInput className={className} />}
        id={id}
        name={name}
        autoComplete={autoComplete}
        required={required}
        popperClassName="date-picker-popper"
        calendarClassName="date-picker-calendar"
      />
      <style dangerouslySetInnerHTML={{
        __html: `
          .date-picker-popper {
            z-index: 9999 !important;
          }
          
          .date-picker-calendar {
            background-color: ${colors.background} !important;
            border: 1px solid ${colors.border} !important;
            border-radius: 0.5rem !important;
            box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.1), 0 4px 6px -2px rgba(0, 0, 0, 0.05) !important;
            color: ${colors.primary} !important;
            font-family: inherit !important;
          }
          
          .date-picker-calendar .react-datepicker__header {
            background-color: ${colors.surface} !important;
            border-bottom: 1px solid ${colors.border} !important;
            border-top-left-radius: 0.5rem !important;
            border-top-right-radius: 0.5rem !important;
            color: ${colors.primary} !important;
            padding: 0.5rem !important;
          }
          
          .date-picker-calendar .react-datepicker__current-month {
            color: ${colors.primary} !important;
            font-weight: 600 !important;
            margin-bottom: 0.5rem !important;
          }
          
          .date-picker-calendar .react-datepicker__day-name {
            color: ${colors.textSecondary} !important;
            font-weight: 500 !important;
            margin: 0.166rem !important;
            width: 2rem !important;
          }
          
          .date-picker-calendar .react-datepicker__day {
            color: ${colors.primary} !important;
            margin: 0.166rem !important;
            width: 2rem !important;
            line-height: 2rem !important;
            text-align: center !important;
            cursor: pointer !important;
            border-radius: 0.25rem !important;
            transition: all 0.15s ease-in-out !important;
          }
          
          .date-picker-calendar .react-datepicker__day:hover {
            background-color: ${colors.surface} !important;
            color: ${colors.primary} !important;
          }
          
          .date-picker-calendar .react-datepicker__day--selected {
            background-color: ${colors.primary} !important;
            color: white !important;
          }
          
          .date-picker-calendar .react-datepicker__day--selected:hover {
            background-color: ${colors.primary} !important;
            opacity: 0.9 !important;
          }
          
          .date-picker-calendar .react-datepicker__day--today {
            font-weight: 600 !important;
            color: ${colors.primary} !important;
          }
          
          .date-picker-calendar .react-datepicker__day--outside-month {
            color: ${colors.textSecondary} !important;
          }
          
          .date-picker-calendar .react-datepicker__day--disabled {
            color: ${colors.textSecondary} !important;
            cursor: not-allowed !important;
          }
          
          .date-picker-calendar .react-datepicker__navigation {
            background: none !important;
            border: none !important;
            cursor: pointer !important;
            padding: 0.5rem !important;
            color: ${colors.textSecondary} !important;
          }
          
          .date-picker-calendar .react-datepicker__navigation:hover {
            color: ${colors.primary} !important;
          }
          
          .date-picker-calendar .react-datepicker__navigation--previous {
            left: 0.5rem !important;
          }
          
          .date-picker-calendar .react-datepicker__navigation--next {
            right: 0.5rem !important;
          }
          
          .date-picker-calendar .react-datepicker__month-dropdown,
          .date-picker-calendar .react-datepicker__year-dropdown {
            background-color: ${colors.background} !important;
            border: 1px solid ${colors.border} !important;
            border-radius: 0.25rem !important;
            box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1) !important;
            color: ${colors.primary} !important;
          }
          
          .date-picker-calendar .react-datepicker__month-dropdown-container--select,
          .date-picker-calendar .react-datepicker__year-dropdown-container--select {
            display: inline-block !important;
            margin: 0 0.5rem !important;
          }
          
          .date-picker-calendar .react-datepicker__month-dropdown-container--select select,
          .date-picker-calendar .react-datepicker__year-dropdown-container--select select {
            background-color: ${colors.background} !important;
            border: 1px solid ${colors.border} !important;
            border-radius: 0.25rem !important;
            color: ${colors.primary} !important;
            padding: 0.25rem 0.5rem !important;
            font-size: 0.875rem !important;
          }
          
          .date-picker-calendar .react-datepicker__time-container {
            border-left: 1px solid ${colors.border} !important;
          }
          
          .date-picker-calendar .react-datepicker__time-list-item {
            color: ${colors.primary} !important;
            padding: 0.5rem !important;
          }
          
          .date-picker-calendar .react-datepicker__time-list-item:hover {
            background-color: ${colors.surface} !important;
          }
          
          .date-picker-calendar .react-datepicker__time-list-item--selected {
            background-color: ${colors.primary} !important;
            color: white !important;
          }
        `
      }} />
    </div>
  );
};

export default DatePicker;