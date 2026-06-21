/**
 * Shared types for globally-scoped foundational content (skills, prompt
 * templates, mission/team/agent/devops templates, knowledge bases).
 *
 * Each such item is either GLOBAL (platform-provided, `account_id == null`,
 * read-only to accounts) or ACCOUNT-owned (`account_id` set, editable). An
 * account copy that was forked from a global item carries `cloned_from_id`
 * (its origin) and `source_key` (stable provenance key), and can be refreshed
 * from its origin via the update-from-source 3-way merge.
 *
 * These mirror the backend `GloballyScopable` model concern. Only fields the
 * API actually returns are declared here.
 */

/** Segmented scope selection that drives the `?scope=` list query param. */
export type ContentScope = 'global' | 'custom' | 'all';

/**
 * The provenance/scoping fields every globally-scopable item's JSON includes.
 * Content models extend their own shape with this.
 */
export interface ScopedContent {
  id: string;
  /** `null` for global (platform-managed, read-only) items. */
  account_id: string | null;
  /** Origin id when this is an account copy forked from another item. */
  cloned_from_id?: string | null;
  /** Stable provenance key shared by an origin and its clones. */
  source_key?: string | null;
}

/**
 * 3-way diff of an account copy vs its origin, returned by
 * `GET .../:id/update_from_source/preview` and echoed by the POST.
 *
 *  - `pulled`    — fields auto-applied from the origin (origin changed, the
 *                  user did not).
 *  - `conflicts` — fields both the origin and the user changed; the user must
 *                  choose per field. `base` is the origin's current value
 *                  ("Take origin"), `yours` is the account copy's value
 *                  ("Keep mine").
 *  - `synced`    — true when there are no outstanding conflicts (fully merged).
 */
export interface UpdateFromSourceConflict {
  base: unknown;
  yours: unknown;
}

export interface UpdateFromSourcePreview {
  pulled: string[];
  conflicts: Record<string, UpdateFromSourceConflict>;
  synced: boolean;
  /** Present (`"no_origin"`) only if the item has no origin to merge from. */
  error?: string;
}

/** Per-field resolution map POSTed to `update_from_source`. */
export type ConflictResolutions = Record<string, unknown>;
