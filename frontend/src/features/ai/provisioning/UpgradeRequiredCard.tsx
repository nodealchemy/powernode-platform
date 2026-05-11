import React from 'react';
import { ArrowUpRight, Sparkles, ShieldAlert, CreditCard, BarChart3 } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';

export type UpgradeReason =
  | 'max_active_instances_exceeded'
  | 'free_hours_exhausted'
  | 'no_subscription'
  | 'llm_cost_cap_exceeded'
  | string;

export interface UpgradeRequiredCardProps {
  /**
   * Reason code returned by the backend quota / cost guard. Recognized values
   * get a tailored heading + body; unknown reasons fall back to a generic
   * "plan limit hit" card so we never blank-render.
   */
  reason: UpgradeReason;
  /** Spend already accrued today (used for the cost-cap variant). */
  spent?: number;
  /** Daily / monthly cap that was hit (used for the cost-cap variant). */
  cap?: number;
  /** Custom CTA destination — defaults to "/checkout". */
  upgradeUrl?: string;
  className?: string;
}

interface ReasonCopy {
  icon: React.ElementType;
  iconClass: string;
  ringClass: string;
  heading: string;
  body: (props: UpgradeRequiredCardProps) => React.ReactNode;
}

const formatUsd = (value?: number): string => {
  if (typeof value !== 'number' || Number.isNaN(value)) return '$0.00';
  return `$${value.toFixed(2)}`;
};

const REASON_COPY: Record<string, ReasonCopy> = {
  max_active_instances_exceeded: {
    icon: BarChart3,
    iconClass: 'text-theme-warning',
    ringClass: 'bg-theme-warning/10',
    heading: "You've hit your plan's instance cap",
    body: () => (
      <p className="text-sm text-theme-secondary">
        Your current plan caps the number of active instances you can run. Upgrade to
        keep provisioning new infrastructure without taking anything down first.
      </p>
    ),
  },
  free_hours_exhausted: {
    icon: Sparkles,
    iconClass: 'text-theme-info',
    ringClass: 'bg-theme-info/10',
    heading: "You're out of free runtime",
    body: () => (
      <p className="text-sm text-theme-secondary">
        Free-tier hours for this billing period are used up. Upgrade to keep your stack
        online and unlock the rest of the provisioning workflow.
      </p>
    ),
  },
  no_subscription: {
    icon: CreditCard,
    iconClass: 'text-theme-interactive-primary',
    ringClass: 'bg-theme-interactive-primary/10',
    heading: 'Add a plan to keep going',
    body: () => (
      <p className="text-sm text-theme-secondary">
        Provisioning live infrastructure needs an active subscription. Pick a plan that
        matches what you want to ship — you can change it anytime.
      </p>
    ),
  },
  llm_cost_cap_exceeded: {
    icon: ShieldAlert,
    iconClass: 'text-theme-danger',
    ringClass: 'bg-theme-danger/10',
    heading: "You've hit today's AI spend cap",
    body: ({ spent, cap }) => (
      <p className="text-sm text-theme-secondary">
        You've used <span className="font-semibold text-theme-primary">{formatUsd(spent)}</span>{' '}
        of your <span className="font-semibold text-theme-primary">{formatUsd(cap)}</span> daily AI
        cap. Upgrade to raise the limit and keep iterating on your plan today.
      </p>
    ),
  },
};

const FALLBACK: ReasonCopy = {
  icon: ShieldAlert,
  iconClass: 'text-theme-warning',
  ringClass: 'bg-theme-warning/10',
  heading: "Hit your plan's limit",
  body: () => (
    <p className="text-sm text-theme-secondary">
      Your current plan doesn't cover this action. Upgrade to unlock the next step in
      provisioning.
    </p>
  ),
};

/**
 * UpgradeRequiredCard — concierge-conversation paywall surface.
 *
 * Renders inline inside `ProjectProvisioningChat` whenever the backend's
 * provisioning tool returns `requires_upgrade: true`. Mirrors the layout of
 * `ConciergeActionCard` (icon chip + heading + body + CTA) so the chat
 * experience stays visually consistent.
 *
 * Accepts a free-form `reason` so it can render specific copy for the four
 * known cases (`max_active_instances_exceeded`, `free_hours_exhausted`,
 * `no_subscription`, `llm_cost_cap_exceeded`) and a sensible fallback
 * otherwise.
 */
export const UpgradeRequiredCard: React.FC<UpgradeRequiredCardProps> = ({
  reason,
  spent,
  cap,
  upgradeUrl = '/checkout',
  className = '',
}) => {
  const copy = REASON_COPY[reason] ?? FALLBACK;
  const Icon = copy.icon;

  return (
    <Card
      variant="default"
      padding="md"
      className={className}
      data-testid="upgrade-required-card"
      data-reason={reason}
    >
      <div className="flex items-start gap-3">
        <div
          className={`shrink-0 w-10 h-10 rounded-lg flex items-center justify-center ${copy.ringClass}`}
          aria-hidden="true"
        >
          <Icon className={`h-5 w-5 ${copy.iconClass}`} />
        </div>
        <div className="flex-1 min-w-0 space-y-2">
          <h4 className="text-sm font-semibold text-theme-primary">{copy.heading}</h4>
          {copy.body({ reason, spent, cap, upgradeUrl })}
          <div className="pt-1">
            <a
              href={upgradeUrl}
              data-testid="upgrade-required-cta"
              className="inline-flex items-center gap-1.5 px-4 py-2 rounded-md text-sm font-medium bg-theme-interactive-primary text-white hover:opacity-90 transition-opacity"
            >
              Upgrade plan
              <ArrowUpRight className="h-4 w-4" aria-hidden="true" />
            </a>
          </div>
        </div>
      </div>
    </Card>
  );
};

export default UpgradeRequiredCard;
