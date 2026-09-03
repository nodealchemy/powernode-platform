import React, { useMemo, useState } from 'react';
import {
  ShieldCheck,
  CheckCircle2,
  XCircle,
  MessageSquare,
  AlertTriangle,
  Edit3,
  Circle,
  CheckCircle,
  Loader2,
  AlertCircle,
  SkipForward,
  PauseCircle
} from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { logger } from '@/shared/utils/logger';
import { StackTopologyPreview } from './StackTopologyPreview';
import { CostBreakdown } from './CostBreakdown';
import type {
  ProvisioningPlan,
  PlanStep,
  PlanStepStatus,
  ProjectBrief,
  RiskFactor,
  RiskSeverity
} from './types';

export interface ProvisioningPlanReviewProps {
  isOpen: boolean;
  onClose: () => void;
  missionId: string;
  plan: ProvisioningPlan;
  /** Optional brief used to compose the header summary. */
  brief?: ProjectBrief;
  onApprove: () => Promise<void>;
  onReject: (reason?: string) => Promise<void>;
  /** Closes the modal and returns the user to the chat surface. */
  onModify: () => void;
  /** Optional per-step edit hook — concierge surface uses this to seed a chat reply. */
  onEditStep?: (stepId: string) => void;
  className?: string;
}

const RISK_VARIANT: Record<RiskSeverity, 'success' | 'warning' | 'danger'> = {
  low: 'success',
  med: 'warning',
  high: 'danger'
};

const RISK_LABEL: Record<RiskSeverity, string> = {
  low: 'Low risk',
  med: 'Medium risk',
  high: 'High risk'
};

const RISK_BG: Record<string, string> = {
  low: 'bg-theme-success-fg/10 border-theme-success-border/30',
  med: 'bg-theme-warning-fg/10 border-theme-warning-border/30',
  high: 'bg-theme-danger-fg/10 border-theme-danger-border/30'
};

const stepIcon = (status: PlanStepStatus | undefined): React.ReactElement => {
  switch (status) {
    case 'completed':
      return <CheckCircle className="w-4 h-4 text-theme-success-fg" aria-label="completed" />;
    // `executing` is the server's in-flight value in Ai::GoalPlanStep::STATUSES —
    // the snapshot hands the raw column through — and `running` is the legacy
    // client-side alias. Both are in flight; neither is "not started yet".
    case 'executing':
    case 'running':
      return <Loader2 className="w-4 h-4 text-theme-info-fg animate-spin" aria-label="running" />;
    case 'failed':
      return <AlertCircle className="w-4 h-4 text-theme-danger-fg" aria-label="failed" />;
    case 'skipped':
      return <SkipForward className="w-4 h-4 text-theme-tertiary" aria-label="skipped" />;
    // Parked on an autonomy gate (SkillCompositionRunner::PARKED_STATUS) —
    // dispatched, blocked on a human, nothing applied. Falling through to the
    // pending circle read as "not started yet".
    case 'awaiting_approval':
      return (
        <PauseCircle className="w-4 h-4 text-theme-warning-fg" aria-label="awaiting approval" />
      );
    default:
      return <Circle className="w-4 h-4 text-theme-secondary" aria-label="pending" />;
  }
};

const formatBudget = (cap?: number | null): string => {
  if (cap == null) return 'no budget cap';
  return `$${cap.toLocaleString(undefined, { maximumFractionDigits: 0 })}/mo cap`;
};

const formatUsd = (value: number): string =>
  `$${value.toLocaleString(undefined, { maximumFractionDigits: 2 })}`;

/**
 * ProvisioningPlanReview — the only hard-gate modal in the M1 provisioning UX.
 *
 * Composes:
 *   - the captured brief summary in the header
 *   - the DAG steps in the left rail with per-step Edit and status icons
 *   - a contained `<StackTopologyPreview />` on the right
 *   - a `<CostBreakdown />` plus risk chips below
 *   - footer actions: Reject / Modify-in-chat / Approve & Provision
 *
 * The footer Reject button progressively reveals a rejection-note textarea —
 * the first click expands it, the second click submits. This keeps the simple
 * "I just don't like this" path one-click while still allowing operators to
 * leave a structured reason for the audit trail without a separate dialog.
 */
export const ProvisioningPlanReview: React.FC<ProvisioningPlanReviewProps> = ({
  isOpen,
  onClose,
  missionId,
  plan,
  brief,
  onApprove,
  onReject,
  onModify,
  onEditStep,
  className = ''
}) => {
  const [submitting, setSubmitting] = useState(false);
  const [rejectionNote, setRejectionNote] = useState('');
  const [showRejectionInput, setShowRejectionInput] = useState(false);

  const steps = plan.dag?.nodes ?? [];

  const handleApprove = async () => {
    setSubmitting(true);
    try {
      await onApprove();
    } catch (err) {
      logger.error('Failed to approve provisioning plan', {
        missionId,
        planId: plan.plan_id,
        error: err instanceof Error ? err.message : String(err)
      });
    } finally {
      setSubmitting(false);
    }
  };

  const handleRejectClick = async () => {
    if (!showRejectionInput) {
      setShowRejectionInput(true);
      return;
    }
    setSubmitting(true);
    try {
      await onReject(rejectionNote.trim() || undefined);
    } catch (err) {
      logger.error('Failed to reject provisioning plan', {
        missionId,
        planId: plan.plan_id,
        error: err instanceof Error ? err.message : String(err)
      });
    } finally {
      setSubmitting(false);
    }
  };

  const briefSummary = useMemo(() => {
    if (!brief) return null;
    const intent = brief.intent || brief.use_case;
    const regions = brief.regions?.length ? brief.regions.join(', ') : 'no region selected';
    const budget = formatBudget(brief.budget_cap_usd_monthly ?? undefined);
    if (!intent) return `${regions} · ${budget}`;
    return `${intent} · ${regions} · ${budget}`;
  }, [brief]);

  // Defensive — partial plans (e.g. server-side compose_plan returning early
  // before cost/topology/risk are filled) may be missing these blocks. The
  // body renders placeholders below when they're undefined; here we only need
  // the totals for the footer summary, so coerce to zero.
  const monthlyTotal = plan.cost_estimate?.monthly_usd ?? 0;
  const oneTimeTotal = plan.cost_estimate?.one_time_usd ?? 0;

  const footer = (
    <div className="flex flex-1 flex-wrap items-center gap-2 justify-end">
      {showRejectionInput && (
        <textarea
          value={rejectionNote}
          onChange={(e) => setRejectionNote(e.target.value)}
          placeholder="Reason for rejection (optional)…"
          rows={1}
          className="input-theme text-xs flex-1 min-w-[200px] mr-2"
          data-testid="provisioning-rejection-note"
        />
      )}
      <Button
        variant="ghost"
        onClick={onModify}
        disabled={submitting}
        data-testid="provisioning-modify-btn"
      >
        <MessageSquare className="w-4 h-4 mr-1.5" />
        Modify in chat
      </Button>
      <Button
        variant="danger"
        onClick={handleRejectClick}
        disabled={submitting}
        loading={submitting && showRejectionInput}
        data-testid="provisioning-reject-btn"
      >
        <XCircle className="w-4 h-4 mr-1.5" />
        {showRejectionInput ? 'Confirm reject' : 'Reject'}
      </Button>
      <Button
        variant="primary"
        onClick={handleApprove}
        disabled={submitting || showRejectionInput}
        loading={submitting && !showRejectionInput}
        data-testid="provisioning-approve-btn"
      >
        <CheckCircle2 className="w-4 h-4 mr-1.5" />
        Approve &amp; Provision
      </Button>
    </div>
  );

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Review provisioning plan"
      subtitle={briefSummary ?? `Plan ${plan.plan_id?.slice(0, 8) ?? '(pending)'}`}
      icon={<ShieldCheck />}
      maxWidth="5xl"
      footer={footer}
      className={className}
    >
      <div className="space-y-4" data-testid="provisioning-plan-review">
        {/* Header row: brief recap + modify-in-chat shortcut */}
        <div className="flex flex-wrap items-start justify-between gap-3 pb-3 border-b border-theme">
          <div className="min-w-0">
            <p className="text-xs text-theme-secondary uppercase tracking-wide font-medium">
              Reviewing
            </p>
            <p className="text-sm text-theme-primary mt-0.5 break-words" data-testid="provisioning-brief-summary">
              {briefSummary ?? 'Plan composed from concierge intent capture.'}
            </p>
          </div>
          <Button
            variant="ghost"
            size="sm"
            onClick={onModify}
            data-testid="provisioning-modify-header"
          >
            <MessageSquare className="w-3.5 h-3.5 mr-1.5" />
            Modify in chat
          </Button>
        </div>

        {/* Body: steps left, topology right; stacks below 768px */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <section data-testid="provisioning-steps">
            <h4 className="text-sm font-semibold text-theme-primary mb-2 flex items-center gap-2">
              Steps
              <Badge variant="default" size="xs">{steps.length}</Badge>
            </h4>
            {steps.length === 0 ? (
              <p className="text-xs text-theme-tertiary italic">No steps composed yet.</p>
            ) : (
              <ol className="space-y-2 max-h-[320px] overflow-y-auto pr-1 custom-scrollbar">
                {steps.map((step, idx) => (
                  <PlanStepItem
                    key={step.id ?? `step-${idx}`}
                    step={step}
                    index={idx}
                    onEditStep={onEditStep}
                  />
                ))}
              </ol>
            )}
          </section>

          <section data-testid="provisioning-topology">
            <h4 className="text-sm font-semibold text-theme-primary mb-2">Topology preview</h4>
            {plan.topology_preview ? (
              <StackTopologyPreview
                topology={plan.topology_preview}
                width="100%"
                height={320}
                className="w-full"
              />
            ) : (
              <p className="text-xs text-theme-tertiary italic">
                Topology not yet available — backend returned a partial plan.
              </p>
            )}
          </section>
        </div>

        {/* Cost + risk row */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {plan.cost_estimate ? (
            <CostBreakdown estimate={plan.cost_estimate} />
          ) : (
            <section
              className="rounded-lg border border-theme bg-theme-surface p-4"
              data-testid="provisioning-cost-missing"
            >
              <h4 className="text-sm font-semibold text-theme-primary mb-2">Cost estimate</h4>
              <p className="text-xs text-theme-tertiary italic">
                Cost estimate not yet computed.
              </p>
            </section>
          )}
          <section
            className="rounded-lg border border-theme bg-theme-surface p-4"
            data-testid="provisioning-risk"
          >
            <div className="flex items-center justify-between mb-3">
              <div className="flex items-center gap-2">
                <AlertTriangle className="w-4 h-4 text-theme-warning-fg" />
                <h4 className="text-sm font-semibold text-theme-primary">Risk assessment</h4>
              </div>
              {plan.risk?.severity != null && (
                <Badge variant={RISK_VARIANT[plan.risk.severity]} size="sm">
                  {RISK_LABEL[plan.risk.severity]} · {plan.risk.score}
                </Badge>
              )}
            </div>
            {!plan.risk ? (
              <p className="text-xs text-theme-tertiary italic">Risk assessment not yet computed.</p>
            ) : plan.risk.factors?.length === 0 ? (
              <p className="text-xs text-theme-tertiary italic">No risk factors detected.</p>
            ) : (
              <ul className="space-y-2">
                {(plan.risk.factors ?? []).map((factor, idx) => (
                  <RiskChip key={`${factor.name}-${idx}`} factor={factor} />
                ))}
              </ul>
            )}
          </section>
        </div>

        {/* Authorization line */}
        <div
          className="text-xs text-theme-secondary bg-theme-warning-fg/10 border border-theme-warning-border/30 rounded-lg px-3 py-2"
          data-testid="provisioning-authorization"
        >
          By approving you authorize creation of resources costing approximately{' '}
          <strong className="text-theme-primary">{formatUsd(monthlyTotal)}/mo</strong>{' '}
          and{' '}
          <strong className="text-theme-primary">{formatUsd(oneTimeTotal)}</strong>{' '}
          one-time charges.
        </div>
      </div>
    </Modal>
  );
};

interface PlanStepItemProps {
  step: PlanStep;
  index: number;
  onEditStep?: (stepId: string) => void;
}

const PlanStepItem: React.FC<PlanStepItemProps> = ({ step, index, onEditStep }) => {
  const stepKey = step.id ?? `step-${index}`;
  return (
    <li
      className="flex items-start gap-2 p-2.5 rounded-lg border border-theme bg-theme-surface"
      data-testid={`provisioning-step-${stepKey}`}
    >
      <span className="flex-shrink-0 mt-0.5">{stepIcon(step.status)}</span>
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <span className="text-xs font-medium text-theme-tertiary">
            {String(index + 1).padStart(2, '0')}
          </span>
          <span className="text-sm font-medium text-theme-primary truncate">
            {step.name || step.action || step.skill || 'Step'}
          </span>
        </div>
        {step.description && (
          <p className="text-xs text-theme-secondary mt-0.5 line-clamp-2">
            {step.description}
          </p>
        )}
        {step.skill && (
          <code className="text-[10px] text-theme-tertiary font-mono">
            {step.skill}
          </code>
        )}
      </div>
      {onEditStep && step.id && (
        <button
          type="button"
          onClick={() => onEditStep(step.id)}
          className="flex-shrink-0 p-1 rounded text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-hover"
          aria-label={`Edit step ${index + 1}`}
          data-testid={`provisioning-step-edit-${stepKey}`}
        >
          <Edit3 className="w-3.5 h-3.5" />
        </button>
      )}
    </li>
  );
};

interface RiskChipProps {
  factor: RiskFactor;
}

const RiskChip: React.FC<RiskChipProps> = ({ factor }) => {
  const severity = (['low', 'med', 'high'].includes(factor.severity)
    ? factor.severity
    : 'low') as RiskSeverity;
  const bg = RISK_BG[severity] ?? RISK_BG.low;
  return (
    <li
      className={`rounded-md border px-2.5 py-1.5 ${bg}`}
      data-testid={`risk-factor-${factor.name}`}
    >
      <div className="flex items-center justify-between gap-2">
        <span className="text-xs font-medium text-theme-primary">{factor.name}</span>
        <span className="text-[10px] text-theme-tertiary">
          weight {factor.weight.toFixed(2)}
        </span>
      </div>
      <p className="text-xs text-theme-secondary mt-0.5">{factor.explanation}</p>
    </li>
  );
};

export default ProvisioningPlanReview;
