import React from 'react';

interface ExportOption {
  type: string;
  label: string;
  description: string;
  icon: string;
}

interface AnalyticsExportModalProps {
  isOpen: boolean;
  onClose: () => void;
  dateRange: { startDate: Date; endDate: Date };
  onExport: (format: 'csv' | 'pdf', reportType: string) => void;
}

const exportOptions: ExportOption[] = [
  { type: 'revenue', label: 'Revenue Analytics', description: 'MRR, ARR, growth trends', icon: '$' },
  { type: 'growth', label: 'Growth Analytics', description: 'Growth rates, new revenue', icon: '+' },
  { type: 'churn', label: 'Churn Analysis', description: 'Customer and revenue churn', icon: '-' },
  { type: 'customers', label: 'Customer Analytics', description: 'Customer growth, ARPU, LTV', icon: 'U' },
  { type: 'cohorts', label: 'Cohort Analysis', description: 'Customer retention by cohort', icon: 'C' },
  { type: 'all', label: 'Complete Report', description: 'All analytics data', icon: 'A' }
];

export const AnalyticsExportModal: React.FC<AnalyticsExportModalProps> = ({
  isOpen,
  onClose,
  dateRange,
  onExport
}) => {
  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 overflow-y-auto">
      <div className="flex items-end justify-center min-h-screen pt-4 px-4 pb-20 text-center sm:block sm:p-0">
        {/* Backdrop */}
        <div
          className="fixed inset-0 bg-black bg-opacity-50 transition-opacity"
          onClick={onClose}
        />

        {/* Modal */}
        <div className="inline-block align-bottom bg-theme-surface rounded-lg px-4 pt-5 pb-4 text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-2xl sm:w-full sm:p-6 relative z-10">
          <div className="w-full">
            <div className="flex justify-between items-center mb-4">
              <h3 className="text-lg leading-6 font-medium text-theme-primary">
                Export Analytics Data
              </h3>
              <button
                onClick={onClose}
                className="text-theme-tertiary hover:text-theme-secondary"
              >
                X
              </button>
            </div>

            <p className="text-sm text-theme-secondary mb-6">
              Export data from {dateRange.startDate.toLocaleDateString()} to {dateRange.endDate.toLocaleDateString()}
            </p>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 mb-6">
              {exportOptions.map((option) => (
                <div key={option.type} className="border border-theme rounded-lg p-4">
                  <div className="flex items-start space-x-3 mb-3">
                    <span className="text-lg w-6 h-6 flex items-center justify-center bg-theme-background-tertiary rounded">
                      {option.icon}
                    </span>
                    <div className="flex-1 min-w-0">
                      <h4 className="text-sm font-medium text-theme-primary">{option.label}</h4>
                      <p className="text-xs text-theme-tertiary">{option.description}</p>
                    </div>
                  </div>

                  <div className="flex space-x-2">
                    <button
                      onClick={() => onExport('csv', option.type)}
                      className="flex-1 px-3 py-2 text-xs bg-theme-success-background text-theme-success rounded hover:bg-theme-success-background-hover"
                    >
                      CSV
                    </button>
                    <button
                      onClick={() => onExport('pdf', option.type)}
                      className="flex-1 px-3 py-2 text-xs bg-theme-error-background text-theme-error rounded hover:bg-theme-error-background-hover"
                    >
                      PDF
                    </button>
                  </div>
                </div>
              ))}
            </div>

            <div className="bg-theme-background-secondary p-3 rounded-lg">
              <div className="flex items-start text-xs text-theme-tertiary">
                <span className="text-lg mr-2">i</span>
                <div>
                  <p>CSV exports include raw data for further analysis.</p>
                  <p className="mt-1">PDF reports include formatted charts and summaries.</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
