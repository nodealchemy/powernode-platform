import React from 'react';
import { ArrowUpRight, Sparkles, ShieldAlert, CreditCard, BarChart3 } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';

export type UpgradeReason =
  | 'max_active_instances_exceeded'
  | 'free_hours_exhausted'
  | 'no_subscription'
  | 'llm_cost_cap_exceeded'
  | 'quota_check_unavailable'
  | string;

export interface UpgradeRequiredCardProps {
  /**
   * Reason code returned by the backend quota / cost guard. Recognized values
   * get a tailored heading + body; unknown reasons fall back to a generic
   * "plan limit hit" card so we never blank-render.
   */
  reason: UpgradeReason;
  /** Spend already accrued today (used for the cost-cap variant). */
  spent?: number | null;
  /**
   * Daily / monthly cap that was hit (used for the cost-cap variant).
   * Nullable: the backend contract always SENDS the key, null when unknown.
   */
  cap?: number | null;
  /**
   * Custom CTA destination. Nullable for the same reason as `cap` — and note
   * a default parameter does NOT fire on null, so the fallback is applied
   * with `??` in the body rather than in the signature.
   */
  upgradeUrl?: string | null;
  className?: string;
}

interface ReasonCopy {
  icon: React.ElementType;
  iconClass: string;
  ringClass: string;
  heading: string;
  body: (props: UpgradeRequiredCardProps) => React.ReactNode;
  /**
   * Suppress the "Upgrade plan" CTA. Set for reasons that are NOT a plan
   * limit — pointing a user at checkout because our own billing check failed
   * would sell them something that cannot fix their problem.
   */
  hideCta?: boolean;
}

const formatUsd = (value?: number | null): string => {
  if (typeof value !== 'number' || Number.isNaN(value)) return '$0.00';
  return `$${value.toFixed(2)}`;
};

const REASON_COPY: Record<string, ReasonCopy> = {
  max_active_instances_exceeded: {
    icon: BarChart3,
    iconClass: 'text-theme-warning-fg',
    ringClass: 'bg-theme-warning-fg/10',
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
    iconClass: 'text-theme-info-fg',
    ringClass: 'bg-theme-info-fg/10',
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
    iconClass: 'text-theme-danger-fg',
    ringClass: 'bg-theme-danger-fg/10',
    heading: "You've hit today's AI spend cap",
    body: ({ spent, cap }) => (
      <p className="text-sm text-theme-secondary">
        You've used <span className="font-semibold text-theme-primary">{formatUsd(spent)}</span>{' '}
        of your <span className="font-semibold text-theme-primary">{formatUsd(cap)}</span> daily AI
        cap. Upgrade to raise the limit and keep iterating on your plan today.
      </p>
    ),
  },
  // NOT a plan limit — the quota check itself failed and the backend denied
  // rather than provisioning unmetered (BillingBridge fails CLOSED). Saying
  // "you hit your plan's limit" here would be a false statement to the user.
  quota_check_unavailable: {
    icon: ShieldAlert,
    iconClass: 'text-theme-warning-fg',
    ringClass: 'bg-theme-warning-fg/10',
    heading: "We couldn't check your plan limits",
    body: () => (
      <p className="text-sm text-theme-secondary">
        Billing is temporarily unreachable, so we held off on provisioning rather than
        starting something we can't meter. Nothing was created — try again in a moment.
      </p>
    ),
    hideCta: true,
  },
};

const FALLBACK: ReasonCopy = {
  icon: ShieldAlert,
  iconClass: 'text-theme-warning-fg',
  ringClass: 'bg-theme-warning-fg/10',
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
  upgradeUrl,
  className = '',
}) => {
  const copy = REASON_COPY[reason] ?? FALLBACK;
  // `??` not a default parameter: the backend sends an explicit null.
  const ctaHref = upgradeUrl ?? '/checkout';
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
          {copy.body({ reason, spent, cap, upgradeUrl: ctaHref })}
          {!copy.hideCta && (
            <div className="pt-1">
              <a
                href={ctaHref}
                data-testid="upgrade-required-cta"
                className="inline-flex items-center gap-1.5 px-4 py-2 rounded-md text-sm font-medium bg-theme-interactive-primary text-white hover:opacity-90 transition-opacity"
              >
                Upgrade plan
                <ArrowUpRight className="h-4 w-4" aria-hidden="true" />
              </a>
            </div>
          )}
        </div>
      </div>
    </Card>
  );
};

export default UpgradeRequiredCard;
