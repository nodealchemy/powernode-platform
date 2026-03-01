import React, { useState } from 'react';
import { DatePicker } from '@/shared/components/ui/DatePicker';

interface DateRangePickerProps {
  startDate: Date | null;
  endDate: Date | null;
  onStartDateChange: (date: Date | null) => void;
  onEndDateChange: (date: Date | null) => void;
  onRangeChange?: (range: { startDate: Date; endDate: Date }) => void;
  startPlaceholder?: string;
  endPlaceholder?: string;
  dateFormat?: string;
  showTimeSelect?: boolean;
  disabled?: boolean;
  className?: string;
  showPresets?: boolean;
  minDate?: Date;
  maxDate?: Date;
}

interface DateRangePreset {
  label: string;
  value: string;
  getDateRange: () => { startDate: Date; endDate: Date };
}

export const DateRangePicker: React.FC<DateRangePickerProps> = ({
  startDate,
  endDate,
  onStartDateChange,
  onEndDateChange,
  onRangeChange,
  startPlaceholder = 'Start date',
  endPlaceholder = 'End date',
  dateFormat = 'MM/dd/yyyy',
  showTimeSelect = false,
  disabled = false,
  className = '',
  showPresets = true,
  minDate,
  maxDate,
}) => {
  const [showCustomInputs, setShowCustomInputs] = useState(false);

  const presets: DateRangePreset[] = [
    {
      label: 'Today',
      value: 'today',
      getDateRange: () => {
        const today = new Date();
        return { startDate: today, endDate: today };
      },
    },
    {
      label: 'Last 7 days',
      value: '7d',
      getDateRange: () => {
        const today = new Date();
        const lastWeek = new Date(today.getTime() - 7 * 24 * 60 * 60 * 1000);
        return { startDate: lastWeek, endDate: today };
      },
    },
    {
      label: 'Last 30 days',
      value: '30d',
      getDateRange: () => {
        const today = new Date();
        const lastMonth = new Date(today.getTime() - 30 * 24 * 60 * 60 * 1000);
        return { startDate: lastMonth, endDate: today };
      },
    },
    {
      label: 'Last 90 days',
      value: '90d',
      getDateRange: () => {
        const today = new Date();
        const last90Days = new Date(today.getTime() - 90 * 24 * 60 * 60 * 1000);
        return { startDate: last90Days, endDate: today };
      },
    },
    {
      label: 'Last 6 months',
      value: '6m',
      getDateRange: () => {
        const today = new Date();
        const last6Months = new Date(today.getFullYear(), today.getMonth() - 6, today.getDate());
        return { startDate: last6Months, endDate: today };
      },
    },
    {
      label: 'Last year',
      value: '1y',
      getDateRange: () => {
        const today = new Date();
        const lastYear = new Date(today.getFullYear() - 1, today.getMonth(), today.getDate());
        return { startDate: lastYear, endDate: today };
      },
    },
    {
      label: 'This month',
      value: 'thisMonth',
      getDateRange: () => {
        const today = new Date();
        const startOfMonth = new Date(today.getFullYear(), today.getMonth(), 1);
        return { startDate: startOfMonth, endDate: today };
      },
    },
    {
      label: 'Last month',
      value: 'lastMonth',
      getDateRange: () => {
        const today = new Date();
        const lastMonth = new Date(today.getFullYear(), today.getMonth() - 1, 1);
        const endOfLastMonth = new Date(today.getFullYear(), today.getMonth(), 0);
        return { startDate: lastMonth, endDate: endOfLastMonth };
      },
    },
  ];

  const handlePresetClick = (preset: DateRangePreset) => {
    const { startDate: newStartDate, endDate: newEndDate } = preset.getDateRange();
    
    if (onRangeChange) {
      onRangeChange({ startDate: newStartDate, endDate: newEndDate });
    } else {
      onStartDateChange(newStartDate);
      onEndDateChange(newEndDate);
    }
    
    setShowCustomInputs(false);
  };

  const handleStartDateChange = (date: Date | null) => {
    onStartDateChange(date);
    // If end date is before start date, clear it
    if (date && endDate && date > endDate) {
      onEndDateChange(null);
    }
  };

  const handleEndDateChange = (date: Date | null) => {
    onEndDateChange(date);
    // If start date is after end date, clear it
    if (date && startDate && startDate > date) {
      onStartDateChange(null);
    }
  };

  const formatDateRange = () => {
    if (!startDate || !endDate) return null;
    
    const formatOptions: Intl.DateTimeFormatOptions = {
      month: 'short',
      day: 'numeric',
      year: startDate.getFullYear() !== new Date().getFullYear() ? 'numeric' : undefined,
    };

    const start = startDate.toLocaleDateString('en-US', formatOptions);
    const end = endDate.toLocaleDateString('en-US', formatOptions);
    
    if (start === end) {
      return start;
    }
    
    return `${start} - ${end}`;
  };

  const getDaysDifference = () => {
    if (!startDate || !endDate) return null;
    const timeDiff = endDate.getTime() - startDate.getTime();
    const daysDiff = Math.ceil(timeDiff / (1000 * 60 * 60 * 24)) + 1; // +1 to include both start and end dates
    return daysDiff;
  };

  const getActivePreset = () => {
    if (!startDate || !endDate) return null;
    
    return presets.find(preset => {
      const { startDate: presetStart, endDate: presetEnd } = preset.getDateRange();
      return (
        Math.abs(startDate.getTime() - presetStart.getTime()) < 24 * 60 * 60 * 1000 &&
        Math.abs(endDate.getTime() - presetEnd.getTime()) < 24 * 60 * 60 * 1000
      );
    });
  };

  const activePreset = getActivePreset();

  return (
    <div className={`space-y-4 ${className}`}>
      {/* Selected Date Range Display */}
      {startDate && endDate && (
        <div className="bg-theme-interactive-primary bg-opacity-10 border border-theme-interactive-primary rounded-lg p-3">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm font-medium text-theme-interactive-primary">Selected Range</p>
              <p className="text-lg font-semibold text-theme-primary">{formatDateRange()}</p>
              <p className="text-xs text-theme-secondary">
                {getDaysDifference()} day{getDaysDifference() !== 1 ? 's' : ''}
              </p>
            </div>
            {activePreset && (
              <span className="px-2 py-1 bg-theme-interactive-primary text-white text-xs rounded-full">
                {activePreset.label}
              </span>
            )}
          </div>
        </div>
      )}

      {showPresets && (
        <div className="flex flex-wrap items-center gap-3">
          <div className="flex flex-wrap gap-2">
            {presets.map((preset) => {
              const isActive = activePreset?.value === preset.value;
              return (
                <button
                  key={preset.value}
                  onClick={() => handlePresetClick(preset)}
                  disabled={disabled}
                  className={`px-3 py-1 text-sm transition-all duration-200 ${
                    isActive
                      ? 'bg-theme-interactive-primary text-white border border-theme-interactive-primary'
                      : 'btn-theme btn-theme-secondary hover:btn-theme-primary'
                  }`}
                >
                  {preset.label}
                </button>
              );
            })}
            <button
              onClick={() => setShowCustomInputs(!showCustomInputs)}
              disabled={disabled}
              className="btn-theme btn-theme-outline px-3 py-1 text-sm"
            >
              {showCustomInputs ? 'Hide Custom' : 'Custom Range'}
            </button>
          </div>
        </div>
      )}

      {(showCustomInputs || !showPresets) && (
        <div className="flex flex-wrap items-center gap-4">
          <div className="flex items-center gap-2">
            <label className="text-sm font-medium text-theme-secondary">From:</label>
            <DatePicker
              selected={startDate}
              onChange={handleStartDateChange}
              placeholderText={startPlaceholder}
              dateFormat={dateFormat}
              showTimeSelect={showTimeSelect}
              maxDate={endDate || maxDate}
              minDate={minDate}
              disabled={disabled}
              className="w-36"
              showMonthDropdown
              showYearDropdown
              dropdownMode="select"
            />
          </div>

          <div className="flex items-center gap-2">
            <label className="text-sm font-medium text-theme-secondary">To:</label>
            <DatePicker
              selected={endDate}
              onChange={handleEndDateChange}
              placeholderText={endPlaceholder}
              dateFormat={dateFormat}
              showTimeSelect={showTimeSelect}
              minDate={startDate || minDate}
              maxDate={maxDate}
              disabled={disabled}
              className="w-36"
              showMonthDropdown
              showYearDropdown
              dropdownMode="select"
            />
          </div>
        </div>
      )}

      {/* Date Range Summary */}
      {startDate && endDate && (
        <div className="flex items-center gap-4 text-sm text-theme-secondary bg-theme-background-secondary px-3 py-2 rounded-md">
          <span className="font-medium">Selected range:</span>
          <span className="text-theme-primary font-medium">{formatDateRange()}</span>
          <span className="text-theme-tertiary">
            ({getDaysDifference()} day{getDaysDifference() !== 1 ? 's' : ''})
          </span>
        </div>
      )}
    </div>
  );
};

export default DateRangePicker;