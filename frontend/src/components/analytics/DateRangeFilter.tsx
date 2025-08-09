import React from 'react';

interface DateRangeFilterProps {
  dateRange: {
    startDate: Date;
    endDate: Date;
  };
  onChange: (dateRange: { startDate: Date; endDate: Date }) => void;
}

export const DateRangeFilter: React.FC<DateRangeFilterProps> = ({ dateRange, onChange }) => {
  const formatDateForInput = (date: Date) => {
    return date.toISOString().split('T')[0];
  };

  const handleStartDateChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const newStartDate = new Date(e.target.value);
    onChange({
      startDate: newStartDate,
      endDate: dateRange.endDate
    });
  };

  const handleEndDateChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const newEndDate = new Date(e.target.value);
    onChange({
      startDate: dateRange.startDate,
      endDate: newEndDate
    });
  };

  const handlePresetChange = (preset: string) => {
    const today = new Date();
    let startDate: Date;
    
    switch (preset) {
      case '7d':
        startDate = new Date(today.getTime() - 7 * 24 * 60 * 60 * 1000);
        break;
      case '30d':
        startDate = new Date(today.getTime() - 30 * 24 * 60 * 60 * 1000);
        break;
      case '90d':
        startDate = new Date(today.getTime() - 90 * 24 * 60 * 60 * 1000);
        break;
      case '6m':
        startDate = new Date(today.getFullYear(), today.getMonth() - 6, today.getDate());
        break;
      case '1y':
        startDate = new Date(today.getFullYear() - 1, today.getMonth(), today.getDate());
        break;
      case '2y':
        startDate = new Date(today.getFullYear() - 2, today.getMonth(), today.getDate());
        break;
      default:
        return;
    }

    onChange({
      startDate,
      endDate: today
    });
  };

  const presets = [
    { label: 'Last 7 days', value: '7d' },
    { label: 'Last 30 days', value: '30d' },
    { label: 'Last 90 days', value: '90d' },
    { label: 'Last 6 months', value: '6m' },
    { label: 'Last year', value: '1y' },
    { label: 'Last 2 years', value: '2y' }
  ];

  return (
    <div className="flex flex-wrap items-center gap-4">
      <div className="flex items-center space-x-2">
        <span className="text-sm font-medium text-theme-secondary">Date Range:</span>
      </div>
      
      {/* Quick Presets */}
      <div className="flex flex-wrap gap-2">
        {presets.map((preset) => (
          <button
            key={preset.value}
            onClick={() => handlePresetChange(preset.value)}
            className="btn-theme btn-theme-secondary px-3 py-1 text-sm"
          >
            {preset.label}
          </button>
        ))}
      </div>

      {/* Custom Date Inputs */}
      <div className="flex items-center space-x-2">
        <div className="flex items-center space-x-1">
          <label htmlFor="start-date" className="text-sm text-theme-secondary">From:</label>
          <input
            id="start-date"
            type="date"
            value={formatDateForInput(dateRange.startDate)}
            onChange={handleStartDateChange}
            max={formatDateForInput(dateRange.endDate)}
            className="input-theme px-3 py-1 text-sm"
          />
        </div>
        
        <div className="flex items-center space-x-1">
          <label htmlFor="end-date" className="text-sm text-theme-secondary">To:</label>
          <input
            id="end-date"
            type="date"
            value={formatDateForInput(dateRange.endDate)}
            onChange={handleEndDateChange}
            min={formatDateForInput(dateRange.startDate)}
            max={formatDateForInput(new Date())}
            className="input-theme px-3 py-1 text-sm"
          />
        </div>
      </div>

      {/* Date Range Summary */}
      <div className="text-sm text-theme-tertiary">
        {(() => {
          const daysDiff = Math.ceil((dateRange.endDate.getTime() - dateRange.startDate.getTime()) / (1000 * 60 * 60 * 24));
          return `${daysDiff} day${daysDiff !== 1 ? 's' : ''}`;
        })()}
      </div>
    </div>
  );
};