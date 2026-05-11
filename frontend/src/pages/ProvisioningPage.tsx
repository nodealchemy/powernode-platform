import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { Loader2, Server, X } from 'lucide-react';
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
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  // Allow deep-linking to a specific mission (e.g. from a Concierge chat
  // card "Open in provisioning"). When present, the page auto-fetches that
  // mission's plan instead of waiting for the chat to surface plan_ready.
  const initialMissionId = searchParams.get('mission_id');

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
  // Phase → ViewMode mapping. Called after fetching mission state on mount
  // or deep-link to decide which surface to show. Without this, refreshing
  // a deep-linked mission_id always re-opened the Approve modal even if
  // the mission had already advanced past review_plan.
  // ------------------------------------------------------------------ //
  // Returns true if the mission is finished — refreshing a deep link to a
  // finished mission should NOT pop up the execution overlay. Treat finished
  // as: terminal mission status, OR phase past `execute`, OR all plan steps
  // completed in `execute` (the steady state for a successful provision).
  const isMissionFinished = (
    phase: string | null | undefined,
    status: string | null | undefined,
    plan: ProvisioningPlan | null
  ): boolean => {
    if (status === 'completed' || status === 'cancelled' || status === 'failed') return true;
    if (phase === 'handoff' || phase === 'completed' || phase === 'adapting') return true;
    // execute + every step done = nothing left to watch live
    if (phase === 'execute' && plan?.dag?.nodes?.length) {
      const allDone = plan.dag.nodes.every(
        (n) => n.status === 'completed' || n.status === 'skipped'
      );
      if (allDone) return true;
    }
    return false;
  };

  const phaseToViewMode = (phase: string | undefined | null): ViewMode => {
    switch (phase) {
      case 'execute':
      case 'verify':
        return 'executing';
      case 'capture_intent':
      case 'compose_plan':
      case 'review_plan':
      default:
        return 'plan';
    }
  };

  // ------------------------------------------------------------------ //
  // Plan fetch — invoked when the chat surfaces a `plan_ready` event,
  // OR on mount when the URL carries ?mission_id=… Two fetches in parallel:
  //   1. /missions/:id            — current_phase + status (gate viewMode)
  //   2. /missions/:id/compose_plan — idempotent plan snapshot
  // ------------------------------------------------------------------ //
  const handleOpenPlan = useCallback(async (missionId: string) => {
    setActiveMissionId(missionId);
    setPillVisible(false);
    setPlan(null);
    setPlanError(null);
    setPlanLoading(true);

    try {
      const [missionResponse, planResponse] = await Promise.all([
        apiClient.get<ApiEnvelope<{ mission?: { current_phase?: string; status?: string } }>>(
          `/ai/missions/${missionId}`
        ),
        apiClient.post<ApiEnvelope<{ plan?: ProvisioningPlan; brief?: ProjectBrief }>>(
          `/ai/missions/${missionId}/compose_plan`
        ),
      ]);

      const phase = missionResponse.data?.data?.mission?.current_phase ?? null;
      const status = missionResponse.data?.data?.mission?.status ?? null;
      const envelope = planResponse.data?.data;
      const fetchedPlan = envelope?.plan ?? null;

      // Finished mission on a refreshed deep link: drop the mission_id from
      // the URL, hand the user a fresh chat surface. Avoids the dead "100%
      // complete" overlay popping over the page on every refresh.
      if (isMissionFinished(phase, status, fetchedPlan)) {
        setActiveMissionId(null);
        setPlan(null);
        setBrief(undefined);
        setViewMode('chat');
        // Strip ?mission_id=… without a navigation/scroll-jump.
        if (typeof window !== 'undefined' && window.history?.replaceState) {
          const url = new URL(window.location.href);
          url.searchParams.delete('mission_id');
          window.history.replaceState({}, '', url.toString());
        }
        return;
      }

      // Decide viewMode FROM phase, not from "is there a plan". A completed
      // mission still has a plan, but the user shouldn't see Approve.
      setViewMode(phaseToViewMode(phase));

      if (!fetchedPlan) {
        setPlanError('Plan composition returned an empty payload.');
        return;
      }
      setPlan(fetchedPlan);
      if (envelope?.brief) setBrief(envelope.brief);

      if (phaseToViewMode(phase) === 'executing') {
        const total = fetchedPlan.dag?.nodes?.length ?? 0;
        setExecutionStats({ total, completed: 0 });
      }
    } catch (err) {
      logger.error('ProvisioningPage: failed to load mission/plan', { missionId, err });
      setPlanError('Failed to load provisioning plan.');
      setViewMode('plan');
    } finally {
      setPlanLoading(false);
    }
  }, []);

  // ------------------------------------------------------------------ //
  // Deep-link bootstrap: when arriving via /app/system/provision?mission_id=X
  // (e.g. from a card click in the standard concierge chat), auto-fetch and
  // open the plan for that mission. Runs once on mount; ignored if no
  // mission_id was passed.
  // ------------------------------------------------------------------ //
  useEffect(() => {
    if (!initialMissionId || !conversationId) return;
    void handleOpenPlan(initialMissionId);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [initialMissionId, conversationId]);

  // ------------------------------------------------------------------ //
  // Plan review actions
  // ------------------------------------------------------------------ //
  const handleApprove = useCallback(async () => {
    if (!activeMissionId || !plan) return;
    try {
      await apiClient.post(`/ai/missions/${activeMissionId}/approve`);
      const total = plan.dag?.nodes?.length ?? 0;
      setExecutionStats({ total, completed: 0 });
      setViewMode('executing');
    } catch (err) {
      // 409 NO_APPROVAL_GATE means the mission is already past review_plan
      // (e.g. operator clicked Approve from a stale UI after the mission
      // already advanced — happens on refresh of an old deep link). Treat
      // as success and surface the executing view; the StepProgressStream
      // will reflect terminal state if provisioning has finished.
      const status = (err as { response?: { status?: number } })?.response?.status;
      if (status === 409) {
        const total = plan.dag?.nodes?.length ?? 0;
        setExecutionStats({ total, completed: 0 });
        setViewMode('executing');
        return;
      }
      logger.error('ProvisioningPage: failed to approve plan', { missionId: activeMissionId, err });
    }
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
      <div className="flex h-full w-full items-center justify-center p-8 text-center text-theme-secondary">
        <Loader2 className="h-5 w-5 animate-spin mr-2" aria-hidden="true" />
        Starting provisioning session…
      </div>
    );
  }

  // Modal is for plan review only. During 'executing' the StepProgressStream
  // below renders the live progress; previously the modal stayed open in
  // 'executing' too, which kept showing the Approve button on top of an
  // already-approved mission.
  const showPlanModal = viewMode === 'plan';

  return (
    <div className="flex h-screen w-full flex-col bg-theme-background" data-testid="provisioning-page">
      <header className="border-b border-theme bg-theme-surface px-4 py-3 flex items-center gap-2">
        <Server className="h-5 w-5 text-theme-interactive-primary" aria-hidden="true" />
        <h1 className="text-base font-semibold text-theme-primary">Provision a new project</h1>
        <button
          type="button"
          onClick={() => navigate('/app')}
          className="ml-auto rounded p-1.5 text-theme-tertiary hover:bg-theme-background-secondary hover:text-theme-primary"
          aria-label="Close provisioning page"
          data-testid="provisioning-page-close"
        >
          <X className="h-4 w-4" aria-hidden="true" />
        </button>
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
          <div className="flex items-center gap-2 rounded-md border border-theme bg-theme-surface px-4 py-3 text-sm text-theme-secondary shadow-lg">
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
        <div className="fixed inset-x-0 bottom-16 mx-auto max-w-3xl px-4" data-testid="provisioning-execution-overlay">
          <div className="relative">
            <button
              type="button"
              onClick={() => setViewMode('chat')}
              className="absolute -top-2 -right-2 z-10 rounded-full border border-theme bg-theme-surface p-1.5 text-theme-tertiary shadow-sm hover:bg-theme-background-secondary hover:text-theme-primary"
              aria-label="Dismiss execution view"
              data-testid="provisioning-execution-dismiss"
            >
              <X className="h-3.5 w-3.5" aria-hidden="true" />
            </button>
            <StepProgressStream
              missionId={activeMissionId}
              steps={progressSteps}
              onAllComplete={() =>
                setExecutionStats((prev) => ({ total: prev.total, completed: prev.total }))
              }
            />
          </div>
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
