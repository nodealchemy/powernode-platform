import React, { useState, useEffect } from 'react';
import { X, Clock, CheckCircle, XCircle, Loader } from 'lucide-react';
import { servicesApi } from '../../services/servicesApi';

interface JobProgressModalProps {
  isOpen: boolean;
  onClose: () => void;
  jobId: string;
  jobType: string;
  title: string;
  onComplete?: (result: any) => void;
  onError?: (error: string) => void;
}

export const JobProgressModal: React.FC<JobProgressModalProps> = ({
  isOpen,
  onClose,
  jobId,
  jobType,
  title,
  onComplete,
  onError
}) => {
  const [status, setStatus] = useState<'pending' | 'in_progress' | 'completed' | 'failed' | 'cancelled'>('pending');
  const [progress, setProgress] = useState(0);
  const [result, setResult] = useState<any>(null);
  const [error, setError] = useState<string | null>(null);
  const [duration, setDuration] = useState<number | null>(null);
  const [polling, setPolling] = useState(false);

  useEffect(() => {
    if (!isOpen || !jobId || polling) return;

    let isMounted = true;
    setPolling(true);

    const pollJob = async () => {
      try {
        const jobData = await servicesApi.pollJobUntilComplete(
          jobId,
          (currentStatus, currentProgress, currentResult) => {
            if (!isMounted) return;
            
            setStatus(currentStatus as any);
            setProgress(currentProgress);
            
            if (currentResult) {
              setResult(currentResult);
            }
          },
          120, // 2 minutes max
          1000 // Poll every second
        );

        if (isMounted) {
          setResult(jobData);
          setStatus('completed');
          onComplete?.(jobData);
        }
      } catch (err: any) {
        if (isMounted) {
          const errorMessage = err.message || 'Job failed';
          setError(errorMessage);
          setStatus('failed');
          onError?.(errorMessage);
        }
      } finally {
        if (isMounted) {
          setPolling(false);
        }
      }
    };

    pollJob();

    return () => {
      isMounted = false;
    };
  }, [isOpen, jobId, onComplete, onError, polling]);

  const handleClose = () => {
    setStatus('pending');
    setProgress(0);
    setResult(null);
    setError(null);
    setDuration(null);
    setPolling(false);
    onClose();
  };

  const getStatusIcon = () => {
    switch (status) {
      case 'pending':
        return <Clock className="w-5 h-5 text-theme-warning" />;
      case 'in_progress':
        return <Loader className="w-5 h-5 text-theme-primary animate-spin" />;
      case 'completed':
        return <CheckCircle className="w-5 h-5 text-theme-success" />;
      case 'failed':
      case 'cancelled':
        return <XCircle className="w-5 h-5 text-theme-error" />;
      default:
        return <Clock className="w-5 h-5 text-theme-secondary" />;
    }
  };

  const getStatusText = () => {
    switch (status) {
      case 'pending':
        return 'Queued';
      case 'in_progress':
        return 'In Progress';
      case 'completed':
        return 'Completed';
      case 'failed':
        return 'Failed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return 'Unknown';
    }
  };

  const getProgressColor = () => {
    switch (status) {
      case 'completed':
        return 'bg-theme-success';
      case 'failed':
      case 'cancelled':
        return 'bg-theme-error';
      case 'in_progress':
        return 'bg-theme-primary';
      default:
        return 'bg-theme-secondary';
    }
  };

  const renderResult = () => {
    if (!result) return null;

    switch (jobType) {
      case 'services_test_configuration':
        return (
          <div className="space-y-3">
            {result.validation && (
              <div>
                <h4 className="font-medium text-theme-primary mb-2">Validation Results</h4>
                <div className={`p-3 rounded-lg ${result.validation.valid ? 'bg-theme-success bg-opacity-10' : 'bg-theme-error bg-opacity-10'}`}>
                  <div className="flex items-center gap-2">
                    {result.validation.valid ? 
                      <CheckCircle className="w-4 h-4 text-theme-success" /> : 
                      <XCircle className="w-4 h-4 text-theme-error" />
                    }
                    <span className={result.validation.valid ? 'text-theme-success' : 'text-theme-error'}>
                      {result.validation.valid ? 'Configuration Valid' : 'Configuration Invalid'}
                    </span>
                  </div>
                  {result.validation.errors?.length > 0 && (
                    <ul className="mt-2 text-sm text-theme-error">
                      {result.validation.errors.map((error: string, index: number) => (
                        <li key={index}>• {error}</li>
                      ))}
                    </ul>
                  )}
                </div>
              </div>
            )}
            
            {result.connectivity && (
              <div>
                <h4 className="font-medium text-theme-primary mb-2">Connectivity Test</h4>
                <div className="space-y-2">
                  {Object.entries(result.connectivity).map(([serviceName, serviceResult]: [string, any]) => (
                    <div key={serviceName} className="flex items-center justify-between p-2 bg-theme-surface rounded">
                      <span className="font-medium">{serviceName}</span>
                      <div className="flex items-center gap-2">
                        <span className={`px-2 py-1 rounded text-xs ${
                          serviceResult.status === 'healthy' ? 'bg-theme-success bg-opacity-20 text-theme-success' :
                          serviceResult.status === 'unhealthy' ? 'bg-theme-warning bg-opacity-20 text-theme-warning' :
                          'bg-theme-error bg-opacity-20 text-theme-error'
                        }`}>
                          {serviceResult.status}
                        </span>
                        {serviceResult.response_time_ms && (
                          <span className="text-xs text-theme-secondary">
                            {serviceResult.response_time_ms}ms
                          </span>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        );

      case 'services_generate_config':
        return (
          <div className="space-y-3">
            <div>
              <h4 className="font-medium text-theme-primary mb-2">Generated Configuration</h4>
              <div className="bg-theme-surface rounded-lg p-3">
                <div className="flex items-center justify-between mb-2">
                  <span className="font-medium">{result.filename}</span>
                  <span className="text-xs text-theme-secondary">{result.size} chars</span>
                </div>
                <pre className="text-xs text-theme-secondary overflow-x-auto max-h-40 bg-theme-background p-2 rounded">
                  {result.config?.substring(0, 500)}{result.config?.length > 500 ? '...' : ''}
                </pre>
              </div>
            </div>
            
            {result.instructions && (
              <div>
                <h4 className="font-medium text-theme-primary mb-2">Installation Instructions</h4>
                <pre className="text-xs text-theme-secondary bg-theme-surface p-3 rounded whitespace-pre-wrap">
                  {result.instructions}
                </pre>
              </div>
            )}
          </div>
        );

      case 'services_service_discovery':
        return (
          <div className="space-y-3">
            <div>
              <h4 className="font-medium text-theme-primary mb-2">
                Discovered Services ({result.services_count || 0})
              </h4>
              {result.services?.length > 0 ? (
                <div className="space-y-2 max-h-60 overflow-y-auto">
                  {result.services.map((service: any, index: number) => (
                    <div key={index} className="flex items-center justify-between p-2 bg-theme-surface rounded">
                      <div>
                        <span className="font-medium">{service.name}</span>
                        <div className="text-xs text-theme-secondary">
                          {service.protocol}://{service.host}:{service.port}
                        </div>
                      </div>
                      <div className="text-right">
                        <span className={`px-2 py-1 rounded text-xs ${
                          service.status === 'healthy' ? 'bg-theme-success bg-opacity-20 text-theme-success' :
                          'bg-theme-warning bg-opacity-20 text-theme-warning'
                        }`}>
                          {service.status}
                        </span>
                        <div className="text-xs text-theme-tertiary mt-1">
                          via {service.discovered_method}
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              ) : (
                <div className="text-center py-4 text-theme-secondary">
                  No services discovered
                </div>
              )}
            </div>
          </div>
        );

      default:
        return (
          <pre className="text-xs text-theme-secondary bg-theme-surface p-3 rounded overflow-x-auto">
            {JSON.stringify(result, null, 2)}
          </pre>
        );
    }
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 bg-theme-background bg-opacity-50 flex items-center justify-center z-50">
      <div className="bg-theme-surface rounded-lg shadow-xl w-full max-w-2xl max-h-[80vh] overflow-hidden">
        <div className="flex items-center justify-between p-4 border-b border-theme">
          <h2 className="text-lg font-semibold text-theme-primary">{title}</h2>
          <button
            onClick={handleClose}
            className="p-1 hover:bg-theme-surface rounded"
          >
            <X className="w-5 h-5 text-theme-secondary" />
          </button>
        </div>

        <div className="p-4 overflow-y-auto">
          <div className="space-y-4">
            {/* Status */}
            <div className="flex items-center gap-3">
              {getStatusIcon()}
              <div>
                <span className="font-medium text-theme-primary">{getStatusText()}</span>
                {duration && (
                  <span className="text-sm text-theme-secondary ml-2">
                    ({duration.toFixed(1)}s)
                  </span>
                )}
              </div>
            </div>

            {/* Progress Bar */}
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <span className="text-sm text-theme-secondary">Progress</span>
                <span className="text-sm text-theme-secondary">{progress}%</span>
              </div>
              <div className="w-full bg-theme-background rounded-full h-2">
                <div
                  className={`h-2 rounded-full transition-all duration-300 ${getProgressColor()}`}
                  style={{ width: `${progress}%` }}
                />
              </div>
            </div>

            {/* Error */}
            {error && (
              <div className="bg-theme-error bg-opacity-10 border border-theme-error border-opacity-20 rounded-lg p-3">
                <div className="flex items-center gap-2 text-theme-error">
                  <XCircle className="w-4 h-4" />
                  <span className="font-medium">Error</span>
                </div>
                <p className="text-sm text-theme-error mt-1">{error}</p>
              </div>
            )}

            {/* Results */}
            {status === 'completed' && result && (
              <div className="border-t border-theme pt-4">
                <h3 className="font-medium text-theme-primary mb-3">Results</h3>
                {renderResult()}
              </div>
            )}
          </div>
        </div>

        {/* Actions */}
        <div className="border-t border-theme p-4">
          <div className="flex justify-end">
            <button
              onClick={handleClose}
              className="px-4 py-2 bg-theme-primary text-white rounded hover:bg-theme-primary-dark transition-colors"
            >
              {status === 'completed' || status === 'failed' ? 'Close' : 'Cancel'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};