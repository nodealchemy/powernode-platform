import type { ApprovalRequest } from '../types/approval';

// How the approval queue is narrowed and ordered (IMP-2184bd06b98e). Pure, so
// the panel only wires it to the URL and the DOM. The queue is the account's
// whole pending list (the server sends it oldest first), and filtering is done
// here rather than on the server: the list is small, the filters are facets of
// what is actually in it, and a decision elsewhere must update the counts
// without a second read.

export type QueueOrder = 'oldest' | 'newest';

/** The severity facet for a request that carries none. */
export const NO_SEVERITY = 'none';

/** '' means "all" for the two facets. */
export interface QueueFilters {
  category: string;
  severity: string;
  needsPerson: boolean;
  order: QueueOrder;
}

export interface QueueFacet {
  value: string;
  count: number;
}

export interface QueueFacets {
  categories: QueueFacet[];
  severities: QueueFacet[];
  needsPerson: number;
}

export const DEFAULT_FILTERS: QueueFilters = { category: '', severity: '', needsPerson: false, order: 'oldest' };

// The URL's names for each filter. `request` is NOT one of them: it is the deep
// link's, and writing the filters must leave it alone.
const PARAM = { category: 'category', severity: 'severity', needsPerson: 'needs_person', order: 'order' } as const;

const SEVERITY_RANK = ['critical', 'high', 'medium', 'low'];

/** What the request is for. Both fields are written by some producer or other. */
export const approvalCategory = (request: ApprovalRequest): string =>
  request.action_category || request.action_type || '';

/**
 * The signal's severity, where the producer recorded one (fleet and campaign
 * requests do, as `payload.signal_severity`); NO_SEVERITY otherwise. Read from
 * request_data, never invented: a request that carries none is not "low".
 */
export const approvalSeverity = (request: ApprovalRequest): string => {
  const data = request.request_data as { payload?: { signal_severity?: unknown }; severity?: unknown } | undefined;
  const raw = data?.payload?.signal_severity ?? data?.severity;
  return typeof raw === 'string' && raw.trim() ? raw.trim().toLowerCase() : NO_SEVERITY;
};

const byCountThenName = (a: QueueFacet, b: QueueFacet) => b.count - a.count || a.value.localeCompare(b.value);

const bySeverity = (a: QueueFacet, b: QueueFacet) => {
  if (a.value === NO_SEVERITY) return b.value === NO_SEVERITY ? 0 : 1;
  if (b.value === NO_SEVERITY) return -1;
  const rank = (value: string) => {
    const index = SEVERITY_RANK.indexOf(value);
    return index === -1 ? SEVERITY_RANK.length : index;
  };
  return rank(a.value) - rank(b.value) || a.value.localeCompare(b.value);
};

const tally = (values: string[]): QueueFacet[] => {
  const counts = new Map<string, number>();
  values.forEach((value) => counts.set(value, (counts.get(value) ?? 0) + 1));
  return Array.from(counts, ([value, count]) => ({ value, count }));
};

/** What the queue holds, counted over the whole (unfiltered) list. */
export const queueFacets = (requests: ApprovalRequest[]): QueueFacets => ({
  categories: tally(requests.map(approvalCategory).filter(Boolean)).sort(byCountThenName),
  severities: tally(requests.map(approvalSeverity)).sort(bySeverity),
  needsPerson: requests.filter((request) => request.requires_human_session === true).length,
});

/** The filters a URL carries, unchecked: see effectiveFilters. */
export const readQueueFilters = (params: URLSearchParams): QueueFilters => ({
  category: params.get(PARAM.category) ?? '',
  severity: params.get(PARAM.severity) ?? '',
  needsPerson: params.get(PARAM.needsPerson) === '1',
  order: params.get(PARAM.order) === 'newest' ? 'newest' : 'oldest',
});

/**
 * Drops a facet value the queue no longer holds. A link can outlive the
 * requests it was made for (every one of them decided since), and a select
 * cannot show a value that is not one of its options, so honouring it would
 * hide the whole queue behind a filter the operator cannot see or clear.
 */
export const effectiveFilters = (filters: QueueFilters, facets: QueueFacets): QueueFilters => ({
  ...filters,
  category: facets.categories.some((facet) => facet.value === filters.category) ? filters.category : '',
  severity: facets.severities.some((facet) => facet.value === filters.severity) ? filters.severity : '',
  needsPerson: filters.needsPerson && facets.needsPerson > 0,
});

export const filtersActive = (filters: QueueFilters): boolean =>
  filters.category !== '' || filters.severity !== '' || filters.needsPerson;

/**
 * The visible queue. `pinnedIds` always stay: the request a deep link names,
 * and the one a push just announced. A toast that says "this needs you" must
 * not land on a queue that has filtered the request away.
 */
export const applyQueueFilters = (
  requests: ApprovalRequest[],
  filters: QueueFilters,
  pinnedIds: ReadonlyArray<string | null | undefined> = []
): ApprovalRequest[] => {
  const matches = (request: ApprovalRequest) =>
    pinnedIds.includes(request.id) ||
    ((filters.category === '' || approvalCategory(request) === filters.category) &&
      (filters.severity === '' || approvalSeverity(request) === filters.severity) &&
      (!filters.needsPerson || request.requires_human_session === true));
  const visible = requests.filter(matches);
  if (filters.order !== 'newest') return visible;
  // Newest first by created_at, with the server's position as the tie-break
  // (it sends oldest first, so a later position is a later request): requests
  // parked in the same instant keep a definite order.
  const position = new Map(requests.map((request, index) => [request.id, index]));
  return [...visible].sort(
    (a, b) =>
      Date.parse(b.created_at) - Date.parse(a.created_at) || (position.get(b.id) ?? 0) - (position.get(a.id) ?? 0)
  );
};

/** The URL's query with the filters written in: only what differs from the default, everything else kept. */
export const writeQueueFilters = (params: URLSearchParams, filters: QueueFilters): URLSearchParams => {
  const next = new URLSearchParams(params);
  const set = (key: string, value: string | null) => (value ? next.set(key, value) : next.delete(key));
  set(PARAM.category, filters.category || null);
  set(PARAM.severity, filters.severity || null);
  set(PARAM.needsPerson, filters.needsPerson ? '1' : null);
  set(PARAM.order, filters.order === 'newest' ? 'newest' : null);
  return next;
};
