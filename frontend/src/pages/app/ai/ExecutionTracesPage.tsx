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
 * ExecutionTracesContent — the embeddable body of the execution-trace viewer
 * (TraceList + TraceViewer), WITHOUT a PageContainer of its own.
 *
 * Extracted so it can be mounted both as a standalone page (ExecutionTracesPage,
 * under the Developer nav) and as the `traces` tab of the Operations hub
 * (`OperationsPage`), where the surrounding PageContainer is supplied by the hub.
 * The "back to traces" affordance lives inside the content (rather than as a
 * page-level action) because the embedding hub owns the page header.
 */
export const ExecutionTracesContent: React.FC = () => {
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

  if (loadingTrace) {
    return (
      <div className="flex items-center justify-center py-12">
        <Loading size="lg" message="Loading trace..." />
      </div>
    );
  }

  if (selectedTrace) {
    return (
      <div className="space-y-4">
        <button
          type="button"
          onClick={() => setSelectedTrace(null)}
          className="btn-theme btn-theme-secondary btn-theme-sm"
          data-testid="execution-traces-back"
          aria-label="Back to traces"
        >
          <ArrowLeft className="w-4 h-4 mr-2" />
          Back to traces
        </button>
        <TraceViewer trace={selectedTrace} />
      </div>
    );
  }

  return <TraceList onSelectTrace={handleSelectTrace} />;
};

/**
 * ExecutionTracesPage — distributed-trace viewer for AI execution.
 *
 * Wires the previously-orphaned `features/ai/debugging` components (TraceList +
 * TraceViewer) into a routed page under the Developer nav section. The body is
 * `ExecutionTracesContent` so the same viewer can be embedded into the Operations
 * hub's `traces` tab.
 */
export const ExecutionTracesPage: React.FC = () => {
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
    >
      <ExecutionTracesContent />
    </PageContainer>
  );
};

export default ExecutionTracesPage;
