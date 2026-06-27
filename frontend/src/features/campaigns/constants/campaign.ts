import type { CampaignStatus, DecisionAuthority } from '../types/campaign';

type BadgeVariant = 'default' | 'primary' | 'secondary' | 'success' | 'warning' | 'danger' | 'info' | 'outline';

export const STATUS_CONFIG: Record<CampaignStatus, { label: string; variant: BadgeVariant }> = {
  created: { label: 'Created', variant: 'secondary' },
  active: { label: 'Active', variant: 'success' },
  paused: { label: 'Paused', variant: 'warning' },
  completed: { label: 'Completed', variant: 'info' },
  archived: { label: 'Archived', variant: 'outline' },
};

export const DECISION_AUTHORITY_OPTIONS: Array<{ value: DecisionAuthority; label: string; description: string }> = [
  { value: 'supervised', label: 'Supervised', description: 'Park every non-trivial decision for the operator.' },
  { value: 'monitored', label: 'Monitored', description: 'Decide low-risk items; park anything ambiguous.' },
  { value: 'trusted', label: 'Trusted', description: 'Decide design/architecture per best practice; park only irreversible / policy items.' },
  { value: 'autonomous', label: 'Autonomous', description: 'Decide everything reversible; park only live-credential / external-irreversible.' },
];

export const DECISION_AUTHORITY_LABELS: Record<DecisionAuthority, string> = {
  supervised: 'Supervised',
  monitored: 'Monitored',
  trusted: 'Trusted',
  autonomous: 'Autonomous',
};
