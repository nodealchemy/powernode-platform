import React from 'react';
import { Link } from 'react-router-dom';
import { ArrowUpRight, CheckCircle2, ClipboardList, Layers, Server, TrendingUp, Wrench } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import type { ChatCard } from '@/shared/types/ai';
import { BriefCard } from './BriefCard';
import type { ProjectBrief, ProvisioningPlan, PlanStep, RiskFactor } from './types';

/**
 * Renders a single ChatCard (surfaced from a Concierge tool result via
 * `assistant_message.content_metadata.cards`) inline in the standard chat.
 *
 * Each card kind picks a compact renderer suited for inline display, plus a
 * "Open in provisioning" deep-link to `/app/system/provision?mission_id=…`
 * for the full flow when the user wants to drill in.
 */
export interface ChatProvisioningCardSlotProps {
  card: ChatCard;
  className?: string;
}

const PROVISION_PATH = '/app/system/provision';

export const ChatProvisioningCardSlot: React.FC<ChatProvisioningCardSlotProps> = ({
  card,
  className = ''
}) => {
  const missionId = (card.payload?.mission_id as string | undefined) ?? undefined;
  const deepLinkHref = missionId
    ? `${PROVISION_PATH}?mission_id=${encodeURIComponent(missionId)}`
    : PROVISION_PATH;

  const inner = renderInner(card);
  if (!inner) return null;

  return (
    <div className={`mt-3 ${className}`.trim()} data-testid={`chat-card-${card.kind}`}>
      {inner}
      <div className="mt-2 flex justify-end">
        <Link
          to={deepLinkHref}
          className="inline-flex items-center gap-1 text-xs font-medium text-theme-interactive-primary hover:underline"
          data-testid={`chat-card-${card.kind}-deeplink`}
        >
          Open in provisioning
          <ArrowUpRight className="h-3 w-3" />
        </Link>
      </div>
    </div>
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
