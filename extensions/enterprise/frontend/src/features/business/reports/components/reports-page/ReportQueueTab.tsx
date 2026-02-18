import React from 'react';
import { ReportRequest } from '@enterprise/pages/business/ReportsPage';

interface ReportQueueTabProps {
  requests: ReportRequest[];
  onDownload: (request: ReportRequest) => void;
  onCancel: (requestId: string) => void;
}

export const ReportQueueTab: React.FC<ReportQueueTabProps> = ({
  requests,
  onDownload,
  onCancel
}) => {
  return (
    <div className="space-y-6">
      {(requests?.length ?? 0) === 0 ? (
        <div className="text-center py-12">
          <span className="text-6xl">N</span>
          <h3 className="text-lg font-medium text-theme-primary mt-2">No reports in queue</h3>
          <p className="text-theme-secondary">Start by creating a report from the Builder or Library.</p>
        </div>
      ) : (
        (requests || []).map((request) => (
          <div key={request.id} className="card-theme p-4">
            <div className="flex items-center justify-between">
              <div className="flex-1">
                <h3 className="font-medium text-theme-primary">{request.name}</h3>
                <div className="flex items-center space-x-4 text-sm text-theme-secondary mt-1">
                  <span>Type: {request.type}</span>
                  <span>Format: {request.format.toUpperCase()}</span>
                  <span>Requested: {new Date(request.requested_at).toLocaleDateString()}</span>
                </div>
              </div>
              <div className="flex items-center space-x-3">
                <span className={`px-2 py-1 text-xs rounded ${
                  request.status === 'completed' ? 'bg-theme-success text-theme-success' :
                  request.status === 'processing' ? 'bg-theme-info text-theme-info' :
                  request.status === 'failed' ? 'bg-theme-error text-theme-error' :
                  'bg-theme-background-secondary text-theme-secondary'
                }`}>
                  {request.status.toUpperCase()}
                </span>
                {request.status === 'completed' && request.file_url && (
                  <button
                    onClick={() => onDownload(request)}
                    className="btn-theme btn-theme-primary text-xs px-3 py-1"
                  >
                    Download
                  </button>
                )}
                {request.status === 'pending' && (
                  <button
                    onClick={() => onCancel(request.id)}
                    className="btn-theme btn-theme-secondary text-xs px-3 py-1"
                  >
                    Cancel
                  </button>
                )}
              </div>
            </div>
          </div>
        ))
      )}
    </div>
  );
};
