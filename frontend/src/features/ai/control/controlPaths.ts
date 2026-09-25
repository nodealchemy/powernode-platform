/** AI → Control: the one page for approvals, policies, budgets, safety, trust and compliance audit. */
export const CONTROL_BASE_PATH = '/app/ai/control';

/**
 * The approval queue. Links carry `?request=<id>` to open one request; they
 * must target this tab directly, since a redirect from the leaf index would
 * drop the query string.
 */
export const CONTROL_APPROVALS_PATH = `${CONTROL_BASE_PATH}/approvals/queue`;

/**
 * Every permission that opens some part of Control: the route guard. The
 * ControlPage suite pins this to the leaves' own gates, so it cannot drift.
 */
export const CONTROL_PERMISSIONS: string[] = [
  'ai.agents.read',
  'ai.proposals.view',
  'ai.escalations.view',
  'ai.approval_chains.manage',
  'ai.intervention_policies.manage',
  'ai.governance.read',
  'ai.kill_switch.manage',
  'ai.security.manage',
  'ai.feedback.view',
  'ai.goals.manage',
];
