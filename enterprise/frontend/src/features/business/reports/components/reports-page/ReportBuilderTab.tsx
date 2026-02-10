import React from 'react';
import { DateRangeFilter } from '@/features/business/analytics/components/DateRangeFilter';

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

interface ReportBuilderTabProps {
  builderStep: 1 | 2 | 3 | 4;
  setBuilderStep: (step: 1 | 2 | 3 | 4) => void;
  categorizedTemplates: Record<string, ReportTemplate[]>;
  selectedTemplate: ReportTemplate | null;
  setSelectedTemplate: (template: ReportTemplate | null) => void;
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

export const ReportBuilderTab: React.FC<ReportBuilderTabProps> = ({
  builderStep,
  setBuilderStep,
  categorizedTemplates,
  selectedTemplate,
  setSelectedTemplate,
  reportConfig,
  setReportConfig,
  dateRange,
  setDateRange,
  isSubmitting,
  onSubmit
}) => {
  return (
    <div className="space-y-6">
      {/* Builder Progress */}
      <div className="card-theme p-6">
        <div className="flex items-center justify-between mb-6">
          <h2 className="text-xl font-semibold text-theme-primary">Create Custom Report</h2>
          <div className="text-sm text-theme-secondary">Step {builderStep} of 4</div>
        </div>

        {/* Progress Bar */}
        <div className="w-full bg-theme-background-tertiary rounded-full h-2 mb-6">
          <div
            className="bg-theme-interactive-primary h-2 rounded-full transition-all duration-300"
            style={{ width: `${(builderStep / 4) * 100}%` }}
          ></div>
        </div>

        {/* Step 1: Select Report Type */}
        {builderStep === 1 && (
          <div className="space-y-6">
            <h3 className="text-lg font-medium text-theme-primary">Select Report Type</h3>
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              {Object.entries(categorizedTemplates).map(([category, categoryTemplates]) => (
                <div key={category} className="space-y-3">
                  <h4 className="font-medium text-theme-primary capitalize">{category}</h4>
                  {categoryTemplates.map((template) => (
                    <div
                      key={template.id}
                      className="p-4 border border-theme rounded-lg hover:bg-theme-surface cursor-pointer transition-colors"
                      onClick={() => {
                        setSelectedTemplate(template);
                        setBuilderStep(2);
                      }}
                    >
                      <div className="flex items-center space-x-3">
                        <span className="text-xl">{template.icon}</span>
                        <div>
                          <div className="font-medium text-theme-primary">{template.name}</div>
                          <div className="text-sm text-theme-secondary">{template.description}</div>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Step 2: Configure Parameters */}
        {builderStep === 2 && selectedTemplate && (
          <div className="space-y-6">
            <h3 className="text-lg font-medium text-theme-primary">Configure Parameters</h3>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">Report Name</label>
                <input
                  type="text"
                  value={reportConfig.name}
                  onChange={(e) => setReportConfig(prev => ({ ...prev, name: e.target.value }))}
                  className="input-theme w-full"
                  placeholder="Enter report name"
                />
              </div>
              {selectedTemplate.parameters.requires_date_range && (
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-2">Date Range</label>
                  <DateRangeFilter dateRange={dateRange} onChange={setDateRange} />
                </div>
              )}
            </div>
            {selectedTemplate.parameters.filters && (
              <div className="space-y-4">
                <h4 className="font-medium text-theme-primary">Filters</h4>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  {selectedTemplate.parameters.filters.map((filter) => (
                    <div key={filter.name}>
                      <label className="block text-sm font-medium text-theme-primary mb-1">{filter.label}</label>
                      {filter.type === 'text' && (
                        <input type="text" className="input-theme w-full" />
                      )}
                      {filter.type === 'select' && filter.options && (
                        <select className="input-theme w-full">
                          <option value="">Select {filter.label}</option>
                          {filter.options.map((option) => (
                            <option key={option} value={option}>{option}</option>
                          ))}
                        </select>
                      )}
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        )}

        {/* Step 3: Choose Format & Schedule */}
        {builderStep === 3 && (
          <div className="space-y-6">
            <h3 className="text-lg font-medium text-theme-primary">Choose Format & Schedule</h3>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">Output Format</label>
                <div className="space-y-2">
                  {selectedTemplate?.formats.map((format) => (
                    <label key={format} className="flex items-center">
                      <input
                        type="radio"
                        name="format"
                        value={format}
                        checked={reportConfig.format === format}
                        onChange={(e) => setReportConfig(prev => ({
                          ...prev,
                          format: e.target.value as 'csv' | 'pdf' | 'xlsx' | 'json'
                        }))}
                        className="mr-2"
                      />
                      <span className="text-theme-primary">{format.toUpperCase()}</span>
                    </label>
                  ))}
                </div>
              </div>
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">Schedule</label>
                <div className="space-y-2">
                  <label className="flex items-center">
                    <input type="radio" name="schedule" value="once" className="mr-2" defaultChecked />
                    <span className="text-theme-primary">Generate Once</span>
                  </label>
                  <label className="flex items-center">
                    <input type="radio" name="schedule" value="daily" className="mr-2" />
                    <span className="text-theme-primary">Daily</span>
                  </label>
                  <label className="flex items-center">
                    <input type="radio" name="schedule" value="weekly" className="mr-2" />
                    <span className="text-theme-primary">Weekly</span>
                  </label>
                  <label className="flex items-center">
                    <input type="radio" name="schedule" value="monthly" className="mr-2" />
                    <span className="text-theme-primary">Monthly</span>
                  </label>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* Step 4: Review & Generate */}
        {builderStep === 4 && (
          <div className="space-y-6">
            <h3 className="text-lg font-medium text-theme-primary">Review & Generate</h3>
            <div className="card-theme bg-theme-surface p-4">
              <h4 className="font-medium text-theme-primary mb-3">Report Summary</h4>
              <dl className="space-y-2 text-sm">
                <div className="flex justify-between">
                  <dt className="text-theme-secondary">Template:</dt>
                  <dd className="text-theme-primary font-medium">{selectedTemplate?.name}</dd>
                </div>
                <div className="flex justify-between">
                  <dt className="text-theme-secondary">Name:</dt>
                  <dd className="text-theme-primary">{reportConfig.name}</dd>
                </div>
                <div className="flex justify-between">
                  <dt className="text-theme-secondary">Format:</dt>
                  <dd className="text-theme-primary">{reportConfig.format.toUpperCase()}</dd>
                </div>
                {selectedTemplate?.parameters.requires_date_range && (
                  <div className="flex justify-between">
                    <dt className="text-theme-secondary">Date Range:</dt>
                    <dd className="text-theme-primary">
                      {dateRange.startDate.toLocaleDateString()} - {dateRange.endDate.toLocaleDateString()}
                    </dd>
                  </div>
                )}
              </dl>
            </div>
          </div>
        )}

        {/* Navigation */}
        <div className="flex items-center justify-between mt-8 pt-6 border-t border-theme">
          <button
            onClick={() => setBuilderStep(Math.max(1, builderStep - 1) as 1 | 2 | 3 | 4)}
            disabled={builderStep === 1}
            className="btn-theme btn-theme-secondary disabled:opacity-50"
          >
            &larr; Previous
          </button>

          {builderStep < 4 ? (
            <button
              onClick={() => setBuilderStep(Math.min(4, builderStep + 1) as 1 | 2 | 3 | 4)}
              disabled={builderStep === 2 && !selectedTemplate}
              className="btn-theme btn-theme-primary disabled:opacity-50"
            >
              Next &rarr;
            </button>
          ) : (
            <button
              onClick={onSubmit}
              disabled={isSubmitting || !reportConfig.name}
              className="btn-theme btn-theme-primary disabled:opacity-50"
            >
              {isSubmitting ? 'Generating...' : 'Generate Report'}
            </button>
          )}
        </div>
      </div>
    </div>
  );
};
