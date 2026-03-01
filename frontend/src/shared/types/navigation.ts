// Navigation Types and Interfaces

export interface NavigationItem {
  id: string;
  name: string;
  href: string;
  icon: React.ComponentType<any> | string;
  description?: string;
  permissions?: string[];
  roles?: string[];
  badge?: string | number;
  children?: NavigationItem[];
  isExternal?: boolean;
  requiresSetup?: boolean;
  category?: string;
  order?: number;
  extensionSlug?: string;
  action?: string;
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
  extensionSlug?: string;
}

export interface NavigationConfig {
  items: NavigationItem[];
  sections?: NavigationSection[];
  userMenuItems: NavigationItem[];
  quickActions: NavigationItem[];
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