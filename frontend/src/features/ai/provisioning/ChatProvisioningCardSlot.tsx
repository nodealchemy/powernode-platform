import React, { useCallback, useState } from 'react';
import { CheckCircle2, ClipboardList, Layers, Server, TrendingUp, Wrench } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { logger } from '@/shared/utils/logger';
import { useNotifications } from '@/shared/hooks/useNotifications';
import type { ChatCard } from '@/shared/types/ai';
import { BriefCard } from './BriefCard';
import { ProvisioningPlanReview } from './ProvisioningPlanReview';
import { provisioningApi } from './services/provisioningApi';
import type { ProjectBrief, ProvisioningPlan, PlanStep, RiskFactor } from './types';
import { PlatformDeploymentWizardCard } from './PlatformDeploymentWizardCard';

/**
 * Renders a single ChatCard (surfaced from a Concierge tool result via
 * `assistant_message.content_metadata.cards`) inline in the standard chat.
 *
 * Plan cards (`provisioning_plan`) get a "Review plan" button that opens
 * ProvisioningPlanReview as an inline modal, keeping the user in the same
 * conversation. Previously this slot deep-linked to /app/system/provision
 * which bootstrapped a *new* concierge conversation, dropping the user
 * out of their current chat.
 */
export interface ChatProvisioningCardSlotProps {
  card: ChatCard;
  className?: string;
}

export const ChatProvisioningCardSlot: React.FC<ChatProvisioningCardSlotProps> = ({
  card,
  className = ''
}) => {
  const missionId = (card.payload?.mission_id as string | undefined) ?? undefined;
  const inner = renderInner(card);
  if (!inner) return null;

  return (
    <div className={`mt-3 ${className}`.trim()} data-testid={`chat-card-${card.kind}`}>
      {inner}
      {card.kind === 'provisioning_plan' && missionId && (
        <PlanReviewLauncher card={card} missionId={missionId} />
      )}
    </div>
  );
};

interface PlanReviewLauncherProps {
  card: ChatCard;
  missionId: string;
}

const PlanReviewLauncher: React.FC<PlanReviewLauncherProps> = ({ card, missionId }) => {
  const [isOpen, setIsOpen] = useState(false);
  const [plan, setPlan] = useState<ProvisioningPlan | null>(
    (card.payload?.plan as ProvisioningPlan | undefined) ?? null
  );
  const [brief, setBrief] = useState<ProjectBrief | undefined>(
    (card.payload?.brief as ProjectBrief | undefined) ?? undefined
  );
  const [loading, setLoading] = useState(false);
  const { addNotification } = useNotifications();

  const handleOpen = useCallback(async () => {
    if (plan) {
      // Card payload already carries the plan — open immediately, refresh
      // in the background so a stale card still shows but updates if the
      // mission moved on.
      setIsOpen(true);
      provisioningApi
        .composePlan(missionId)
        .then((env) => {
          if (env?.plan) setPlan(env.plan);
          if (env?.brief) setBrief(env.brief);
        })
        .catch((err) => logger.warn('Plan refresh failed', { missionId, err }));
      return;
    }

    setLoading(true);
    try {
      const env = await provisioningApi.composePlan(missionId);
      if (!env?.plan) {
        addNotification({ type: 'error', title: 'Plan unavailable', message: 'Plan composition returned no plan.' });
        return;
      }
      setPlan(env.plan);
      if (env.brief) setBrief(env.brief);
      setIsOpen(true);
    } catch (err) {
      logger.error('Failed to load plan for review', { missionId, err });
      addNotification({ type: 'error', title: 'Plan unavailable', message: 'Could not load the plan for review.' });
    } finally {
      setLoading(false);
    }
  }, [plan, missionId, addNotification]);

  const handleApprove = useCallback(async () => {
    try {
      await provisioningApi.approveMission(missionId);
      addNotification({ type: 'success', message: 'Plan approved. Provisioning started.' });
    } catch (err) {
      const status = (err as { response?: { status?: number } })?.response?.status;
      if (status === 409) {
        addNotification({ type: 'info', message: 'Mission already past review.' });
      } else {
        logger.error('Failed to approve plan', { missionId, err });
        addNotification({ type: 'error', title: 'Approve failed', message: 'Could not approve the plan.' });
        throw err;
      }
    }
    setIsOpen(false);
  }, [missionId, addNotification]);

  const handleReject = useCallback(async (reason?: string) => {
    try {
      await provisioningApi.rejectMission(missionId, reason);
      addNotification({ type: 'success', message: 'Plan rejected. Continue refining in chat.' });
    } catch (err) {
      logger.error('Failed to reject plan', { missionId, err });
      addNotification({ type: 'error', title: 'Reject failed', message: 'Could not reject the plan.' });
    }
    setIsOpen(false);
  }, [missionId, addNotification]);

  const handleModify = useCallback(() => {
    setIsOpen(false);
  }, []);

  return (
    <>
      <div className="mt-2 flex justify-end">
        <Button
          size="sm"
          variant="primary"
          onClick={handleOpen}
          disabled={loading}
          data-testid={`chat-card-${card.kind}-review`}
        >
          {loading ? 'Loading…' : 'Review plan'}
        </Button>
      </div>
      {isOpen && plan && (
        <ProvisioningPlanReview
          isOpen
          onClose={() => setIsOpen(false)}
          missionId={missionId}
          plan={plan}
          brief={brief}
          onApprove={handleApprove}
          onReject={handleReject}
          onModify={handleModify}
        />
      )}
    </>
  );
};

function renderInner(card: ChatCard): React.ReactElement | null {
  switch (card.kind) {
    case 'provisioning_brief': {
      const brief = card.payload?.brief as ProjectBrief | undefined;
      const missing = (card.payload?.missing_fields as string[] | undefined) ?? [];
      if (!brief) return null;
      return <BriefCard brief={brief} missingFields={missing} />;
    }

    case 'provisioning_plan':
    case 'provisioning_plan_approved': {
      const plan = card.payload?.plan as ProvisioningPlan | undefined;
      if (!plan) return null;
      const stepCount = plan.dag?.nodes?.length ?? 0;
      const monthlyCost =
        (card.payload?.cost as { monthly_usd?: number } | undefined)?.monthly_usd
        ?? plan.cost_estimate?.monthly_usd;
      const risk = (card.payload?.risk as { score?: number; severity?: string } | undefined)
        ?? plan.risk;
      const approved = card.kind === 'provisioning_plan_approved';

      return (
        <Card className="p-3">
          <div className="flex items-start gap-3">
            <span className="flex h-9 w-9 flex-shrink-0 items-center justify-center rounded-md bg-theme-interactive-primary/10 text-theme-interactive-primary">
              <ClipboardList className="h-5 w-5" />
            </span>
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2 text-sm font-semibold text-theme-primary">
                {approved ? 'Plan approved' : 'Plan ready for review'}
                {approved && <CheckCircle2 className="h-4 w-4 text-theme-success" />}
              </div>
              <div className="mt-1 flex flex-wrap items-center gap-2 text-xs text-theme-secondary">
                <span>{stepCount} step{stepCount === 1 ? '' : 's'}</span>
                {monthlyCost != null && (
                  <span>· ~${monthlyCost.toFixed ? monthlyCost.toFixed(2) : monthlyCost}/mo</span>
                )}
                {risk?.severity && (
                  <Badge variant={riskVariant(String(risk.severity))} size="sm">
                    {String(risk.severity)} risk
                  </Badge>
                )}
              </div>
              {plan.dag?.nodes?.length ? (
                <ol className="mt-2 list-decimal pl-5 text-xs text-theme-secondary space-y-0.5">
                  {plan.dag.nodes.slice(0, 5).map((step: PlanStep) => (
                    <li key={step.id}>{step.name ?? step.skill ?? step.id}</li>
                  ))}
                  {plan.dag.nodes.length > 5 && (
                    <li className="list-none italic">
                      …and {plan.dag.nodes.length - 5} more
                    </li>
                  )}
                </ol>
              ) : null}
            </div>
          </div>
        </Card>
      );
    }

    case 'provisioning_execution': {
      const total = (card.payload?.total_steps as number | undefined)
        ?? (card.payload?.steps as unknown[] | undefined)?.length
        ?? 0;
      const completed = (card.payload?.completed_steps as number | undefined) ?? 0;
      const status = (card.payload?.status as string | undefined) ?? 'running';
      const variant = status === 'failed' ? 'danger' : status === 'completed' ? 'success' : 'info';

      return (
        <Card className="p-3">
          <div className="flex items-start gap-3">
            <span className="flex h-9 w-9 flex-shrink-0 items-center justify-center rounded-md bg-theme-interactive-primary/10 text-theme-interactive-primary">
              <Server className="h-5 w-5" />
            </span>
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2 text-sm font-semibold text-theme-primary">
                Provisioning underway
                <Badge variant={variant} size="sm">
                  {status}
                </Badge>
              </div>
              <p className="mt-1 text-xs text-theme-secondary">
                {completed} of {total} step{total === 1 ? '' : 's'} complete
              </p>
              {total > 0 && (
                <div className="mt-2 h-1.5 w-full overflow-hidden rounded-full bg-theme-background-secondary">
                  <div
                    className="h-full bg-theme-interactive-primary transition-[width] duration-300"
                    style={{ width: `${Math.round((completed / total) * 100)}%` }}
                  />
                </div>
              )}
            </div>
          </div>
        </Card>
      );
    }

    case 'provisioning_status': {
      const summary = (card.payload?.summary as string | undefined) ?? 'Mission status updated';
      const phase = card.payload?.phase as string | undefined;
      return (
        <Card className="p-3">
          <div className="flex items-start gap-3">
            <span className="flex h-9 w-9 flex-shrink-0 items-center justify-center rounded-md bg-theme-info/10 text-theme-info">
              <Layers className="h-5 w-5" />
            </span>
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2 text-sm font-semibold text-theme-primary">
                {summary}
                {phase && <Badge variant="outline" size="sm">{phase}</Badge>}
              </div>
            </div>
          </div>
        </Card>
      );
    }

    case 'provisioning_adaptation': {
      const summary = (card.payload?.summary as string | undefined) ?? 'Adaptation proposed';
      const factors = (card.payload?.factors as RiskFactor[] | undefined) ?? [];
      return (
        <Card className="p-3">
          <div className="flex items-start gap-3">
            <span className="flex h-9 w-9 flex-shrink-0 items-center justify-center rounded-md bg-theme-warning/10 text-theme-warning">
              <Wrench className="h-5 w-5" />
            </span>
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2 text-sm font-semibold text-theme-primary">
                <TrendingUp className="h-4 w-4 text-theme-warning" />
                {summary}
              </div>
              {factors.length > 0 && (
                <ul className="mt-1 list-disc pl-5 text-xs text-theme-secondary space-y-0.5">
                  {factors.slice(0, 3).map((f, i) => (
                    <li key={i}>{f.name ?? 'factor'}</li>
                  ))}
                </ul>
              )}
            </div>
          </div>
        </Card>
      );
    }

    // D3 — Platform deployment wizard. Renders inline form (form phase)
    // or done-summary with acceptance_token capture (done phase).
    case 'platform_deployment_wizard':
      return <PlatformDeploymentWizardCard card={card} />;

    default:
      return null;
  }
}

function riskVariant(severity: string): 'success' | 'warning' | 'danger' | 'outline' {
  switch (severity.toLowerCase()) {
    case 'low':
      return 'success';
    case 'med':
    case 'medium':
      return 'warning';
    case 'high':
    case 'critical':
      return 'danger';
    default:
      return 'outline';
  }
}

export default ChatProvisioningCardSlot;
