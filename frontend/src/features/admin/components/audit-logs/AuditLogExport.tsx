import React, { useState } from 'react';
import {
  Download,
  FileText,
  Table,
  X,
  AlertCircle,
  Loader
} from 'lucide-react';
import { AuditLogFilters as FilterType } from '@/features/audit-logs/services/auditLogsApi';
import { useNotification } from '@/shared/hooks/useNotification';

interface AuditLogExportProps {
  filters: FilterType;
  onClose: () => void;
}

type ExportFormat = 'csv' | 'json' | 'pdf';
type ExportScope = 'current' | 'filtered' | 'all';

interface ExportOptions {
  format: ExportFormat;
  scope: ExportScope;
  includeMetadata: boolean;
  includeSensitiveData: boolean;
  maxRecords: number;
  customDateRange: {
    enabled: boolean;
    startDate: string;
    endDate: string;
  };
}

export const AuditLogExport: React.FC<AuditLogExportProps> = ({ filters, onClose }) => {
AuditLogExport.displayName = 'AuditLogExport';
  const [exportOptions, setExportOptions] = useState<ExportOptions>({
    format: 'csv',
    scope: 'filtered',
    includeMetadata: true,
    includeSensitiveData: false,
    maxRecords: 10000,
    customDateRange: {
      enabled: false,
      startDate: '',
      endDate: ''
    }
  });
  
  const [isExporting, setIsExporting] = useState(false);
  const [exportProgress, setExportProgress] = useState(0);
  const { showNotification } = useNotification();

  const formatOptions = [
    {
      value: 'csv',
      label: 'CSV',
      description: 'Comma-separated values for spreadsheet applications',
      icon: <Table className="w-4 h-4" />
    },
    {
      value: 'json',
      label: 'JSON',
      description: 'JavaScript Object Notation for programmatic access',
      icon: <FileText className="w-4 h-4" />
    },
    {
      value: 'pdf',
      label: 'PDF',
      description: 'Portable Document Format for reports and archival',
      icon: <FileText className="w-4 h-4" />
    }
  ];

  const scopeOptions = [
    {
      value: 'current',
      label: 'Current Page',
      description: 'Export only the currently displayed audit logs'
    },
    {
      value: 'filtered',
      label: 'All Filtered Results',
      description: 'Export all audit logs matching current filters'
    },
    {
      value: 'all',
      label: 'All Audit Logs',
      description: 'Export complete audit log history (use with caution)'
    }
  ];

  const handleExport = async () => {
    setIsExporting(true);
    setExportProgress(0);

    try {
      // Simulate export progress
      const progressInterval = setInterval(() => {
        setExportProgress(prev => {
          if (prev >= 90) {
            clearInterval(progressInterval);
            return 90;
          }
          return prev + 10;
        });
      }, 200);

      // TODO: Implement actual export API call with parameters:

      // Simulate API call
      await new Promise(resolve => setTimeout(resolve, 2000));
      
      clearInterval(progressInterval);
      setExportProgress(100);
      
      // Simulate file download
      const timestamp = new Date().toISOString().split('T')[0];
      const filename = `audit-logs-${timestamp}.${exportOptions.format}`;
      
      // In a real implementation, this would be an actual file download
      showNotification(`Export completed: ${filename}`, 'success');
      
      setTimeout(() => {
        setIsExporting(false);
        setExportProgress(0);
        onClose();
      }, 1000);
      
    } catch (error) {
      console.error('Export failed:', error);
      setIsExporting(false);
      setExportProgress(0);
      showNotification('Export failed. Please try again.', 'error');
    }
  };

  const updateExportOptions = (key: keyof ExportOptions, value: any) => {
    setExportOptions(prev => ({ ...prev, [key]: value }));
  };

  const estimatedRecords = (() => {
    switch (exportOptions.scope) {
      case 'current': return 25;
      case 'filtered': return 1250;
      case 'all': return 15750;
      default: return 0;
    }
  })();

  return (
    <div className="bg-theme-surface rounded-lg border border-theme overflow-hidden">
      {/* Header */}
      <div className="px-6 py-4 border-b border-theme">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-theme-interactive-primary bg-opacity-10 rounded-lg">
              <Download className="w-5 h-5 text-theme-interactive-primary" />
            </div>
            <div>
              <h3 className="text-lg font-semibold text-theme-primary">Export Audit Logs</h3>
              <p className="text-theme-secondary">Configure and download audit log data</p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="text-theme-secondary hover:text-theme-primary transition-colors duration-200"
          >
            <X className="w-5 h-5" />
          </button>
        </div>
      </div>

      {/* Export Configuration */}
      <div className="p-6 space-y-6">
        {/* Format Selection */}
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-3">Export Format</label>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            {formatOptions.map((format) => (
              <button
                key={format.value}
                onClick={() => updateExportOptions('format', format.value)}
                className={`p-4 rounded-lg border-2 transition-all duration-200 text-left ${
                  exportOptions.format === format.value
                    ? 'border-theme-interactive-primary bg-theme-interactive-primary bg-opacity-5'
                    : 'border-theme hover:border-theme-focus'
                }`}
              >
                <div className="flex items-center gap-2 mb-2">
                  {format.icon}
                  <span className="font-medium text-theme-primary">{format.label}</span>
                </div>
                <p className="text-xs text-theme-secondary">{format.description}</p>
              </button>
            ))}
          </div>
        </div>

        {/* Scope Selection */}
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-3">Export Scope</label>
          <div className="space-y-2">
            {scopeOptions.map((scope) => (
              <label
                key={scope.value}
                className="flex items-start gap-3 p-3 rounded-lg border border-theme hover:bg-theme-surface-hover cursor-pointer transition-colors duration-200"
              >
                <input
                  type="radio"
                  name="scope"
                  value={scope.value}
                  checked={exportOptions.scope === scope.value}
                  onChange={(e) => updateExportOptions('scope', e.target.value)}
                  className="mt-1"
                />
                <div>
                  <div className="font-medium text-theme-primary">{scope.label}</div>
                  <div className="text-sm text-theme-secondary">{scope.description}</div>
                </div>
              </label>
            ))}
          </div>
        </div>

        {/* Additional Options */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-3">Additional Options</label>
            <div className="space-y-3">
              <label className="flex items-center gap-2">
                <input
                  type="checkbox"
                  checked={exportOptions.includeMetadata}
                  onChange={(e) => updateExportOptions('includeMetadata', e.target.checked)}
                  className="rounded"
                />
                <span className="text-sm text-theme-primary">Include metadata fields</span>
              </label>
              
              <label className="flex items-center gap-2">
                <input
                  type="checkbox"
                  checked={exportOptions.includeSensitiveData}
                  onChange={(e) => updateExportOptions('includeSensitiveData', e.target.checked)}
                  className="rounded"
                />
                <span className="text-sm text-theme-primary">Include sensitive data</span>
              </label>
            </div>
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-primary mb-3">Record Limit</label>
            <select
              value={exportOptions.maxRecords}
              onChange={(e) => updateExportOptions('maxRecords', parseInt(e.target.value))}
              className="w-full px-3 py-2 text-sm bg-theme-background border border-theme rounded-md text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-focus focus:border-transparent"
            >
              <option value={1000}>1,000 records</option>
              <option value={5000}>5,000 records</option>
              <option value={10000}>10,000 records</option>
              <option value={50000}>50,000 records</option>
              <option value={-1}>No limit</option>
            </select>
          </div>
        </div>

        {/* Custom Date Range */}
        <div>
          <label className="flex items-center gap-2 mb-3">
            <input
              type="checkbox"
              checked={exportOptions.customDateRange.enabled}
              onChange={(e) => updateExportOptions('customDateRange', {
                ...exportOptions.customDateRange,
                enabled: e.target.checked
              })}
              className="rounded"
            />
            <span className="text-sm font-medium text-theme-primary">Use custom date range</span>
          </label>
          
          {exportOptions.customDateRange.enabled && (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className="block text-xs font-medium text-theme-secondary mb-1">Start Date</label>
                <input
                  type="date"
                  value={exportOptions.customDateRange.startDate}
                  onChange={(e) => updateExportOptions('customDateRange', {
                    ...exportOptions.customDateRange,
                    startDate: e.target.value
                  })}
                  className="w-full px-3 py-2 text-sm bg-theme-background border border-theme rounded-md text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-focus focus:border-transparent"
                />
              </div>
              <div>
                <label className="block text-xs font-medium text-theme-secondary mb-1">End Date</label>
                <input
                  type="date"
                  value={exportOptions.customDateRange.endDate}
                  onChange={(e) => updateExportOptions('customDateRange', {
                    ...exportOptions.customDateRange,
                    endDate: e.target.value
                  })}
                  className="w-full px-3 py-2 text-sm bg-theme-background border border-theme rounded-md text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-focus focus:border-transparent"
                />
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Export Progress */}
      {isExporting && (
        <div className="px-6 py-4 border-t border-theme bg-theme-background">
          <div className="flex items-center gap-3 mb-2">
            <Loader className="w-4 h-4 animate-spin text-theme-interactive-primary" />
            <span className="text-sm font-medium text-theme-primary">Exporting audit logs...</span>
            <span className="text-sm text-theme-secondary">{exportProgress}%</span>
          </div>
          <div className="w-full bg-theme-surface rounded-full h-2">
            <div 
              className="bg-theme-interactive-primary h-2 rounded-full transition-all duration-300"
              style={{ width: `${exportProgress}%` }}
            />
          </div>
        </div>
      )}

      {/* Footer */}
      <div className="px-6 py-4 border-t border-theme bg-theme-background flex items-center justify-between">
        <div className="flex items-center gap-2 text-sm text-theme-secondary">
          <AlertCircle className="w-4 h-4" />
          <span>Estimated {estimatedRecords.toLocaleString()} records to export</span>
        </div>
        
        <div className="flex items-center gap-2">
          <button
            onClick={onClose}
            disabled={isExporting}
            className="px-4 py-2 text-sm text-theme-secondary hover:text-theme-primary transition-colors duration-200 disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            onClick={handleExport}
            disabled={isExporting}
            className="flex items-center gap-2 px-4 py-2 text-sm bg-theme-interactive-primary text-white rounded-md hover:bg-theme-interactive-primary-hover transition-colors duration-200 disabled:opacity-50"
          >
            {isExporting ? (
              <Loader className="w-4 h-4 animate-spin" />
            ) : (
              <Download className="w-4 h-4" />
            )}
            {isExporting ? 'Exporting...' : 'Start Export'}
          </button>
        </div>
      </div>
    </div>
  );
};