import React, { useState, useEffect, useCallback, useMemo } from 'react';
import { DatePicker } from '@/shared/components/ui/DatePicker';
import { Button } from '@/shared/components/ui/Button';
import { Calendar, ChevronDown, RotateCcw, ChevronLeft, ChevronRight } from 'lucide-react';

interface DateRangeFilterProps {
  dateRange: {
    startDate: Date;
    endDate: Date;
  };
  onChange: (dateRange: { startDate: Date; endDate: Date }) => void;
}

interface DateRangePreset {
  label: string;
  value: string;
  getDateRange: () => { startDate: Date; endDate: Date };
}

export const DateRangeFilter: React.FC<DateRangeFilterProps> = ({ dateRange, onChange }) => {
  const [showDropdown, setShowDropdown] = useState(false);
  const [showCustomInputs, setShowCustomInputs] = useState(false);

  // Define presets first to avoid use-before-define warnings
  const presets: DateRangePreset[] = useMemo(() => [
    {
      label: 'Today',
      value: 'today',
      getDateRange: () => {
        const today = new Date();
        return { startDate: today, endDate: today };
      },
    },
    {
      label: 'Yesterday',
      value: 'yesterday',
      getDateRange: () => {
        const yesterday = new Date();
        yesterday.setDate(yesterday.getDate() - 1);
        return { startDate: yesterday, endDate: yesterday };
      },
    },
    {
      label: 'Last 7 days',
      value: '7d',
      getDateRange: () => {
        const today = new Date();
        const lastWeek = new Date(today.getTime() - 6 * 24 * 60 * 60 * 1000);
        return { startDate: lastWeek, endDate: today };
      },
    },
    {
      label: 'Last 30 days',
      value: '30d',
      getDateRange: () => {
        const today = new Date();
        const lastMonth = new Date(today.getTime() - 29 * 24 * 60 * 60 * 1000);
        return { startDate: lastMonth, endDate: today };
      },
    },
    {
      label: 'Last 90 days',
      value: '90d',
      getDateRange: () => {
        const today = new Date();
        const last90Days = new Date(today.getTime() - 89 * 24 * 60 * 60 * 1000);
        return { startDate: last90Days, endDate: today };
      },
    },
    {
      label: 'This week',
      value: 'thisWeek',
      getDateRange: () => {
        const today = new Date();
        const startOfWeek = new Date(today);
        startOfWeek.setDate(today.getDate() - today.getDay());
        return { startDate: startOfWeek, endDate: today };
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
    {
      label: 'This quarter',
      value: 'thisQuarter',
      getDateRange: () => {
        const today = new Date();
        const quarter = Math.floor(today.getMonth() / 3);
        const startOfQuarter = new Date(today.getFullYear(), quarter * 3, 1);
        return { startDate: startOfQuarter, endDate: today };
      },
    },
    {
      label: 'Last quarter',
      value: 'lastQuarter',
      getDateRange: () => {
        const today = new Date();
        const currentQuarter = Math.floor(today.getMonth() / 3);
        const lastQuarter = currentQuarter === 0 ? 3 : currentQuarter - 1;
        const year = currentQuarter === 0 ? today.getFullYear() - 1 : today.getFullYear();
        const startOfLastQuarter = new Date(year, lastQuarter * 3, 1);
        const endOfLastQuarter = new Date(year, (lastQuarter + 1) * 3, 0);
        return { startDate: startOfLastQuarter, endDate: endOfLastQuarter };
      },
    },
    {
      label: 'This year',
      value: 'thisYear',
      getDateRange: () => {
        const today = new Date();
        const startOfYear = new Date(today.getFullYear(), 0, 1);
        return { startDate: startOfYear, endDate: today };
      },
    },
    {
      label: 'Last year',
      value: 'lastYear',
      getDateRange: () => {
        const today = new Date();
        const startOfLastYear = new Date(today.getFullYear() - 1, 0, 1);
        const endOfLastYear = new Date(today.getFullYear() - 1, 11, 31);
        return { startDate: startOfLastYear, endDate: endOfLastYear };
      },
    },
    {
      label: 'Last 6 months',
      value: '6m',
      getDateRange: () => {
        const today = new Date();
        const last6Months = new Date(today.getFullYear(), today.getMonth() - 6, today.getDate() + 1);
        return { startDate: last6Months, endDate: today };
      },
    },
    {
      label: 'Last 12 months',
      value: '12m',
      getDateRange: () => {
        const today = new Date();
        const lastYear = new Date(today.getFullYear(), today.getMonth() - 12, today.getDate() + 1);
        return { startDate: lastYear, endDate: today };
      },
    }
  ], []);

  // Define handlePresetClick before useEffect to avoid use-before-define warning
  const handlePresetClick = useCallback((preset: DateRangePreset) => {
    const { startDate, endDate } = preset.getDateRange();
    onChange({ startDate, endDate });
    setShowDropdown(false);
    setShowCustomInputs(false);
  }, [onChange]);

  // Keyboard shortcuts
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.ctrlKey || e.metaKey) {
        switch (e.key) {
          case '1': {
            e.preventDefault();
            const preset1 = presets.find(p => p.value === '7d');
            if (preset1) handlePresetClick(preset1);
            break;
          }
          case '2': {
            e.preventDefault();
            const preset2 = presets.find(p => p.value === '30d');
            if (preset2) handlePresetClick(preset2);
            break;
          }
          case '3': {
            e.preventDefault();
            const preset3 = presets.find(p => p.value === 'thisMonth');
            if (preset3) handlePresetClick(preset3);
            break;
          }
          case '4': {
            e.preventDefault();
            const preset4 = presets.find(p => p.value === 'thisQuarter');
            if (preset4) handlePresetClick(preset4);
            break;
          }
        }
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [handlePresetClick, presets]);

  const shiftDateRange = (direction: 'prev' | 'next') => {
    const days = getDaysInRange();
    const shift = direction === 'prev' ? -days : days;
    
    const newStartDate = new Date(dateRange.startDate);
    const newEndDate = new Date(dateRange.endDate);
    
    newStartDate.setDate(newStartDate.getDate() + shift);
    newEndDate.setDate(newEndDate.getDate() + shift);
    
    onChange({ startDate: newStartDate, endDate: newEndDate });
  };

  const resetToDefault = () => {
    const defaultPreset = presets.find(p => p.value === '30d');
    if (defaultPreset) {
      handlePresetClick(defaultPreset);
    }
  };

  // Presets and handlePresetClick already defined above

  const handleStartDateChange = (startDate: Date | null) => {
    if (startDate) {
      onChange({
        startDate,
        endDate: dateRange.endDate
      });
    }
  };

  const handleEndDateChange = (endDate: Date | null) => {
    if (endDate) {
      onChange({
        startDate: dateRange.startDate,
        endDate
      });
    }
  };

  const formatDateRange = () => {
    const formatOptions: Intl.DateTimeFormatOptions = {
      month: 'short',
      day: 'numeric',
      year: dateRange.startDate.getFullYear() !== new Date().getFullYear() ? 'numeric' : undefined,
    };

    const start = dateRange.startDate.toLocaleDateString('en-US', formatOptions);
    const end = dateRange.endDate.toLocaleDateString('en-US', formatOptions);
    
    if (start === end) {
      return start;
    }
    
    return `${start} - ${end}`;
  };

  const getDaysInRange = () => {
    const timeDiff = dateRange.endDate.getTime() - dateRange.startDate.getTime();
    const daysDiff = Math.ceil(timeDiff / (1000 * 60 * 60 * 24));
    
    // Always add 1 to include both start and end dates
    return daysDiff + 1;
  };

  const getDateRangeInfo = () => {
    const days = getDaysInRange();
    const activePresetLabel = activePreset?.label;
    
    if (activePresetLabel) {
      return `${activePresetLabel} (${days} day${days !== 1 ? 's' : ''})`;
    }
    
    return `${formatDateRange()} (${days} day${days !== 1 ? 's' : ''})`;
  };

  const getActivePreset = () => {
    return presets.find(preset => {
      const { startDate: presetStart, endDate: presetEnd } = preset.getDateRange();
      return (
        Math.abs(dateRange.startDate.getTime() - presetStart.getTime()) < 24 * 60 * 60 * 1000 &&
        Math.abs(dateRange.endDate.getTime() - presetEnd.getTime()) < 24 * 60 * 60 * 1000
      );
    });
  };

  const activePreset = getActivePreset();

  return (
    <div className="relative">
      {/* Date Range Controls */}
      <div className="flex items-center space-x-2">
        {/* Previous Period Button */}
        <Button
          onClick={() => shiftDateRange('prev')}
          variant="outline"
          size="sm"
          iconOnly
          title="Previous period"
        >
          <ChevronLeft className="h-4 w-4" />
        </Button>

        {/* Main Date Range Button */}
        <Button
          onClick={() => setShowDropdown(!showDropdown)}
          variant="outline"
          size="sm"
          className="min-w-0"
        >
          <Calendar className="h-4 w-4 mr-2" />
          <span className="whitespace-nowrap">
            {getDateRangeInfo()}
          </span>
          <ChevronDown className="h-4 w-4 ml-2" />
        </Button>

        {/* Next Period Button */}
        <Button
          onClick={() => shiftDateRange('next')}
          size="sm"
          iconOnly
          title="Next period"
        >
          <ChevronRight className="h-4 w-4" />
        </Button>

        {/* Reset Button */}
        <Button
          onClick={resetToDefault}
          variant="outline"
          size="sm"
          iconOnly
          title="Reset to Last 30 days"
        >
          <RotateCcw className="h-4 w-4" />
        </Button>
      </div>

      {/* Dropdown */}
      {showDropdown && (
        <>
          {/* Backdrop */}
          <div 
            className="fixed inset-0 z-10" 
            onClick={() => setShowDropdown(false)}
          />
          
          {/* Dropdown Content */}
          <div className="absolute top-full left-8 mt-1 w-72 bg-theme-surface border border-theme rounded-lg shadow-lg z-20">
            <div className="p-3">
              <h4 className="text-sm font-medium text-theme-primary mb-3">Quick Date Ranges</h4>
              
              {/* Recent Dates */}
              <div className="mb-4">
                <h5 className="text-xs font-medium text-theme-secondary mb-2 uppercase tracking-wide">Recent</h5>
                <div className="space-y-1">
                  {presets.slice(0, 2).map((preset) => {
                    return (
                      <Button
                        key={preset.value}
                        onClick={() => handlePresetClick(preset)}
                        size="sm"
                        className="w-full justify-start"
                      >
                        {preset.label}
                      </Button>
                    );
                  })}
                </div>
              </div>

              {/* Rolling Periods */}
              <div className="mb-4">
                <h5 className="text-xs font-medium text-theme-secondary mb-2 uppercase tracking-wide">Rolling Periods</h5>
                <div className="space-y-1">
                  {presets.slice(2, 5).map((preset, index) => {
                    const isActive = activePreset?.value === preset.value;
                    const shortcut = index === 0 ? 'Ctrl+1' : index === 1 ? 'Ctrl+2' : null;
                    return (
                      <Button
                        key={preset.value}
                        onClick={() => handlePresetClick(preset)}
                        variant={isActive ? 'primary' : 'ghost'}
                        size="sm"
                        className="w-full justify-between"
                      >
                        <span>{preset.label}</span>
                        {shortcut && (
                          <span className={`text-xs ${isActive ? 'text-white/70' : 'text-theme-tertiary'}`}>
                            {shortcut}
                          </span>
                        )}
                      </Button>
                    );
                  })}
                </div>
              </div>

              {/* Calendar Periods */}
              <div className="mb-4">
                <h5 className="text-xs font-medium text-theme-secondary mb-2 uppercase tracking-wide">Calendar Periods</h5>
                <div className="space-y-1">
                  {presets.slice(5, 12).map((preset, index) => {
                    const isActive = activePreset?.value === preset.value;
                    const shortcut = index === 2 ? 'Ctrl+3' : index === 4 ? 'Ctrl+4' : null; // This month and This quarter
                    return (
                      <Button
                        key={preset.value}
                        onClick={() => handlePresetClick(preset)}
                        variant={isActive ? 'primary' : 'ghost'}
                        size="sm"
                        className="w-full justify-between"
                      >
                        <span>{preset.label}</span>
                        {shortcut && (
                          <span className={`text-xs ${isActive ? 'text-white/70' : 'text-theme-tertiary'}`}>
                            {shortcut}
                          </span>
                        )}
                      </Button>
                    );
                  })}
                </div>
              </div>

              {/* Extended Periods */}
              <div className="mb-4">
                <h5 className="text-xs font-medium text-theme-secondary mb-2 uppercase tracking-wide">Extended Periods</h5>
                <div className="space-y-1">
                  {presets.slice(12).map((preset) => {
                    const isActive = activePreset?.value === preset.value;
                    return (
                      <Button
                        key={preset.value}
                        onClick={() => handlePresetClick(preset)}
                        variant={isActive ? 'primary' : 'ghost'}
                        size="sm"
                        className="w-full justify-start"
                      >
                        {preset.label}
                      </Button>
                    );
                  })}
                </div>
              </div>
              
              <hr className="my-3 border-theme" />
              
              <Button
                onClick={() => {
                  setShowCustomInputs(!showCustomInputs);
                  setShowDropdown(false);
                }}
                className="w-full justify-start font-medium"
              >
                📅 Custom Date Range
              </Button>

              {/* Help Section */}
              <div className="mt-3 pt-3 border-t border-theme">
                <div className="text-xs text-theme-tertiary space-y-1">
                  <div className="flex items-center justify-between">
                    <span>Navigation:</span>
                    <span className="font-mono">← / → arrows</span>
                  </div>
                  <div className="flex items-center justify-between">
                    <span>Reset:</span>
                    <span className="font-mono">⟲ button</span>
                  </div>
                  <div className="text-center mt-2 text-theme-tertiary/70">
                    Use keyboard shortcuts for quick access
                  </div>
                </div>
              </div>
            </div>
          </div>
        </>
      )}

      {/* Custom Date Inputs (shown when needed) */}
      {showCustomInputs && (
        <div className="mt-2 p-3 bg-theme-background-secondary border border-theme rounded-md">
          <div className="flex items-center gap-3">
            <div className="flex items-center gap-2">
              <label className="text-xs font-medium text-theme-secondary">From:</label>
              <DatePicker
                selected={dateRange.startDate}
                onChange={handleStartDateChange}
                placeholderText="Start date"
                dateFormat="MM/dd/yyyy"
                maxDate={dateRange.endDate || new Date()}
                className="w-28 text-xs"
                showMonthDropdown
                showYearDropdown
                dropdownMode="select"
              />
            </div>

            <div className="flex items-center gap-2">
              <label className="text-xs font-medium text-theme-secondary">To:</label>
              <DatePicker
                selected={dateRange.endDate}
                onChange={handleEndDateChange}
                placeholderText="End date"
                dateFormat="MM/dd/yyyy"
                minDate={dateRange.startDate}
                maxDate={new Date()}
                className="w-28 text-xs"
                showMonthDropdown
                showYearDropdown
                dropdownMode="select"
              />
            </div>
            
            <Button
              onClick={() => setShowCustomInputs(false)}
              variant="ghost"
              size="xs"
            >
              Done
            </Button>
          </div>
        </div>
      )}
    </div>
  );
};