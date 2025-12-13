import React, { useState } from 'react';
import {
  ArrowDownTrayIcon,
  DocumentArrowDownIcon,
  ClockIcon,
  CheckCircleIcon,
  ExclamationCircleIcon,
} from '@heroicons/react/24/outline';
import type { DataExportRequest } from '../services/privacyApi';

interface DataExportCardProps {
  requests: DataExportRequest[];
  onRequestExport: (options: { format: string; export_type: string }) => Promise<void>;
  onDownload: (id: string, token: string) => Promise<void>;
  loading?: boolean;
}

const STATUS_STYLES: Record<string, { bg: string; text: string; icon: React.ElementType }> = {
  pending: { bg: 'bg-theme-warning/20', text: 'text-theme-warning', icon: ClockIcon },
  processing: { bg: 'bg-theme-info/20', text: 'text-theme-info', icon: ClockIcon },
  completed: { bg: 'bg-theme-success/20', text: 'text-theme-success', icon: CheckCircleIcon },
  failed: { bg: 'bg-theme-danger/20', text: 'text-theme-danger', icon: ExclamationCircleIcon },
  expired: { bg: 'bg-theme-surface', text: 'text-theme-primary', icon: ExclamationCircleIcon },
};

export const DataExportCard: React.FC<DataExportCardProps> = ({
  requests,
  onRequestExport,
  onDownload,
  loading = false,
}) => {
  const [format, setFormat] = useState<'json' | 'csv' | 'zip'>('json');
  const [requesting, setRequesting] = useState(false);

  const handleRequestExport = async () => {
    setRequesting(true);
    try {
      await onRequestExport({ format, export_type: 'full' });
    } finally {
      setRequesting(false);
    }
  };

  const formatFileSize = (bytes?: number) => {
    if (!bytes) return 'N/A';
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  };

  return (
    <div className="bg-theme-surface rounded-lg border border-theme p-6">
      <div className="flex items-center space-x-3 mb-6">
        <DocumentArrowDownIcon className="h-6 w-6 text-theme-primary" />
        <div>
          <h3 className="text-lg font-semibold text-theme-primary">Data Export</h3>
          <p className="text-sm text-theme-secondary">
            Download a copy of your personal data
          </p>
        </div>
      </div>

      {/* Request Form */}
      <div className="p-4 bg-theme-background rounded-lg mb-6">
        <div className="flex items-end space-x-4">
          <div className="flex-1">
            <label className="block text-sm font-medium text-theme-primary mb-2">
              Export Format
            </label>
            <select
              value={format}
              onChange={(e) => setFormat(e.target.value as 'json' | 'csv' | 'zip')}
              className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
            >
              <option value="json">JSON (Recommended)</option>
              <option value="csv">CSV (Spreadsheet)</option>
              <option value="zip">ZIP Archive</option>
            </select>
          </div>
          <button
            onClick={handleRequestExport}
            disabled={requesting || loading}
            className="px-6 py-2 bg-theme-primary text-white rounded-lg hover:bg-theme-primary-dark transition-colors disabled:opacity-50 flex items-center space-x-2"
          >
            <ArrowDownTrayIcon className="h-5 w-5" />
            <span>{requesting ? 'Requesting...' : 'Request Export'}</span>
          </button>
        </div>
        <p className="text-xs text-theme-tertiary mt-2">
          Exports typically take 5-15 minutes to prepare. You can request one export per week.
        </p>
      </div>

      {/* Recent Requests */}
      {requests.length > 0 && (
        <div>
          <h4 className="text-sm font-medium text-theme-primary mb-3">Recent Exports</h4>
          <div className="space-y-3">
            {requests.map((request) => {
              const style = STATUS_STYLES[request.status] || STATUS_STYLES.pending;
              const Icon = style.icon;

              return (
                <div
                  key={request.id}
                  className="flex items-center justify-between p-3 bg-theme-background rounded-lg"
                >
                  <div className="flex items-center space-x-3">
                    <span className={`px-2 py-1 rounded text-xs font-medium ${style.bg} ${style.text}`}>
                      <Icon className="h-4 w-4 inline mr-1" />
                      {request.status}
                    </span>
                    <div>
                      <p className="text-sm text-theme-primary">
                        {request.format.toUpperCase()} Export
                      </p>
                      <p className="text-xs text-theme-tertiary">
                        {new Date(request.created_at).toLocaleDateString()}
                        {request.file_size_bytes && ` • ${formatFileSize(request.file_size_bytes)}`}
                      </p>
                    </div>
                  </div>

                  {request.downloadable && request.download_token && (
                    <button
                      onClick={() => onDownload(request.id, request.download_token!)}
                      className="px-3 py-1.5 bg-theme-success text-white text-sm rounded hover:opacity-90 transition-colors flex items-center space-x-1"
                    >
                      <ArrowDownTrayIcon className="h-4 w-4" />
                      <span>Download</span>
                    </button>
                  )}

                  {request.status === 'pending' || request.status === 'processing' ? (
                    <span className="text-sm text-theme-secondary">Processing...</span>
                  ) : null}
                </div>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
};

export default DataExportCard;
