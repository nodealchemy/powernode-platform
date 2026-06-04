import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { ClipboardList, Loader2, Server, CheckCircle2, AlertCircle, Sparkles } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { logger } from '@/shared/utils/logger';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { ProvisioningPlanReview } from './ProvisioningPlanReview';
import { provisioningApi } from './services/provisioningApi';
import type { ProjectBrief, ProvisioningPlan } from './types';
import type { AiMessage } from '@/shared/types/ai';

/**
 * Persistent control surface for a provisioning conversation. Mounts above
 * the message list and shows the active mission's phase, missing-fields hint,
 * and phase-appropriate actions (most importantly: re-open the plan review
 * modal). Solves the "no way to control or see status" gap when the chat
 * has scrolled past the relevant cards.
 *
 * Active mission is derived from the latest assistant message whose
 * content_metadata.cards contains a provisioning_* card with a mission_id.
 */
export interface MissionStatusBarProps {
  messages: AiMessage[];
  className?: string;
}

interface MissionState {
  current_phase: string | null;
  status: string | null;
}

interface CardWithMission {
  kind: string;
  mission_id?: string;
  missing_fields?: string[];
  brief?: ProjectBrief;
}

const FIELD_LABELS: Record<string, string> = {
  intent: 'intent',
  use_case: 'use case',
  scale: 'scale',
  regions: 'regions',
  budget_cap_usd_monthly: 'budget cap',
  compliance: 'compliance',
  latency_targets_ms: 'latency target',
  data_residency: 'data residency',
  preferred_provider: 'preferred provider',
};

function deriveLatestProvisioningCard(messages: AiMessage[]): CardWithMission | null {
  for (let i = messages.length - 1; i >= 0; i--) {
    const m = messages[i];
    const cards = (m.metadata?.cards as Array<Record<string, unknown>> | undefined) ?? [];
    for (let j = cards.length - 1; j >= 0; j--) {
      const c = cards[j];
      const kind = c?.kind as string | undefined;
      if (kind?.startsWith('provisioning_')) {
        const payload = (c.payload as Record<string, unknown> | undefined) ?? {};
        const missionId = payload.mission_id as string | undefined;
        if (missionId) {
          return {
            kind,
            mission_id: missionId,
            missing_fields: payload.missing_fields as string[] | undefined,
            brief: payload.brief as ProjectBrief | undefined,
          };
        }
      }
    }
  }
  return null;
}

export const MissionStatusBar: React.FC<MissionStatusBarProps> = ({ messages, className = '' }) => {
  const latestCard = useMemo(() => deriveLatestProvisioningCard(messages), [messages]);
  const missionId = latestCard?.mission_id;

  const [mission, setMission] = useState<MissionState | null>(null);
  const [reviewOpen, setReviewOpen] = useState(false);
  const [plan, setPlan] = useState<ProvisioningPlan | null>(null);
  const [brief, setBrief] = useState<ProjectBrief | undefined>(latestCard?.brief);
  const [loadingPlan, setLoadingPlan] = useState(false);
  const { addNotification } = useNotifications();

  // Refetch mission state whenever the latest provisioning card changes
  // (new card arriving usually means phase advanced).
  useEffect(() => {
    if (!missionId) {
      setMission(null);
      return;
    }
    let cancelled = false;
    provisioningApi
      .getMission(missionId)
      .then((m) => {
        if (cancelled) return;
        if (m) setMission(m);
      })
      .catch((err) => logger.warn('MissionStatusBar: mission fetch failed', { missionId, err }));
    return () => { cancelled = true; };
  }, [missionId, latestCard?.kind, messages.length]);

  // Sync brief from card payload when it updates.
  useEffect(() => {
    if (latestCard?.brief) setBrief(latestCard.brief);
  }, [latestCard?.brief]);

  const openReview = useCallback(async () => {
    if (!missionId) return;
    setLoadingPlan(true);
    try {
      const env = await provisioningApi.composePlan(missionId);
      if (!env?.plan) {
        addNotification({ type: 'error', title: 'Plan unavailable', message: 'Plan not ready yet.' });
        return;
      }
      setPlan(env.plan);
      if (env.brief) setBrief(env.brief);
      setReviewOpen(true);
    } catch (err) {
      logger.error('MissionStatusBar: plan fetch failed', { missionId, err });
      addNotification({ type: 'error', title: 'Plan unavailable', message: 'Could not load the plan.' });
    } finally {
      setLoadingPlan(false);
    }
  }, [missionId, addNotification]);

  const handleApprove = useCallback(async () => {
    if (!missionId) return;
    try {
      await provisioningApi.approveMission(missionId);
      addNotification({ type: 'success', message: 'Plan approved. Provisioning started.' });
    } catch (err) {
      const status = (err as { response?: { status?: number } })?.response?.status;
      if (status !== 409) {
        logger.error('Approve failed', { missionId, err });
        addNotification({ type: 'error', title: 'Approve failed', message: 'Could not approve.' });
        throw err;
      }
    }
    setReviewOpen(false);
  }, [missionId, addNotification]);

  const handleReject = useCallback(async (reason?: string) => {
    if (!missionId) return;
    try {
      await provisioningApi.rejectMission(missionId, reason);
      addNotification({ type: 'success', message: 'Plan rejected.' });
    } catch (err) {
      logger.error('Reject failed', { missionId, err });
    }
    setReviewOpen(false);
  }, [missionId, addNotification]);

  if (!missionId) return null;

  const phase = mission?.current_phase;
  const missingFields = latestCard?.missing_fields ?? [];

  const indicator = (() => {
    if (phase === 'review_plan') {
      return {
        icon: <ClipboardList className="h-4 w-4 text-theme-interactive-primary" />,
        label: 'Plan ready for review',
        variant: 'info' as const,
        action: (
          <Button size="sm" variant="primary" onClick={openReview} disabled={loadingPlan} data-testid="mission-bar-review">
            {loadingPlan ? 'Loading…' : 'Review plan'}
          </Button>
        ),
      };
    }
    if (phase === 'compose_plan') {
      return {
        icon: <Loader2 className="h-4 w-4 text-theme-info animate-spin" />,
        label: 'Composing plan…',
        variant: 'info' as const,
        action: null,
      };
    }
    if (phase === 'execute' || phase === 'executing') {
      return {
        icon: <Server className="h-4 w-4 text-theme-info" />,
        label: 'Provisioning in progress',
        variant: 'info' as const,
        action: null,
      };
    }
    if (phase === 'adapt' || phase === 'adapting') {
      return {
        icon: <Loader2 className="h-4 w-4 text-theme-warning animate-spin" />,
        label: 'Adapting plan',
        variant: 'warning' as const,
        action: null,
      };
    }
    if (phase === 'completed' || mission?.status === 'completed') {
      return {
        icon: <CheckCircle2 className="h-4 w-4 text-theme-success" />,
        label: 'Provisioned',
        variant: 'success' as const,
        action: null,
      };
    }
    if (phase === 'failed' || mission?.status === 'failed') {
      return {
        icon: <AlertCircle className="h-4 w-4 text-theme-danger" />,
        label: 'Provisioning failed',
        variant: 'danger' as const,
        action: null,
      };
    }
    // Default: capture_intent / brief sketch state
    return {
      icon: <Sparkles className="h-4 w-4 text-theme-info" />,
      label: missingFields.length > 0 ? 'Brief incomplete' : 'Capturing intent',
      variant: 'info' as const,
      action: null,
    };
  })();

  const missingHint = missingFields.length > 0
    ? `Tell the assistant: ${missingFields.map((f) => FIELD_LABELS[f] ?? f).join(', ')}`
    : null;

  return (
    <>
      <div
        className={`flex items-center gap-3 border-b border-theme bg-theme-surface px-4 py-2 text-sm ${className}`.trim()}
        data-testid="mission-status-bar"
      >
        {indicator.icon}
        <Badge variant={indicator.variant} size="sm">{indicator.label}</Badge>
        {missingHint && <span className="text-theme-secondary text-xs truncate" title={missingHint}>{missingHint}</span>}
        <div className="ml-auto flex items-center gap-2">{indicator.action}</div>
      </div>
      {reviewOpen && plan && missionId && (
        <ProvisioningPlanReview
          isOpen
          onClose={() => setReviewOpen(false)}
          missionId={missionId}
          plan={plan}
          brief={brief}
          onApprove={handleApprove}
          onReject={handleReject}
          onModify={() => setReviewOpen(false)}
        />
      )}
    </>
  );
};

export default MissionStatusBar;
