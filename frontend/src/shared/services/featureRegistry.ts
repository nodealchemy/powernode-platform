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
}

interface FeatureRegistryState {
  routes: Map<string, FeatureRoute[]>;
  navItems: Map<string, FeatureNavItem[]>;
}

const state: FeatureRegistryState = {
  routes: new Map(),
  navItems: new Map(),
};

export const featureRegistry = {
  /**
   * Register routes for a namespace (e.g., 'enterprise', 'ai')
   */
  registerRoutes(namespace: string, routes: FeatureRoute[]): void {
    const existing = state.routes.get(namespace) || [];
    state.routes.set(namespace, [...existing, ...routes]);
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
   * Check if any routes are registered for a namespace
   */
  hasRoutes(namespace: string): boolean {
    const routes = state.routes.get(namespace);
    return !!routes && routes.length > 0;
  },

  /**
   * Clear all registrations (useful for testing)
   */
  clear(): void {
    state.routes.clear();
    state.navItems.clear();
  },
};
