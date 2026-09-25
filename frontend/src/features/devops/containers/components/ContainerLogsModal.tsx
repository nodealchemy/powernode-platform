import React, { useState, useEffect } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { Loading } from '@/shared/components/ui/Loading';
import { containerExecutionApi } from '@/shared/services/ai';
import type { ContainerInstanceSummary } from '@/shared/services/ai';

interface ContainerLogsModalProps {
  container: ContainerInstanceSummary | null;
  onClose: () => void;
}

export const ContainerLogsModal: React.FC<ContainerLogsModalProps> = ({ container, onClose }) => {
  const [logs, setLogs] = useState<string>('');
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!container) return;

    setIsLoading(true);
    setError(null);
    containerExecutionApi
      .getContainerLogs(container.id)
      .then((res) => setLogs(res.logs || ''))
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load logs'))
      .finally(() => setIsLoading(false));
  }, [container]);

  return (
    <Modal
      isOpen={!!container}
      onClose={onClose}
      title={container ? `Logs — ${container.execution_id}` : 'Logs'}
      size="lg"
    >
      {isLoading ? (
        <div className="flex items-center justify-center p-8">
          <Loading size="lg" />
        </div>
      ) : error ? (
        <div className="p-4 rounded-lg bg-theme-status-error/10 text-theme-status-error">{error}</div>
      ) : (
        <pre className="whitespace-pre-wrap text-xs bg-theme-background-secondary p-4 rounded-lg max-h-96 overflow-auto">
          {logs || 'No logs available.'}
        </pre>
      )}
    </Modal>
  );
};

export default ContainerLogsModal;
