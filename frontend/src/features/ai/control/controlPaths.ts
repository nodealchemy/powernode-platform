/** AI → Control: the one page for approvals, policies, budgets, safety, trust and compliance audit. */
export const CONTROL_BASE_PATH = '/app/ai/control';

/**
 * The approval queue. Links carry `?request=<id>` to open one request; they
 * must target this tab directly, since a redirect from the leaf index would
 * drop the query string.
 */
export const CONTROL_APPROVALS_PATH = `${CONTROL_BASE_PATH}/approvals/queue`;

/** Every permission that opens some part of Control (defined in shared for the nav gate). */
export { CONTROL_PERMISSIONS } from '@/shared/constants/controlPermissions';
