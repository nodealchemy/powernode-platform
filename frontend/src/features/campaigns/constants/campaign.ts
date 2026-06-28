import type { CampaignStatus, DecisionAuthority, ProposalStatus, DriverKind } from '../types/campaign';

type BadgeVariant = 'default' | 'primary' | 'secondary' | 'success' | 'warning' | 'danger' | 'info' | 'outline';

export const STATUS_CONFIG: Record<CampaignStatus, { label: string; variant: BadgeVariant }> = {
  created: { label: 'Created', variant: 'secondary' },
  active: { label: 'Active', variant: 'success' },
  paused: { label: 'Paused', variant: 'warning' },
  completed: { label: 'Completed', variant: 'info' },
  archived: { label: 'Archived', variant: 'outline' },
};

export const PROPOSAL_STATUS_CONFIG: Record<ProposalStatus, { label: string; variant: BadgeVariant }> = {
  proposed: { label: 'Proposed', variant: 'secondary' },
  queued: { label: 'Queued', variant: 'info' },
  approved: { label: 'Approved', variant: 'primary' },
  rejected: { label: 'Rejected', variant: 'danger' },
  spawned: { label: 'Spawned', variant: 'success' },
};

export const DRIVER_KIND_OPTIONS: Array<{ value: DriverKind; label: string }> = [
  { value: 'claude_code', label: 'Claude Code (dev-loop)' },
  { value: 'platform_agent', label: 'Platform agent' },
  { value: 'platform_team', label: 'Platform team' },
  { value: 'platform_mission', label: 'Platform mission' },
];

export const DRIVER_KIND_LABELS: Record<DriverKind, string> = {
  claude_code: 'Claude Code',
  platform_agent: 'Platform agent',
  platform_team: 'Platform team',
  platform_mission: 'Platform mission',
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
