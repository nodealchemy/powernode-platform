import React from 'react';
import { Link, useLocation } from 'react-router-dom';

/**
 * PathTabs — a shared presentational scaffold for path-based tab hubs.
 *
 * Renders a permission-filtered tab bar (one `<Link>` per accessible tab,
 * derived from the URL's last path segment) plus a permission-gated empty
 * state when the operator can see none of the tabs. The active route content
 * is supplied by the caller as children (its own `<Routes>`), keeping this
 * component purely presentational.
 *
 * Extracted from the near-identical AcmePage / IngressPage scaffolds so both
 * hubs share one implementation. Behavior is preserved exactly: tabs are
 * filtered by `hasPermission`, the active key is derived from the trailing
 * path segment (falling back to the first accessible tab), and the empty
 * state lists the permissions an admin must grant.
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
    const seg = location.pathname.split('/').filter(Boolean).pop();
    const match = accessibleTabs.find((t) => t.key === seg);
    return match?.key ?? accessibleTabs[0]?.key;
  })();

  if (accessibleTabs.length === 0) {
    return <>{emptyState ?? null}</>;
  }

  return (
    <>
      <nav className="flex items-center gap-1 border-b border-theme mb-4">
        {accessibleTabs.map((tab) => {
          const isActive = activeKey === tab.key;
          return (
            <Link
              key={tab.key}
              to={`${basePath}/${tab.key}`}
              className={`px-3 py-2 text-sm inline-flex items-center gap-2 border-b-2 transition-colors ${
                isActive
                  ? 'border-theme-info text-theme-primary font-medium'
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
