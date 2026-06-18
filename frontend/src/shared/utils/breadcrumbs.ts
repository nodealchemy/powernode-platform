import type { BreadcrumbItem } from '@/shared/components/layout/PageContainer';

/**
 * Breadcrumb helpers for path-based hubs.
 *
 * Hub pages read `useLocation` to know their active leaf/sub-tab, then pass a
 * computed `BreadcrumbItem[]` to `PageContainer`. These helpers keep the trail
 * consistent so every tab/sub-nav selection updates both the URL and the
 * breadcrumb (the "tabs update breadcrumbs + URL" rule) without bespoke arrays
 * scattered across pages.
 */

/** Prepend an arbitrary root trail to a hub/leaf breadcrumb trail. */
export function buildBreadcrumbs(
  root: BreadcrumbItem[],
  ...trail: BreadcrumbItem[]
): BreadcrumbItem[] {
  return [...root, ...trail];
}

/** Standard `Dashboard ▸ AI` root shared by every AI-domain hub. */
export const AI_ROOT_CRUMBS: BreadcrumbItem[] = [
  { label: 'Dashboard', href: '/app' },
  { label: 'AI', href: '/app/ai' },
];

/** Prepend the standard `Dashboard ▸ AI` root to a hub/leaf breadcrumb trail. */
export function aiCrumbs(...trail: BreadcrumbItem[]): BreadcrumbItem[] {
  return buildBreadcrumbs(AI_ROOT_CRUMBS, ...trail);
}
