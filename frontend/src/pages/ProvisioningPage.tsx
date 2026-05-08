import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { Loader2, Server } from 'lucide-react';
import { ProjectProvisioningChat } from '@/features/ai/provisioning/ProjectProvisioningChat';
import { ProvisioningPlanReview } from '@/features/ai/provisioning/ProvisioningPlanReview';
import { ExecutionPill } from '@/features/ai/provisioning/ExecutionPill';
import {
  StepProgressStream,
  type PlanStep as ProgressStreamPlanStep,
  type ProvisioningStepStatus,
} from '@/features/ai/provisioning/StepProgressStream';
import type {
  ProvisioningPlan,
  ProjectBrief,
  PlanStepStatus,
} from '@/features/ai/provisioning/types';
import { logger } from '@/shared/utils/logger';
import apiClient from '@/shared/services/apiClient';

type ViewMode = 'chat' | 'plan' | 'executing';

interface ConversationCreateResponse {
  conversation: {
    id?: string;
    conversation_id?: string;
  };
}

interface ApiEnvelope<T> {
  data?: T;
}

/**
 * Operator-facing entry point for the AI provisioning conversation.
 *
 * Mounted at `/new`. Composes the M1 components into a chat → plan modal →
 * execution-view state machine:
 *
 *   ProjectProvisioningChat (always)
 *     → onOpenPlan(missionId) → fetch plan, open ProvisioningPlanReview
 *       → onApprove → execute → render StepProgressStream + ExecutionPill
 *       → onReject / onClose → return to chat
 */
export const ProvisioningPage: React.FC = () => {
  const [conversationId, setConversationId] = useState<string | null>(null);
  const [conversationError, setConversationError] = useState<string | null>(null);

  const [activeMissionId, setActiveMissionId] = useState<string | null>(null);
  const [plan, setPlan] = useState<ProvisioningPlan | null>(null);
  const [brief, setBrief] = useState<ProjectBrief | undefined>(undefined);
  const [planLoading, setPlanLoading] = useState(false);
  const [planError, setPlanError] = useState<string | null>(null);

  const [viewMode, setViewMode] = useState<ViewMode>('chat');
  const [pillVisible, setPillVisible] = useState(false);
  const [executionStats, setExecutionStats] = useState<{ total: number; completed: number }>({
    total: 0,
    completed: 0,
  });

  // ------------------------------------------------------------------ //
  // Bootstrap a concierge conversation on mount
  // ------------------------------------------------------------------ //
  useEffect(() => {
    let cancelled = false;
    const init = async () => {
      try {
        const response = await apiClient.post<ApiEnvelope<ConversationCreateResponse>>(
          '/ai/conversations/concierge'
        );
        const conv = response.data?.data?.conversation;
        const convId = conv?.conversation_id ?? conv?.id ?? null;
        if (cancelled) return;
        if (convId) {
          setConversationId(convId);
        } else {
          setConversationError('Failed to start a provisioning conversation.');
        }
      } catch (err) {
        logger.error('ProvisioningPage: failed to initialize concierge conversation', err);
        if (!cancelled) setConversationError('Failed to start a provisioning conversation.');
      }
    };
    void init();
    return () => {
      cancelled = true;
    };
  }, []);

  // ------------------------------------------------------------------ //
  // Plan fetch — invoked when the chat surfaces a `plan_ready` event
  // ------------------------------------------------------------------ //
  const handleOpenPlan = useCallback(async (missionId: string) => {
    setActiveMissionId(missionId);
    setViewMode('plan');
    setPillVisible(false);
    setPlan(null);
    setPlanError(null);
    setPlanLoading(true);

    try {
      const response = await apiClient.post<ApiEnvelope<{ plan?: ProvisioningPlan; brief?: ProjectBrief }>>(
        `/ai/missions/${missionId}/compose_plan`
      );
      const envelope = response.data?.data;
      const fetchedPlan = envelope?.plan ?? null;
      if (!fetchedPlan) {
        setPlanError('Plan composition returned an empty payload.');
        return;
      }
      setPlan(fetchedPlan);
      if (envelope?.brief) setBrief(envelope.brief);
    } catch (err) {
      logger.error('ProvisioningPage: failed to compose plan', { missionId, err });
      setPlanError('Failed to load provisioning plan.');
    } finally {
      setPlanLoading(false);
    }
  }, []);

  // ------------------------------------------------------------------ //
  // Plan review actions
  // ------------------------------------------------------------------ //
  const handleApprove = useCallback(async () => {
    if (!activeMissionId || !plan) return;
    try {
      await apiClient.post(`/ai/missions/${activeMissionId}/approve`);
    } catch (err) {
      logger.error('ProvisioningPage: failed to approve plan', { missionId: activeMissionId, err });
    }
    const total = plan.dag?.nodes?.length ?? 0;
    setExecutionStats({ total, completed: 0 });
    setViewMode('executing');
  }, [activeMissionId, plan]);

  const handleReject = useCallback(
    async (reason?: string) => {
      if (!activeMissionId) return;
      try {
        await apiClient.post(`/ai/missions/${activeMissionId}/reject`, { reason });
      } catch (err) {
        logger.error('ProvisioningPage: failed to reject plan', { missionId: activeMissionId, err });
      }
      // Return to chat surface — leave plan/brief in memory in case operator wants to revisit.
      setViewMode('chat');
    },
    [activeMissionId]
  );

  const handleModify = useCallback(() => {
    setViewMode('chat');
  }, []);

  const handleCloseModal = useCallback(() => {
    if (viewMode === 'executing') {
      // Background the modal — switch to floating ExecutionPill
      setPillVisible(true);
    }
    setViewMode('chat');
  }, [viewMode]);

  const handleResumeExecution = useCallback(() => {
    setPillVisible(false);
    setViewMode('executing');
  }, []);

  const handleDismissPill = useCallback(() => {
    setPillVisible(false);
  }, []);

  // Normalize plan steps for StepProgressStream. The plan's `PlanStepStatus`
  // includes a `skipped` value that the live-progress stream doesn't model;
  // collapse it to `pending` so the live updates remain monotonic.
  const progressSteps: ProgressStreamPlanStep[] = useMemo(() => {
    if (!plan?.dag?.nodes) return [];
    const mapStatus = (s?: PlanStepStatus): ProvisioningStepStatus | undefined => {
      if (!s) return undefined;
      if (s === 'skipped') return 'pending';
      return s;
    };
    return plan.dag.nodes.map((step) => ({
      id: step.id,
      label: step.name ?? step.skill ?? step.id,
      description: step.description,
      status: mapStatus(step.status),
    }));
  }, [plan]);

  // ------------------------------------------------------------------ //
  // Render
  // ------------------------------------------------------------------ //
  if (conversationError) {
    return (
      <div className="flex h-full w-full items-center justify-center p-8 text-center">
        <div className="max-w-md rounded-md border border-theme-danger/30 bg-theme-danger/10 p-6 text-sm text-theme-danger">
          {conversationError}
        </div>
      </div>
    );
  }

  if (!conversationId) {
    return (
      <div className="flex h-full w-full items-center justify-center p-8 text-center text-theme-text-secondary">
        <Loader2 className="h-5 w-5 animate-spin mr-2" aria-hidden="true" />
        Starting provisioning session…
      </div>
    );
  }

  const showPlanModal = viewMode === 'plan' || viewMode === 'executing';

  return (
    <div className="flex h-screen w-full flex-col bg-theme-background" data-testid="provisioning-page">
      <header className="border-b border-theme bg-theme-surface px-4 py-3 flex items-center gap-2">
        <Server className="h-5 w-5 text-theme-interactive-primary" aria-hidden="true" />
        <h1 className="text-base font-semibold text-theme-primary">Provision a new project</h1>
      </header>

      <main className="flex-1 overflow-hidden p-4">
        <ProjectProvisioningChat
          conversationId={conversationId}
          onOpenPlan={handleOpenPlan}
        />
      </main>

      {showPlanModal && plan && (
        <ProvisioningPlanReview
          isOpen
          onClose={handleCloseModal}
          missionId={activeMissionId ?? ''}
          plan={plan}
          brief={brief}
          onApprove={handleApprove}
          onReject={handleReject}
          onModify={handleModify}
        />
      )}

      {viewMode === 'plan' && planLoading && (
        <div
          role="status"
          className="fixed inset-0 z-50 flex items-center justify-center bg-theme-background/80"
          data-testid="provisioning-plan-loading"
        >
          <div className="flex items-center gap-2 rounded-md border border-theme bg-theme-surface px-4 py-3 text-sm text-theme-text-secondary shadow-lg">
            <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />
            Composing plan…
          </div>
        </div>
      )}

      {viewMode === 'plan' && planError && (
        <div
          role="alert"
          className="fixed inset-x-4 bottom-4 z-50 rounded-md border border-theme-danger/30 bg-theme-danger/10 p-3 text-sm text-theme-danger shadow-lg"
          data-testid="provisioning-plan-error"
        >
          {planError}
        </div>
      )}

      {viewMode === 'executing' && plan && activeMissionId && (
        <div className="fixed inset-x-0 bottom-16 mx-auto max-w-3xl px-4">
          <StepProgressStream
            missionId={activeMissionId}
            steps={progressSteps}
            onAllComplete={() =>
              setExecutionStats((prev) => ({ total: prev.total, completed: prev.total }))
            }
          />
        </div>
      )}

      {pillVisible && activeMissionId && (
        <ExecutionPill
          missionId={activeMissionId}
          totalSteps={executionStats.total}
          completedSteps={executionStats.completed}
          onClick={handleResumeExecution}
          onClose={handleDismissPill}
        />
      )}
    </div>
  );
};

export default ProvisioningPage;
