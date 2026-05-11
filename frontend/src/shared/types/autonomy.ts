/**
 * Shared autonomy types — used by every extension's autonomy settings UI
 * (Trading, System, future). Lives in core because autonomy is a platform-wide
 * feature, not a Trading-specific one.
 */

export type AutonomyLevel = 'block' | 'require_approval' | 'notify_and_proceed' | 'auto_approve';

export interface AutonomyPolicy {
  id?: string;
  action_category: string;
  scope: 'global' | 'agent' | 'action_type';
  policy: AutonomyLevel;
  priority?: number;
  is_active?: boolean;
  agent_id?: string | null;
  agent_name?: string | null;
  approval_chain_id?: string | null;
  approval_chain_name?: string | null;
  conditions?: Record<string, unknown>;
  preferred_channels?: string[];
}

/**
 * Configuration for the parameterized useAutonomyConfig hook so any extension
 * can wire up a Settings UI against its own API endpoints. Trading and System
 * each provide their own AutonomyConfigSource; the hook itself is generic.
 */
export interface AutonomyConfigSource {
  /** GET endpoint that returns { policies: { [agentName]: { [action]: { policy, ... } } } } */
  fetchEndpoint: string;
  /** PATCH endpoint for bulk updates. Accepts { policies, agent_role } body. */
  updateEndpoint: string;
  /** Map agent display name → role string used in the PATCH body (extension-specific). */
  roleForAgent: (agentName: string) => string | undefined;
}

export interface AutonomyAgentInfo {
  id: string;
  name: string;
  status?: string;
  trust_tier?: string | null;
  overall_score?: number | null;
}

/** Per-agent policy map: { agentName: { action: level } } — frontend working state */
export type AgentPoliciesMap = Record<string, Record<string, AutonomyLevel>>;
