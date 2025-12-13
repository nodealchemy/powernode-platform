import React, { useState } from 'react';
import { Button } from '@/shared/components/ui/Button';

interface AnalyticsExportProps {
  dateRange: {
    startDate: Date;
    endDate: Date;
  };
  onExport: (format: 'csv' | 'pdf', reportType: string) => Promise<void>;
  onClose?: () => void;
  isOpen?: boolean;
}

export const AnalyticsExport: React.FC<AnalyticsExportProps> = ({ dateRange, onExport, onClose, isOpen: externalIsOpen }) => {
  const [internalIsOpen, setInternalIsOpen] = useState(false);
  const [isExporting, setIsExporting] = useState(false);
  
  // Use external isOpen if provided, otherwise use internal state
  const isOpen = externalIsOpen !== undefined ? externalIsOpen : internalIsOpen;

  const handleExport = async (format: 'csv' | 'pdf', reportType: string) => {
    try {
      setIsExporting(true);
      await onExport(format, reportType);
      if (onClose) {
        onClose();
      } else {
        setInternalIsOpen(false);
      }
    } catch (error) {
      // You could add a toast notification here
    } finally {
      setIsExporting(false);
    }
  };

  const exportOptions = [
    {
      type: 'revenue',
      label: 'Revenue Analytics',
      description: 'MRR, ARR, growth trends, and forecasting',
      icon: '💰'
    },
    {
      type: 'growth',
      label: 'Growth Analytics',
      description: 'Growth rates, new revenue, and expansion metrics',
      icon: '📈'
    },
    {
      type: 'churn',
      label: 'Churn Analysis',
      description: 'Customer and revenue churn rates and trends',
      icon: '📉'
    },
    {
      type: 'customers',
      label: 'Customer Analytics',
      description: 'Customer growth, ARPU, LTV, and segmentation',
      icon: '👥'
    },
    {
      type: 'cohorts',
      label: 'Cohort Analysis',
      description: 'Customer retention by cohort and tenure',
      icon: '🔄'
    },
    {
      type: 'all',
      label: 'Complete Report',
      description: 'All analytics data in a comprehensive report',
      icon: '📊'
    }
  ];

  return (
    <div className="relative">
      <Button variant="outline" onClick={() => onClose ? onClose() : setInternalIsOpen(!internalIsOpen)}
        disabled={isExporting}
        className="btn-theme btn-theme-primary flex items-center space-x-2 disabled:opacity-50 disabled:cursor-not-allowed"
      >
        <span className="text-lg">📥</span>
        <span className="text-sm font-medium">
          {isExporting ? 'Exporting...' : 'Export'}
        </span>
      </Button>

      {isOpen && (
        <>
          {/* Backdrop */}
          <div 
            className="fixed inset-0 z-40 bg-black bg-opacity-25" 
            onClick={() => onClose ? onClose() : setInternalIsOpen(false)}
          />
          
          {/* Export Menu */}
          <div className="absolute right-0 top-full mt-2 w-80 card-theme rounded-lg shadow-lg border-theme z-50">
            <div className="p-4 border-b border-theme">
              <h3 className="text-lg font-semibold text-theme-primary">Export Analytics</h3>
              <p className="text-sm text-theme-secondary mt-1">
                Export data from {dateRange.startDate.toLocaleDateString()} to {dateRange.endDate.toLocaleDateString()}
              </p>
            </div>
            
            <div className="p-4 space-y-4">
              {exportOptions.map((option) => (
                <div key={option.type} className="space-y-2">
                  <div className="flex items-start space-x-3">
                    <span className="text-lg">{option.icon}</span>
                    <div className="flex-1 min-w-0">
                      <h4 className="text-sm font-medium text-theme-primary">{option.label}</h4>
                      <p className="text-xs text-theme-tertiary">{option.description}</p>
                    </div>
                  </div>
                  
                  <div className="flex space-x-2 ml-8">
                    <Button variant="outline" onClick={() => handleExport('csv', option.type)}
                      disabled={isExporting}
                      className="px-3 py-1 text-xs bg-theme-success-background text-theme-success rounded hover:bg-theme-success-background-hover disabled:opacity-50 disabled:cursor-not-allowed"
                    >
                      CSV
                    </Button>
                    <Button variant="outline" onClick={() => handleExport('pdf', option.type)}
                      disabled={isExporting}
                      className="px-3 py-1 text-xs bg-theme-error-background text-theme-error rounded hover:bg-theme-error-background-hover disabled:opacity-50 disabled:cursor-not-allowed"
                    >
                      PDF
                    </Button>
                  </div>
                </div>
              ))}
            </div>
            
            <div className="p-4 border-t border-theme bg-theme-background-secondary rounded-b-lg">
              <div className="flex items-center text-xs text-theme-tertiary">
                <span className="text-lg mr-2">ℹ️</span>
                <div>
                  <p>CSV exports include raw data for further analysis.</p>
                  <p className="mt-1">PDF reports include formatted charts and summaries.</p>
                </div>
              </div>
            </div>
          </div>
        </>
      )}
    </div>
  );
};