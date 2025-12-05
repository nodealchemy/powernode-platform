
import { CheckCircle, XCircle, AlertCircle, Clock, Zap } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { StorageConnectionTestResult } from '@/shared/types/storage';

interface ConnectionTestModalProps {
  isOpen: boolean;
  onClose: () => void;
  providerName: string;
  result: StorageConnectionTestResult | null;
  testing: boolean;
}

export const ConnectionTestModal: React.FC<ConnectionTestModalProps> = ({
  isOpen,
  onClose,
  providerName,
  result,
  testing,
}) => {
  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={`Connection Test - ${providerName}`}
      maxWidth="md"
    >
      <div className="space-y-4">
        {testing && (
          <div className="flex flex-col items-center justify-center py-8">
            <div className="animate-spin h-12 w-12 border-4 border-blue-600 border-t-transparent rounded-full mb-4" />
            <p className="text-lg font-medium text-theme-primary">Testing connection...</p>
            <p className="text-sm text-theme-secondary mt-2">
              Please wait while we verify the storage configuration
            </p>
          </div>
        )}

        {!testing && result && (
          <div className="space-y-4">
            {/* Result Header */}
            <div
              className={`flex items-center gap-3 p-4 rounded-lg ${
                result.success
                  ? 'bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800'
                  : 'bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800'
              }`}
            >
              {result.success ? (
                <CheckCircle className="h-8 w-8 text-theme-success dark:text-green-400 flex-shrink-0" />
              ) : (
                <XCircle className="h-8 w-8 text-theme-danger dark:text-red-400 flex-shrink-0" />
              )}
              <div className="flex-1">
                <h3
                  className={`text-lg font-semibold ${
                    result.success
                      ? 'text-green-900 dark:text-green-100'
                      : 'text-red-900 dark:text-red-100'
                  }`}
                >
                  {result.success ? 'Connection Successful' : 'Connection Failed'}
                </h3>
                <p
                  className={`text-sm ${
                    result.success
                      ? 'text-theme-success dark:text-green-300'
                      : 'text-theme-danger dark:text-red-300'
                  }`}
                >
                  {result.message}
                </p>
              </div>
            </div>

            {/* Connection Details */}
            {result.details && (
              <div className="bg-theme-surface border border-theme rounded-lg p-4 space-y-3">
                <h4 className="text-sm font-semibold text-theme-primary mb-3">
                  Connection Details
                </h4>

                {result.details.latency_ms !== undefined && (
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2 text-sm text-theme-secondary">
                      <Clock className="h-4 w-4" />
                      <span>Latency</span>
                    </div>
                    <span
                      className={`text-sm font-medium ${
                        result.details.latency_ms < 100
                          ? 'text-theme-success dark:text-green-400'
                          : result.details.latency_ms < 500
                          ? 'text-theme-warning dark:text-yellow-400'
                          : 'text-theme-danger dark:text-red-400'
                      }`}
                    >
                      {result.details.latency_ms}ms
                    </span>
                  </div>
                )}

                {result.details.readable !== undefined && (
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2 text-sm text-theme-secondary">
                      <Zap className="h-4 w-4" />
                      <span>Read Access</span>
                    </div>
                    {result.details.readable ? (
                      <CheckCircle className="h-5 w-5 text-theme-success dark:text-green-400" />
                    ) : (
                      <XCircle className="h-5 w-5 text-theme-danger dark:text-red-400" />
                    )}
                  </div>
                )}

                {result.details.writable !== undefined && (
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2 text-sm text-theme-secondary">
                      <Zap className="h-4 w-4" />
                      <span>Write Access</span>
                    </div>
                    {result.details.writable ? (
                      <CheckCircle className="h-5 w-5 text-theme-success dark:text-green-400" />
                    ) : (
                      <XCircle className="h-5 w-5 text-theme-danger dark:text-red-400" />
                    )}
                  </div>
                )}

                {result.details.error && (
                  <div className="mt-3 p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg">
                    <div className="flex items-start gap-2">
                      <AlertCircle className="h-5 w-5 text-theme-danger dark:text-red-400 flex-shrink-0 mt-0.5" />
                      <div>
                        <p className="text-sm font-medium text-red-900 dark:text-red-100">
                          Error Details
                        </p>
                        <p className="text-sm text-theme-danger dark:text-red-300 mt-1">
                          {result.details.error}
                        </p>
                      </div>
                    </div>
                  </div>
                )}
              </div>
            )}

            {/* Recommendations */}
            {!result.success && (
              <div className="bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800 rounded-lg p-4">
                <h4 className="text-sm font-semibold text-blue-900 dark:text-blue-100 mb-2">
                  Troubleshooting Tips
                </h4>
                <ul className="text-sm text-theme-info dark:text-blue-300 space-y-1 list-disc list-inside">
                  <li>Verify your credentials are correct</li>
                  <li>Check that the storage endpoint is accessible</li>
                  <li>Ensure proper firewall and network configuration</li>
                  <li>Confirm the storage container/bucket exists</li>
                  <li>Review IAM permissions for your service account</li>
                </ul>
              </div>
            )}
          </div>
        )}

        {/* Actions */}
        <div className="flex items-center justify-end gap-3 pt-4 border-t border-theme">
          <button
            onClick={onClose}
            className="px-4 py-2 text-sm font-medium text-theme-primary bg-theme-surface border border-theme rounded-lg hover:bg-theme-hover transition-colors"
          >
            Close
          </button>
        </div>
      </div>
    </Modal>
  );
};
