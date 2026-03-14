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

interface FeatureRegistryState {
  routes: Map<string, FeatureRoute[]>;
  navItems: Map<string, FeatureNavItem[]>;
  navSections: Map<string, FeatureNavSection[]>;
  version: number;
  listeners: Set<() => void>;
}

const state: FeatureRegistryState = {
  routes: new Map(),
  navItems: new Map(),
  navSections: new Map(),
  version: 0,
  listeners: new Set(),
};

function notifyListeners(): void {
  state.version++;
  state.listeners.forEach(fn => fn());
}

export const featureRegistry = {
  /**
   * Register routes for a namespace (e.g., 'enterprise', 'ai')
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
    state.navItems.clear();
    state.navSections.clear();
  },
};
