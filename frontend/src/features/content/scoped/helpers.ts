/**
 * Read-only gating helpers for globally-scoped foundational content.
 *
 * Global items (`account_id == null`) are platform-managed and read-only —
 * Edit/Delete must be disabled and a "Clone to customize" CTA shown instead.
 * Account copies forked from a global item (those with `cloned_from_id`) can be
 * refreshed from their origin via update-from-source.
 */
/** Minimal shapes the gating helpers need (tolerant of optional fields). */
interface HasAccountId {
  account_id?: string | null;
}
interface HasClonedFromId {
  cloned_from_id?: string | null;
}

/** True when the item is platform-provided (global) and read-only. */
export function isGlobal(item: HasAccountId | null | undefined): boolean {
  return item?.account_id == null;
}

/** True when the item is an account-owned copy forked from another item. */
export function isClone(item: HasClonedFromId | null | undefined): boolean {
  return item?.cloned_from_id != null && item.cloned_from_id !== '';
}

/**
 * Whether the current user may edit/delete this item: it must be account-owned
 * (not global) AND the user must hold the relevant write permission.
 *
 * @param item    the content item
 * @param canWrite result of the caller's permission check (e.g.
 *                 `hasPermission('ai.skills.update')`)
 */
export function canEditContent(
  item: HasAccountId | null | undefined,
  canWrite: boolean,
): boolean {
  return canWrite && !isGlobal(item);
}
