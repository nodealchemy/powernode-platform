import React from 'react';
import { DateRangeFilter } from '@enterprise/features/business/analytics/components/DateRangeFilter';

interface ReportTemplate {
  id: string;
  name: string;
  description: string;
  category: string;
  icon: string;
  formats: string[];
  parameters: {
    requires_date_range: boolean;
    filters?: Array<{
      name: string;
      type: 'text' | 'select' | 'multi-select' | 'boolean';
      label: string;
      options?: string[];
      required?: boolean;
    }>;
  };
}

interface ReportRequestModalProps {
  isOpen: boolean;
  onClose: () => void;
  selectedTemplate: ReportTemplate;
  reportConfig: {
    name: string;
    format: 'csv' | 'pdf' | 'xlsx' | 'json';
    filters: Record<string, unknown>;
  };
  setReportConfig: React.Dispatch<React.SetStateAction<{
    name: string;
    format: 'csv' | 'pdf' | 'xlsx' | 'json';
    filters: Record<string, unknown>;
  }>>;
  dateRange: { startDate: Date; endDate: Date };
  setDateRange: (range: { startDate: Date; endDate: Date }) => void;
  isSubmitting: boolean;
  onSubmit: () => void;
}

export const ReportRequestModal: React.FC<ReportRequestModalProps> = ({
  isOpen,
  onClose,
  selectedTemplate,
  reportConfig,
  setReportConfig,
  dateRange,
  setDateRange,
  isSubmitting,
  onSubmit
}) => {
  if (!isOpen) return null;

  return (
    <>
      <div className="fixed inset-0 bg-theme-overlay z-40" onClick={onClose} />
      <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div className="card-theme w-full max-w-lg max-h-screen overflow-y-auto relative z-10">
          <div className="flex items-center justify-between p-6 border-b border-theme">
            <h2 className="text-lg font-semibold text-theme-primary">
              Generate {selectedTemplate.name}
            </h2>
            <button
              onClick={onClose}
              className="text-theme-secondary hover:text-theme-primary"
            >
              X
            </button>
          </div>

          <div className="p-6 space-y-4">
            {/* Report Name */}
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">
                Report Name
              </label>
              <input
                type="text"
                value={reportConfig.name}
                onChange={(e) => setReportConfig(prev => ({ ...prev, name: e.target.value }))}
                className="input-theme w-full"
                placeholder="Enter report name"
              />
            </div>

            {/* Format Selection */}
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">
                Format
              </label>
              <select
                value={reportConfig.format}
                onChange={(e) => setReportConfig(prev => ({
                  ...prev,
                  format: e.target.value as 'csv' | 'pdf' | 'xlsx' | 'json'
                }))}
                className="input-theme w-full"
              >
                {selectedTemplate.formats.map((format) => (
                  <option key={format} value={format}>
                    {format.toUpperCase()}
                  </option>
                ))}
              </select>
            </div>

            {/* Date Range */}
            {selectedTemplate.parameters.requires_date_range && (
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-1">
                  Date Range
                </label>
                <DateRangeFilter
                  dateRange={dateRange}
                  onChange={setDateRange}
                />
              </div>
            )}

            {/* Additional Filters */}
            {selectedTemplate.parameters.filters?.map((filter) => (
              <div key={filter.name}>
                <label className="block text-sm font-medium text-theme-primary mb-1">
                  {filter.label}
                </label>
                {filter.type === 'text' && (
                  <input
                    type="text"
                    className="input-theme w-full"
                    onChange={(e) => setReportConfig(prev => ({
                      ...prev,
                      filters: { ...prev.filters, [filter.name]: e.target.value }
                    }))}
                  />
                )}
                {filter.type === 'select' && filter.options && (
                  <select
                    className="input-theme w-full"
                    onChange={(e) => setReportConfig(prev => ({
                      ...prev,
                      filters: { ...prev.filters, [filter.name]: e.target.value }
                    }))}
                  >
                    <option value="">Select {filter.label}</option>
                    {filter.options.map((option) => (
                      <option key={option} value={option}>
                        {option}
                      </option>
                    ))}
                  </select>
                )}
                {filter.type === 'boolean' && (
                  <label className="flex items-center">
                    <input
                      type="checkbox"
                      className="mr-2"
                      onChange={(e) => setReportConfig(prev => ({
                        ...prev,
                        filters: { ...prev.filters, [filter.name]: e.target.checked }
                      }))}
                    />
                    {filter.label}
                  </label>
                )}
              </div>
            ))}
          </div>

          <div className="flex items-center justify-end space-x-3 p-6 border-t border-theme">
            <button
              onClick={onClose}
              className="btn-theme btn-theme-secondary"
              disabled={isSubmitting}
            >
              Cancel
            </button>
            <button
              onClick={onSubmit}
              className="btn-theme btn-theme-primary"
              disabled={isSubmitting || !reportConfig.name}
            >
              {isSubmitting ? 'Generating...' : 'Generate Report'}
            </button>
          </div>
        </div>
      </div>
    </>
  );
};
