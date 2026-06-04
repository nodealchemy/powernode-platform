import React, { useState } from 'react';
import { ArrowLeft } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Loading } from '@/shared/components/ui/Loading';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { TraceList } from '@/features/ai/debugging/components/TraceList';
import { TraceViewer, type TraceData } from '@/features/ai/debugging/components/TraceViewer';
import { executionTracesApi } from '@/features/ai/debugging/services/executionTracesApi';
import { getErrorMessage } from '@/shared/utils/errorHandling';

/**
 * ExecutionTracesPage — distributed-trace viewer for AI execution.
 *
 * Wires the previously-orphaned `features/ai/debugging` components (TraceList +
 * TraceViewer) into a routed page under the Developer nav section. Selecting a
 * trace fetches its full span tree via the authenticated executionTracesApi.
 */
export const ExecutionTracesPage: React.FC = () => {
  const { addNotification } = useNotifications();
  const [selectedTrace, setSelectedTrace] = useState<TraceData | null>(null);
  const [loadingTrace, setLoadingTrace] = useState(false);

  const handleSelectTrace = async (traceId: string) => {
    setLoadingTrace(true);
    try {
      const trace = await executionTracesApi.getTrace(traceId);
      setSelectedTrace(trace);
    } catch (error) {
      addNotification({ type: 'error', message: getErrorMessage(error) });
    } finally {
      setLoadingTrace(false);
    }
  };

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'Developer', href: '/app/developer' },
    { label: 'Execution Traces' },
  ];

  return (
    <PageContainer
      title="Execution Traces"
      description="Distributed traces for AI agent, workflow, and tool execution"
      breadcrumbs={breadcrumbs}
      actions={
        selectedTrace
          ? [
              {
                label: 'Back to traces',
                onClick: () => setSelectedTrace(null),
                icon: ArrowLeft,
                variant: 'secondary' as const,
              },
            ]
          : []
      }
    >
      {loadingTrace ? (
        <div className="flex items-center justify-center py-12">
          <Loading size="lg" message="Loading trace..." />
        </div>
      ) : selectedTrace ? (
        <TraceViewer trace={selectedTrace} />
      ) : (
        <TraceList onSelectTrace={handleSelectTrace} />
      )}
    </PageContainer>
  );
};

export default ExecutionTracesPage;
