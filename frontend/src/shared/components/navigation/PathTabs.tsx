import React from 'react';
import { Link, useLocation } from 'react-router-dom';

/**
 * PathTabs — a shared presentational scaffold for path-based tab hubs.
 *
 * Renders a permission-filtered tab bar (one `<Link>` per accessible tab, with
 * the tab the URL is inside accented) plus a permission-gated empty state when
 * the operator can see none of the tabs. The active route content is supplied
 * by the caller as children (its own `<Routes>`), keeping this component purely
 * presentational.
 *
 * Extracted from the near-identical AcmePage / IngressPage scaffolds so both
 * hubs share one implementation, and since IMP-d725a6bad253 the sole tab strip
 * for every system hub. Tabs are filtered by `hasPermission`, the active key
 * comes from `activeTabKeyFromPath` below, and the empty state lists the
 * permissions an admin must grant.
 *
 * Path-based tabs per feedback_path_based_tabs.
 */

export interface PathTabSpec<TKey extends string = string> {
  key: TKey;
  label: string;
  permission: string;
  icon?: React.ReactNode;
}

interface PathTabsProps<TKey extends string = string> {
  /** Tab definitions in display order. */
  tabs: PathTabSpec<TKey>[];
  /** URL prefix the tab keys append to, e.g. `/app/system/acme`. */
  basePath: string;
  /** Permission predicate (from usePermissions). */
  hasPermission: (permission: string) => boolean;
  /**
   * Rendered when the operator can access none of the tabs. Optional: callers
   * that guard the empty case themselves (e.g. with a standalone container)
   * can omit it, in which case nothing is rendered when no tab is accessible.
   */
  emptyState?: React.ReactNode;
  /**
   * The active route content — typically the caller's own `<Routes>` whose
   * default/catchall paths redirect to the first accessible tab.
   */
  children: React.ReactNode;
}

/**
 * The tab whose route `pathname` is inside, or `undefined` when the path names
 * no tab at all (e.g. the bare hub path).
 *
 * Matches a tab's own segment AND anything nested beneath it, mirroring
 * SubNavRail's rule. That matters for hubs whose tabs own sub-routes:
 * `/app/system/compute/platform/services` resolves to `platform`, not to the
 * trailing `services` segment that belongs to the tab's inner router.
 *
 * Exported so callers that also key page actions off the active tab derive it
 * the same way the strip does, instead of hand-rolling a second rule.
 */
export function activeTabKeyFromPath<TKey extends string = string>(
  tabs: PathTabSpec<TKey>[],
  basePath: string,
  pathname: string,
): TKey | undefined {
  return tabs.find(
    (t) =>
      pathname === `${basePath}/${t.key}` || pathname.startsWith(`${basePath}/${t.key}/`),
  )?.key;
}

export function PathTabs<TKey extends string = string>({
  tabs,
  basePath,
  hasPermission,
  emptyState,
  children,
}: PathTabsProps<TKey>): React.ReactElement {
  const location = useLocation();

  const accessibleTabs = tabs.filter((t) => hasPermission(t.permission));
  const activeKey = (() => {
    // Derived against ALL tabs, not just the accessible ones: a path that
    // names a tab the operator cannot see must highlight nothing rather than
    // put the accent on a different tab's label while that tab's body is on
    // screen. Only a path that names no tab at all (the bare hub path, which
    // the caller's index route is about to redirect) falls back to the first
    // accessible tab.
    const matched = activeTabKeyFromPath(tabs, basePath, location.pathname);
    if (matched === undefined) return accessibleTabs[0]?.key;
    return accessibleTabs.find((t) => t.key === matched)?.key;
  })();

  if (accessibleTabs.length === 0) {
    return <>{emptyState ?? null}</>;
  }

  return (
    <>
      <nav className="flex flex-wrap items-center gap-1 border-b border-theme mb-4">
        {accessibleTabs.map((tab) => {
          const isActive = activeKey === tab.key;
          return (
            <Link
              key={tab.key}
              to={`${basePath}/${tab.key}`}
              className={`px-3 py-2 text-sm inline-flex items-center gap-2 border-b-2 transition-colors ${
                isActive
                  ? 'border-theme-info-border text-theme-primary font-medium'
                  : 'border-transparent text-theme-secondary hover:text-theme-primary'
              }`}
            >
              {tab.icon}
              {tab.label}
            </Link>
          );
        })}
      </nav>
      {children}
    </>
  );
}

/**
 * Convenience: the first-accessible-tab redirect target a caller's default
 * and catchall `<Route>`s should point at. Returns `null` when no tab is
 * accessible (the PathTabs empty state covers that case).
 */
export function firstAccessibleTabPath<TKey extends string = string>(
  tabs: PathTabSpec<TKey>[],
  basePath: string,
  hasPermission: (permission: string) => boolean,
): string | null {
  const first = tabs.find((t) => hasPermission(t.permission));
  return first ? `${basePath}/${first.key}` : null;
}

export default PathTabs;
