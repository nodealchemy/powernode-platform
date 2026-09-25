/**
 * Every permission that opens some part of AI → Control: the route guard and
 * the nav gate. It lives in shared so the navigation config does not depend on
 * a feature; the ControlPage suite pins it to the leaves' own gates, so it
 * cannot drift.
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
