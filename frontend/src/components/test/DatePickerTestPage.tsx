import React, { useState } from 'react';
import { DatePicker } from '../common/DatePicker';
import { DateRangePicker } from '../common/DateRangePicker';

export const DatePickerTestPage: React.FC = () => {
  const [singleDate, setSingleDate] = useState<Date | null>(new Date());
  const [birthDate, setBirthDate] = useState<Date | null>(null);
  const [startDate, setStartDate] = useState<Date | null>(new Date());
  const [endDate, setEndDate] = useState<Date | null>(new Date(Date.now() + 7 * 24 * 60 * 60 * 1000));
  const [dateTimeValue, setDateTimeValue] = useState<Date | null>(new Date());

  return (
    <div className="max-w-6xl mx-auto p-8 space-y-12">
      <div>
        <h1 className="text-3xl font-bold text-theme-primary mb-6">Date Picker Components Test</h1>
        <p className="text-theme-secondary mb-8">
          Testing all date picker components with different configurations and use cases.
        </p>
      </div>

      {/* Basic Date Picker */}
      <div className="card-theme p-6">
        <h2 className="text-xl font-semibold text-theme-primary mb-4">Basic Date Picker</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div>
            <label className="label-theme">Select Date</label>
            <DatePicker
              selected={singleDate}
              onChange={setSingleDate}
              placeholderText="Choose a date"
              className="w-full"
            />
            <p className="text-sm text-theme-secondary mt-2">
              Selected: {singleDate ? singleDate.toLocaleDateString() : 'None'}
            </p>
          </div>

          <div>
            <label className="label-theme">Birth Date (with restrictions)</label>
            <DatePicker
              selected={birthDate}
              onChange={setBirthDate}
              dateFormat="MM/dd/yyyy"
              maxDate={new Date()}
              showYearDropdown
              showMonthDropdown
              dropdownMode="select"
              placeholderText="Select birth date"
              className="w-full"
              isClearable
            />
            <p className="text-sm text-theme-secondary mt-2">
              Selected: {birthDate ? birthDate.toLocaleDateString() : 'None'}
            </p>
          </div>
        </div>
      </div>

      {/* Date Time Picker */}
      <div className="card-theme p-6">
        <h2 className="text-xl font-semibold text-theme-primary mb-4">Date Time Picker</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div>
            <label className="label-theme">Appointment Date & Time</label>
            <DatePicker
              selected={dateTimeValue}
              onChange={setDateTimeValue}
              showTimeSelect
              timeFormat="HH:mm"
              timeIntervals={15}
              dateFormat="MM/dd/yyyy HH:mm"
              placeholderText="Select date and time"
              className="w-full"
            />
            <p className="text-sm text-theme-secondary mt-2">
              Selected: {dateTimeValue ? dateTimeValue.toLocaleString() : 'None'}
            </p>
          </div>
        </div>
      </div>

      {/* Date Range Picker */}
      <div className="card-theme p-6">
        <h2 className="text-xl font-semibold text-theme-primary mb-4">Date Range Picker</h2>
        <div className="space-y-6">
          <div>
            <label className="label-theme">Select Date Range</label>
            <DateRangePicker
              startDate={startDate}
              endDate={endDate}
              onStartDateChange={setStartDate}
              onEndDateChange={setEndDate}
              showPresets={true}
              className="date-range-test"
            />
            <div className="mt-4 p-3 bg-theme-background-secondary rounded">
              <p className="text-sm text-theme-secondary">
                Selected Range: {startDate ? startDate.toLocaleDateString() : 'None'} to {endDate ? endDate.toLocaleDateString() : 'None'}
              </p>
              {startDate && endDate && (
                <p className="text-sm text-theme-secondary">
                  Duration: {Math.ceil((endDate.getTime() - startDate.getTime()) / (1000 * 60 * 60 * 24))} days
                </p>
              )}
            </div>
          </div>
        </div>
      </div>

      {/* Form Integration Test */}
      <div className="card-theme p-6">
        <h2 className="text-xl font-semibold text-theme-primary mb-4">Form Integration Test</h2>
        <form className="space-y-4">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <label className="label-theme">Event Start Date *</label>
              <DatePicker
                selected={startDate}
                onChange={setStartDate}
                dateFormat="MM/dd/yyyy"
                minDate={new Date()}
                required
                className="w-full"
              />
            </div>
            <div>
              <label className="label-theme">Event End Date *</label>
              <DatePicker
                selected={endDate}
                onChange={setEndDate}
                dateFormat="MM/dd/yyyy"
                minDate={startDate || new Date()}
                required
                className="w-full"
              />
            </div>
          </div>
          <div className="flex justify-end space-x-3">
            <button type="button" className="btn-theme btn-theme-secondary">
              Cancel
            </button>
            <button type="submit" className="btn-theme btn-theme-primary">
              Create Event
            </button>
          </div>
        </form>
      </div>

      {/* Theme Integration Test */}
      <div className="card-theme p-6">
        <h2 className="text-xl font-semibold text-theme-primary mb-4">Theme Integration</h2>
        <p className="text-theme-secondary mb-4">
          All date pickers should automatically adapt to the current theme (light/dark mode).
        </p>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <DatePicker
            selected={null}
            onChange={() => {}}
            placeholderText="Light theme test"
            className="theme-light"
          />
          <DatePicker
            selected={null}
            onChange={() => {}}
            placeholderText="Dark theme test"
            className="theme-dark"
          />
          <DatePicker
            selected={null}
            onChange={() => {}}
            placeholderText="System theme test"
          />
        </div>
      </div>
    </div>
  );
};

export default DatePickerTestPage;