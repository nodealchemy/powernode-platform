import React from 'react';
import { Link, useLocation } from 'react-router-dom';
import { PathTabSpec } from './PathTabs';

/**
 * SubNavRail — a shared, permission-gated vertical sub-navigation rail for
 * in-page hubs whose leaves have their own sub-views.
 *
 * This is the canonical replacement for nested horizontal tabs: a hub renders
 * ONE vertical rail (this component) on the left and the active leaf — which may
 * itself carry a single `PathTabs` row — on the right. Net depth never exceeds
 * rail → one tab row, so we avoid stacked horizontal tab bars.
 *
 * It mirrors `PathTabs` exactly (same `PathTabSpec`, same permission filtering
 * and empty-state behavior) but lays the items out vertically and styles them
 * like the primary `Sidebar` (`NavigationItem`) so the sub-rail reads as native
 * navigation. The active item is derived from the URL segment immediately
 * following `basePath`, so a deep leaf URL (e.g. `${basePath}/credits/transactions`)
 * still highlights its rail item.
 *
 * Path-based nav per feedback_path_based_tabs. Permissions only — never roles.
 */

interface SubNavRailProps<TKey extends string = string> {
  /** Rail items in display order (reuses the PathTabs spec shape). */
  items: PathTabSpec<TKey>[];
  /** URL prefix the item keys append to, e.g. `/app/ai/cost`. */
  basePath: string;
  /** Permission predicate (from usePermissions). */
  hasPermission: (permission: string) => boolean;
  /**
   * Rendered when the operator can access none of the items. Optional: callers
   * that guard the empty case themselves can omit it (nothing renders).
   */
  emptyState?: React.ReactNode;
  /** The active leaf content — typically the caller's own `<Routes>`. */
  children: React.ReactNode;
  /** Accessible label for the nav landmark. Defaults to 'Section navigation'. */
  ariaLabel?: string;
  /** Optional eyebrow heading shown above the rail. */
  title?: string;
}

export function SubNavRail<TKey extends string = string>({
  items,
  basePath,
  hasPermission,
  emptyState,
  children,
  ariaLabel = 'Section navigation',
  title,
}: SubNavRailProps<TKey>): React.ReactElement {
  const location = useLocation();

  const accessibleItems = items.filter((i) => hasPermission(i.permission));
  const activeKey = (() => {
    const match = accessibleItems.find(
      (i) =>
        location.pathname === `${basePath}/${i.key}` ||
        location.pathname.startsWith(`${basePath}/${i.key}/`),
    );
    return match?.key ?? accessibleItems[0]?.key;
  })();

  if (accessibleItems.length === 0) {
    return <>{emptyState ?? null}</>;
  }

  return (
    <div className="flex flex-col gap-6 lg:flex-row">
      <nav
        aria-label={ariaLabel}
        data-testid="sub-nav-rail"
        className="flex-shrink-0 lg:w-56 lg:border-r lg:border-theme lg:pr-4"
      >
        {title && (
          <p className="px-3 mb-2 text-xs font-semibold uppercase tracking-wider text-theme-tertiary">
            {title}
          </p>
        )}
        <ul className="flex flex-row gap-1 overflow-x-auto pb-1 lg:flex-col lg:overflow-visible lg:pb-0">
          {accessibleItems.map((item) => {
            const isActive = activeKey === item.key;
            return (
              <li key={item.key}>
                <Link
                  to={`${basePath}/${item.key}`}
                  aria-current={isActive ? 'page' : undefined}
                  data-testid={`sub-nav-${item.key}`}
                  className={`group flex items-center gap-3 px-3 py-2 border-l-4 text-sm font-medium rounded-md transition-colors duration-150 whitespace-nowrap ${
                    isActive
                      ? 'bg-theme-surface-selected text-theme-link border-theme-focus'
                      : 'text-theme-secondary border-transparent hover:bg-theme-surface-hover hover:text-theme-primary'
                  }`}
                >
                  {item.icon}
                  <span className="flex-1">{item.label}</span>
                </Link>
              </li>
            );
          })}
        </ul>
      </nav>
      <div className="flex-1 min-w-0">{children}</div>
    </div>
  );
}

export default SubNavRail;
