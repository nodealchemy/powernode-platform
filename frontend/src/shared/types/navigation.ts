// Navigation Types and Interfaces

export interface NavigationItem {
  id: string;
  name: string;
  href: string;
  icon: React.ComponentType<{ className?: string }> | string;
  description?: string;
  permissions?: string[];
  roles?: string[];
  badge?: string | number;
  children?: NavigationItem[];
  isExternal?: boolean;
  requiresSetup?: boolean;
  category?: string;
  order?: number;
  action?: string;
  activeMatch?: 'exact' | 'prefix';
  /**
   * A featureRegistry component-slot id prefix (e.g. 'devops.ci-cd.tab.').
   * When set, this item's visibility unions in the `permissions` declared by
   * every registered slot under the prefix (featureRegistry.getSlotPermissions),
   * on top of its own `permissions` — so an item whose page hosts extension
   * tabs through a slot seam stays visible to a user who holds only the
   * extension's slot permission, without core ever naming that permission
   * itself. Resolved in NavigationContext.tsx's buildNavigationConfig.
   */
  slotPrefix?: string;
}

export interface NavigationSection {
  id: string;
  name: string;
  items: NavigationItem[];
  permissions?: string[];
  roles?: string[];
  collapsible?: boolean;
  defaultExpanded?: boolean;
  order?: number;
}

export interface NavigationConfig {
  items: NavigationItem[];
  sections?: NavigationSection[];
  userMenuItems: NavigationItem[];
  adminOverrides?: {
    items?: NavigationItem[];
    sections?: NavigationSection[];
    userMenuItems?: NavigationItem[];
  };
}

export interface MenuState {
  activePath: string;
  expandedSections: string[]; // Legacy - may not be needed with flat structure
  isCollapsed: boolean;
  isMobileOpen: boolean;
}

export type NavigationTheme = 'default' | 'compact' | 'minimal';

export interface NavigationContext {
  config: NavigationConfig;
  state: MenuState;
  theme: NavigationTheme;
  updateState: (updates: Partial<MenuState>) => void;
  hasPermission: (permissions?: string[]) => boolean;
}