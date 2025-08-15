import React from 'react';
import { DateRangePicker } from '../common/DateRangePicker';

interface DateRangeFilterProps {
  dateRange: {
    startDate: Date;
    endDate: Date;
  };
  onChange: (dateRange: { startDate: Date; endDate: Date }) => void;
}

export const DateRangeFilter: React.FC<DateRangeFilterProps> = ({ dateRange, onChange }) => {
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

  const handleRangeChange = (newRange: { startDate: Date; endDate: Date }) => {
    onChange(newRange);
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center space-x-2">
        <span className="text-sm font-medium text-theme-secondary">Analytics Date Range:</span>
      </div>
      
      <DateRangePicker
        startDate={dateRange.startDate}
        endDate={dateRange.endDate}
        onStartDateChange={handleStartDateChange}
        onEndDateChange={handleEndDateChange}
        onRangeChange={handleRangeChange}
        maxDate={new Date()}
        showPresets={true}
        className="analytics-date-range"
      />
    </div>
  );
};