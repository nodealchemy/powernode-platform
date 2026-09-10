import { apiClient } from '@/shared/services/apiClient';
import type {
  ComponentAction,
  ComponentStatusIndexData,
  ComponentStatusShowData,
  ComponentStatusRollupData,
  ComponentStatusImpactData,
} from '@/shared/types/platformStatus';

// The four reads of the component status plane (design §6), against
// `Api::V1::Platform::ComponentStatusesController`. All four are gated on
// `platform.status.read` server-side; this module never assumes the caller
// holds it, and the page hides itself when they do not.
//
// THE FOUR READS ARE THE ONLY THINGS THIS MODULE KNOWS THE SHAPE OF. There is
// one write helper below — `runComponentAction` (C3) — and the distinction it
// preserves is the one that matters: it issues whatever method and path a ROW
// declared, to a door this module has never heard of, under a permission the
// row named. It is a courier, not an endpoint client. `platform.status.read`
// buys the picture; every actuation is gated somewhere else, twice.

/** Server route prefix. The api client already carries `/api/v1`. */
const BASE = '/platform/component_statuses';

/**
 * Query parameters the REST door accepts. All optional; each is echoed back in
 * the response's `filters` so a caller can tell which question produced an
 * empty page.
 */
export interface PlatformStatusQuery {
  kind?: string;
  verdict?: string;
  /**
   * THREE-VALUED (design §4.6), and the third value is the reason this is a
   * string rather than a nullable id:
   *
   *   undefined        → every row: in-plane, plane-less, every plane
   *   'none'           → the plane-less rows ONLY
   *   <id | slug>      → that plane's rows PLUS the plane-less ones, and never
   *                      another plane's
   *
   * Sending `environment: undefined` and sending `environment: 'none'` are
   * different questions. Axios drops undefined params, which is what makes the
   * first case work; never "helpfully" default this to anything.
   */
  environment?: string;
  page?: number;
  per_page?: number;
}

/** What a list read returns, plus the pagination the envelope carries beside it. */
export interface ComponentStatusIndexResult extends ComponentStatusIndexData {
  pagination: {
    current_page: number;
    per_page: number;
    total_count: number;
    total_pages: number;
  };
}

/**
 * The page's list read.
 *
 * `per_page` defaults to 100 — the server's maximum — rather than its default
 * of 20. The design sizes the reference fleet at ~150 components, and a status
 * grid silently showing 20 of them is worse than one that says so: the page
 * renders "showing N of M" from `pagination.total_count` whenever the two
 * differ. A real pager belongs with the drawer work, not here.
 */
export const fetchComponentStatuses = async (
  query: PlatformStatusQuery = {}
): Promise<ComponentStatusIndexResult> => {
  const response = await apiClient.get(BASE, {
    params: { per_page: 100, ...query },
  });
  const data = response.data?.data ?? {};
  const pagination = response.data?.meta?.pagination ?? {};

  return {
    // Defaulted rather than trusted: an envelope that omitted the key would
    // otherwise crash the grid on `.map`, and a status page that white-screens
    // is the one page that must not.
    component_statuses: data.component_statuses ?? [],
    filters: data.filters ?? {},
    unknown_environment: data.unknown_environment ?? false,
    pagination: {
      current_page: pagination.current_page ?? 1,
      per_page: pagination.per_page ?? 100,
      total_count: pagination.total_count ?? (data.component_statuses?.length ?? 0),
      total_pages: pagination.total_pages ?? 1,
    },
  };
};

/**
 * The dual rollup (design §4.1) plus the per-kind breakdown.
 *
 * `rollup` covers this account's rows; `shared` covers the process-wide ones,
 * and the two are NOT summed — folding one shared circuit breaker into the
 * account verdict would turn it into every tenant's outage.
 */
export const fetchStatusRollup = async (
  query: PlatformStatusQuery = {}
): Promise<ComponentStatusRollupData> => {
  const response = await apiClient.get(`${BASE}/rollup`, { params: query });
  return response.data?.data;
};

/** One component's detail plus its downstream impact. Used by the drawer (C3). */
export const fetchComponentStatus = async (id: string): Promise<ComponentStatusShowData> => {
  const response = await apiClient.get(`${BASE}/${id}`);
  return response.data?.data;
};

/**
 * Impact plus ranked root-cause candidates. The response carries
 * `heuristic: true` and a `heuristic_basis` string, and any surface rendering
 * the ranking must render that label with it — an unlabelled ranking gets read
 * as an answer rather than as correlation over the dependency graph.
 */
export const fetchComponentImpact = async (id: string): Promise<ComponentStatusImpactData> => {
  const response = await apiClient.get(`${BASE}/${id}/impact`);
  return response.data?.data;
};

/**
 * Issue one of a component's declared actions.
 *
 * ── THIS FUNCTION KNOWS NOTHING ABOUT THE ACTION ───────────────────────────
 *
 * The method, the path and the permission all come from the row. Core learns
 * nothing kind-specific: a contributor declares `{key, label, method, path,
 * permission, destructive, confirm}` and the page renders a button that sends
 * exactly that. Adding "cordon a node" to the drawer is a contributor change in
 * an extension and no edit here.
 *
 * ── THE PERMISSION IS CHECKED TWICE, AND NEITHER CHECK IS THIS ONE ─────────
 *
 * The caller hides the button when the viewer lacks `action.permission`, and
 * the door the action names checks it again server-side. The first is a
 * courtesy — it stops an operator clicking something that will refuse — and the
 * second is the actual gate. Holding `platform.status.read` authorizes neither.
 * This function deliberately does NOT check anything: a client-side check
 * placed here would look like the enforcement point and it is not one.
 *
 * @param reason Sent as `reason` when the action declared `confirm.requires_reason`.
 *   It travels with the request so the far side can audit WHY, not just what.
 */
export const runComponentAction = async (
  action: Pick<ComponentAction, 'method' | 'path'>,
  options: { reason?: string } = {}
): Promise<unknown> => {
  const body = options.reason ? { reason: options.reason } : undefined;

  switch (action.method) {
    case 'POST':
      return (await apiClient.post(action.path, body)).data;
    case 'PUT':
      return (await apiClient.put(action.path, body)).data;
    case 'PATCH':
      return (await apiClient.patch(action.path, body)).data;
    case 'DELETE':
      // axios `delete` carries no body argument here, so a reason rides as a
      // query param rather than being silently dropped. A destructive action
      // whose reason vanished on the way to the audit log is worse than one
      // that refuses.
      return (
        await apiClient.delete(action.path, options.reason ? { params: { reason: options.reason } } : undefined)
      ).data;
    default: {
      // Exhaustive over ComponentAction['method']: a method added to the type
      // without a case here is a compile error, not a silently dropped click.
      const unreachable: never = action.method;
      throw new Error(`Unsupported action method: ${String(unreachable)}`);
    }
  }
};
