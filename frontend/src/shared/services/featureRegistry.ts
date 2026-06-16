import { ComponentType, LazyExoticComponent } from 'react';

export interface FeatureRoute {
  path: string;
  component: LazyExoticComponent<ComponentType<unknown>> | ComponentType<unknown>;
  permission?: string;
}

export interface FeatureNavItem {
  label: string;
  path: string;
  icon?: string;
  permission?: string;
  section?: string;
  order?: number;
  activeMatch?: 'exact' | 'prefix';
}

export interface FeatureNavSection {
  id: string;
  name: string;
  items: FeatureNavItem[];
  icon?: string;
  permissions?: string[];
  collapsible?: boolean;
  defaultExpanded?: boolean;
  order?: number;
}

/**
 * A tab contributed to a tabbed admin/settings surface (e.g. Admin Settings).
 * `icon` is a Lucide icon name string (resolved by the host, falling back to
 * Puzzle) so extensions don't import core icon components. `path` is the full
 * app path of the tab (e.g. '/app/admin/settings/payment-gateways'); the host
 * derives the nested route from it. `component` renders inside the host's
 * tabbed shell. Rendered only when the registering extension is loaded — keyed
 * by namespace, never by core.
 */
export interface FeatureSettingsTab {
  id: string;
  label: string;
  path: string;
  component: LazyExoticComponent<ComponentType<unknown>> | ComponentType<unknown>;
  icon?: string;
  description?: string;
  permission?: string;
  order?: number;
}

/**
 * A widget injected into the global header slot (e.g. the trading portfolio
 * switcher). `match` decides, from the current pathname, whether the widget
 * should render — this keeps route-specific header chrome out of core. Keyed
 * by namespace; core never names an extension here.
 */
export interface FeatureHeaderWidget {
  component: LazyExoticComponent<ComponentType<unknown>> | ComponentType<unknown>;
  match: (pathname: string) => boolean;
  permission?: string;
}

interface FeatureRegistryState {
  routes: Map<string, FeatureRoute[]>;
  publicRoutes: Map<string, FeatureRoute[]>;
  navItems: Map<string, FeatureNavItem[]>;
  navSections: Map<string, FeatureNavSection[]>;
  settingsTabs: Map<string, FeatureSettingsTab[]>;
  headerWidgets: Map<string, FeatureHeaderWidget[]>;
  version: number;
  listeners: Set<() => void>;
}

const state: FeatureRegistryState = {
  routes: new Map(),
  publicRoutes: new Map(),
  navItems: new Map(),
  navSections: new Map(),
  settingsTabs: new Map(),
  headerWidgets: new Map(),
  version: 0,
  listeners: new Set(),
};

function notifyListeners(): void {
  state.version++;
  state.listeners.forEach(fn => fn());
}

export const featureRegistry = {
  /**
   * Register routes for a namespace (e.g., 'business', 'ai')
   */
  registerRoutes(namespace: string, routes: FeatureRoute[]): void {
    const existing = state.routes.get(namespace) || [];
    state.routes.set(namespace, [...existing, ...routes]);
    notifyListeners();
  },

  /**
   * Get all registered routes, optionally filtered by namespace
   */
  getRoutes(namespace?: string): FeatureRoute[] {
    if (namespace) {
      return state.routes.get(namespace) || [];
    }
    return Array.from(state.routes.values()).flat();
  },

  /**
   * Register PUBLIC routes for a namespace (no authentication required).
   * Consumed by App.tsx routing for unauthenticated landing/marketing pages.
   * Public routes render WITHOUT any PublicRoute or ProtectedRoute wrapper —
   * they're visible to authenticated and unauthenticated users alike.
   * First-match wins in App.tsx, so extension-registered public routes
   * override the default routes when the extension is loaded; they fall
   * through to App.tsx defaults when the extension is absent.
   */
  registerPublicRoutes(namespace: string, routes: FeatureRoute[]): void {
    const existing = state.publicRoutes.get(namespace) || [];
    state.publicRoutes.set(namespace, [...existing, ...routes]);
    notifyListeners();
  },

  /**
   * Get all registered public routes, optionally filtered by namespace
   */
  getPublicRoutes(namespace?: string): FeatureRoute[] {
    if (namespace) {
      return state.publicRoutes.get(namespace) || [];
    }
    return Array.from(state.publicRoutes.values()).flat();
  },

  /**
   * Register navigation items for a namespace
   */
  registerNavItems(namespace: string, items: FeatureNavItem[]): void {
    const existing = state.navItems.get(namespace) || [];
    state.navItems.set(namespace, [...existing, ...items]);
    notifyListeners();
  },

  /**
   * Get all registered nav items, optionally filtered by namespace
   */
  getNavItems(namespace?: string): FeatureNavItem[] {
    if (namespace) {
      return state.navItems.get(namespace) || [];
    }
    return Array.from(state.navItems.values()).flat();
  },

  /**
   * Register navigation sections for a namespace
   */
  registerNavSections(namespace: string, sections: FeatureNavSection[]): void {
    const existing = state.navSections.get(namespace) || [];
    state.navSections.set(namespace, [...existing, ...sections]);
    notifyListeners();
  },

  /**
   * Get all registered nav sections, optionally filtered by namespace
   */
  getNavSections(namespace?: string): FeatureNavSection[] {
    if (namespace) {
      return state.navSections.get(namespace) || [];
    }
    return Array.from(state.navSections.values()).flat();
  },

  /**
   * Register settings tabs for a namespace (e.g. a 'business' Payment Gateways
   * tab). Consumed by tabbed settings surfaces; rendered only when the owning
   * extension is loaded.
   */
  registerSettingsTabs(namespace: string, tabs: FeatureSettingsTab[]): void {
    const existing = state.settingsTabs.get(namespace) || [];
    state.settingsTabs.set(namespace, [...existing, ...tabs]);
    notifyListeners();
  },

  /**
   * Get all registered settings tabs, optionally filtered by namespace
   */
  getSettingsTabs(namespace?: string): FeatureSettingsTab[] {
    if (namespace) {
      return state.settingsTabs.get(namespace) || [];
    }
    return Array.from(state.settingsTabs.values()).flat();
  },

  /**
   * Register header widgets for a namespace (e.g. the trading portfolio
   * switcher). Consumed by the global Header; each widget decides via its
   * `match(pathname)` predicate whether it renders for the current route.
   */
  registerHeaderWidgets(namespace: string, widgets: FeatureHeaderWidget[]): void {
    const existing = state.headerWidgets.get(namespace) || [];
    state.headerWidgets.set(namespace, [...existing, ...widgets]);
    notifyListeners();
  },

  /**
   * Get all registered header widgets, optionally filtered by namespace
   */
  getHeaderWidgets(namespace?: string): FeatureHeaderWidget[] {
    if (namespace) {
      return state.headerWidgets.get(namespace) || [];
    }
    return Array.from(state.headerWidgets.values()).flat();
  },

  /**
   * Get all registered namespace identifiers
   */
  getRegisteredNamespaces(): string[] {
    return Array.from(state.routes.keys());
  },

  /**
   * Check if any routes are registered for a namespace
   */
  hasRoutes(namespace: string): boolean {
    const routes = state.routes.get(namespace);
    return !!routes && routes.length > 0;
  },

  /**
   * Current registry version — increments on every registration.
   */
  getVersion(): number {
    return state.version;
  },

  /**
   * Subscribe to registry changes. Returns an unsubscribe function.
   */
  subscribe(listener: () => void): () => void {
    state.listeners.add(listener);
    return () => { state.listeners.delete(listener); };
  },

  /**
   * Clear all registrations (useful for testing)
   */
  clear(): void {
    state.routes.clear();
    state.publicRoutes.clear();
    state.navItems.clear();
    state.navSections.clear();
    state.settingsTabs.clear();
    state.headerWidgets.clear();
  },
};
