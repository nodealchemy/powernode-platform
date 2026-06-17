/**
 * Shared autonomy types — used by every extension's autonomy settings UI
 * (System and future extensions). Lives in core because autonomy is a
 * platform-wide feature, not an extension-specific one.
 */

export type AutonomyLevel = 'block' | 'require_approval' | 'notify_and_proceed' | 'auto_approve';

/**
 * Configuration for the parameterized useAutonomyConfig hook so any extension
 * can wire up a Settings UI against its own API endpoints. Each extension
 * provides its own AutonomyConfigSource; the hook itself is generic.
 */
export interface AutonomyConfigSource {
  /** GET endpoint that returns { policies: { [agentName]: { [action]: { policy, ... } } } } */
  fetchEndpoint: string;
  /** PATCH endpoint for bulk updates. Accepts { policies, agent_role } body. */
  updateEndpoint: string;
  /** Map agent display name → role string used in the PATCH body (extension-specific). */
  roleForAgent: (agentName: string) => string | undefined;
}

/** Per-agent policy map: { agentName: { action: level } } — frontend working state */
export type AgentPoliciesMap = Record<string, Record<string, AutonomyLevel>>;
