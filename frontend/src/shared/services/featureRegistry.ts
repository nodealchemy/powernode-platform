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
 * A widget injected into the global header slot (e.g. an extension's portfolio
 * switcher). `match` decides, from the current pathname, whether the widget
 * should render — this keeps route-specific header chrome out of core. Keyed
 * by namespace; core never names an extension here.
 */
export interface FeatureHeaderWidget {
  component: LazyExoticComponent<ComponentType<unknown>> | ComponentType<unknown>;
  match: (pathname: string) => boolean;
  permission?: string;
}

/** A setup-wizard step component an extension contributes, keyed by the step's
 *  `component` id (e.g. "@ext/system/setup/VirtualizationHostsStep"). Rendered by
 *  SetupWizard for component-based extension steps; keyed by id, never by core. */
type SetupStepComponent = LazyExoticComponent<ComponentType<unknown>> | ComponentType<unknown>;

/** A component an extension contributes into a named slot that a core host page
 *  exposes (e.g. an optional leaf inside a tabbed hub). Keyed by an opaque slot
 *  id the host page owns (e.g. 'ai.cost.outcome-billing'); the host renders the
 *  slot's component when present and omits the surface when absent. Lets a core
 *  page host an extension-provided sub-view without importing — or naming — any
 *  extension. Props are slot-specific; the host casts to the slot's prop shape
 *  at the call site (mirrors getSetupStepComponent). */
type ComponentSlot = LazyExoticComponent<ComponentType<unknown>> | ComponentType<unknown>;

/**
 * A real-time ActionCable channel an extension contributes. `key` is the logical channel
 * id consumed by usePageWebSocket (e.g. 'subscriptions'); `channelName` is the ActionCable
 * channel class the backend exposes (e.g. 'SubscriptionChannel'); `defaultPageTypes` lists
 * the page types that auto-subscribe to it when the extension is loaded. Keyed by namespace —
 * core never names an extension's channels; it merges whatever is registered with its core set.
 */
export interface FeatureChannel {
  key: string;
  channelName: string;
  defaultPageTypes?: string[];
}

interface FeatureRegistryState {
  routes: Map<string, FeatureRoute[]>;
  publicRoutes: Map<string, FeatureRoute[]>;
  navItems: Map<string, FeatureNavItem[]>;
  navSections: Map<string, FeatureNavSection[]>;
  settingsTabs: Map<string, FeatureSettingsTab[]>;
  headerWidgets: Map<string, FeatureHeaderWidget[]>;
  channels: Map<string, FeatureChannel[]>;
  setupStepComponents: Map<string, SetupStepComponent>;
  componentSlots: Map<string, ComponentSlot>;
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
  channels: new Map(),
  setupStepComponents: new Map(),
  componentSlots: new Map(),
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
   * Register setup-wizard step components, keyed by the step's `component` id.
   * Extensions call this from register.ts for component-based setup steps; the
   * SetupWizard resolves the id to render it.
   */
  registerSetupStepComponents(components: Record<string, SetupStepComponent>): void {
    Object.entries(components).forEach(([id, component]) => {
      state.setupStepComponents.set(id, component);
    });
    notifyListeners();
  },

  /** Resolve a setup-step component by its `component` id, or undefined. */
  getSetupStepComponent(id: string): SetupStepComponent | undefined {
    return state.setupStepComponents.get(id);
  },

  /**
   * Register components into named slots that core host pages expose, keyed by
   * each slot's opaque id (owned by the host page, e.g. 'ai.cost.outcome-billing').
   * Extensions call this from register.ts to fill a host slot; the host renders
   * the slot when present and omits the surface when absent — so a core page can
   * host an extension-provided sub-view without importing or naming any extension.
   */
  registerComponentSlots(slots: Record<string, ComponentSlot>): void {
    Object.entries(slots).forEach(([id, component]) => {
      state.componentSlots.set(id, component);
    });
    notifyListeners();
  },

  /** Resolve a slot component by its host-owned slot id, or undefined. */
  getComponentSlot(id: string): ComponentSlot | undefined {
    return state.componentSlots.get(id);
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
   * Register header widgets for a namespace (e.g. an extension's portfolio
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
   * Register real-time channels for a namespace (e.g. the business subscriptions/
   * customers/analytics channels). Consumed by usePageWebSocket, which merges these
   * with its core channel set — so core resolves channel names and per-page defaults
   * dynamically and never hardcodes an extension's channel.
   */
  registerChannels(namespace: string, channels: FeatureChannel[]): void {
    const existing = state.channels.get(namespace) || [];
    state.channels.set(namespace, [...existing, ...channels]);
    notifyListeners();
  },

  /**
   * Get all registered channels, optionally filtered by namespace
   */
  getChannels(namespace?: string): FeatureChannel[] {
    if (namespace) {
      return state.channels.get(namespace) || [];
    }
    return Array.from(state.channels.values()).flat();
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
    state.channels.clear();
    state.setupStepComponents.clear();
    state.componentSlots.clear();
  },
};
