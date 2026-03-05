// Navigation Context Provider
import React, { createContext, useContext, useReducer, useCallback, useEffect, useMemo } from 'react';
import { useLocation } from 'react-router-dom';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import type { NavigationItem, NavigationSection } from '@/shared/types/navigation';
import { NavigationContext, NavigationConfig, MenuState, NavigationTheme } from '@/shared/types/navigation';
import { hasAccess } from '@/shared/utils/permissionUtils';
import { defaultNavigationConfig, adminNavigationOverrides } from '@/shared/utils/navigation';
import { featureRegistry } from '@/shared/services/featureRegistry';

// Menu state reducer
type MenuAction =
  | { type: 'SET_ACTIVE_PATH'; payload: string }
  | { type: 'TOGGLE_SECTION'; payload: string }
  | { type: 'SET_COLLAPSED'; payload: boolean }
  | { type: 'SET_MOBILE_OPEN'; payload: boolean }
  | { type: 'UPDATE_STATE'; payload: Partial<MenuState> }
  | { type: 'EXPAND_SECTIONS'; payload: string[] };

const menuReducer = (state: MenuState, action: MenuAction): MenuState => {
  switch (action.type) {
    case 'SET_ACTIVE_PATH':
      return { ...state, activePath: action.payload };
    case 'TOGGLE_SECTION':
      return {
        ...state,
        expandedSections: state.expandedSections.includes(action.payload)
          ? state.expandedSections.filter(id => id !== action.payload)
          : [...state.expandedSections, action.payload]
      };
    case 'SET_COLLAPSED':
      return { ...state, isCollapsed: action.payload };
    case 'SET_MOBILE_OPEN':
      return { ...state, isMobileOpen: action.payload };
    case 'UPDATE_STATE':
      return { ...state, ...action.payload };
    case 'EXPAND_SECTIONS': {
      // Only add sections that aren't already expanded (doesn't re-expand collapsed sections)
      const sectionsToAdd = action.payload.filter(id => !state.expandedSections.includes(id));
      if (sectionsToAdd.length === 0) return state;
      return { ...state, expandedSections: [...state.expandedSections, ...sectionsToAdd] };
    }
    default:
      return state;
  }
};

// Initial menu state
const initialMenuState: MenuState = {
  activePath: '/',
  expandedSections: [], // All sections collapsed by default on first login
  isCollapsed: false,
  isMobileOpen: false
};

// Create context
const NavigationContextProvider = createContext<NavigationContext | null>(null);

interface NavigationProviderProps {
  children: React.ReactNode;
  theme?: NavigationTheme;
}

export const NavigationProvider: React.FC<NavigationProviderProps> = ({ 
  children, 
  theme = 'default' 
}) => {
  const location = useLocation();
  const { user } = useSelector((state: RootState) => state.auth);
  const { loadedExtensions } = useSelector((state: RootState) => state.config);
  const [menuState, dispatch] = useReducer(menuReducer, initialMenuState);

  // Check if user has admin access (permission-based)
  const hasAdminPermissions = hasAccess(user, ['admin.access']) ||
                             hasAccess(user, ['users.manage']) ||
                             hasAccess(user, ['workers.manage']);

  // Helper: filter items whose extensionSlug is not loaded
  const filterExtensionItems = useCallback((items: NavigationItem[]): NavigationItem[] => {
    return items.filter(item => !item.extensionSlug || loadedExtensions.includes(item.extensionSlug));
  }, [loadedExtensions]);

  // Helper: filter sections and their items by extensionSlug
  const filterExtensionSections = useCallback((sections: NavigationSection[]): NavigationSection[] => {
    return sections
      .filter(section => !section.extensionSlug || loadedExtensions.includes(section.extensionSlug))
      .map(section => ({
        ...section,
        items: section.items.filter(item => !item.extensionSlug || loadedExtensions.includes(item.extensionSlug))
      }));
  }, [loadedExtensions]);

  // Build navigation config based on user permissions
  const buildNavigationConfig = useCallback((): NavigationConfig => {
    const config = { ...defaultNavigationConfig };

    // Add admin sections if user has admin permissions
    if (hasAdminPermissions && adminNavigationOverrides.sections) {
      config.sections = [...(config.sections || []), ...adminNavigationOverrides.sections];
    }

    // Merge extension-registered nav sections
    const extensionSections = featureRegistry.getNavSections();
    if (extensionSections.length > 0) {
      const convertedSections = extensionSections.map(section => ({
        id: section.id,
        name: section.name,
        items: section.items.map(item => ({
          id: item.label.toLowerCase().replace(/\s+/g, '-'),
          name: item.label,
          href: item.path,
          icon: item.icon || 'Puzzle',
          description: '',
          permissions: item.permission ? [item.permission] : [],
          order: item.order,
        })),
        permissions: section.permissions,
        collapsible: section.collapsible,
        defaultExpanded: section.defaultExpanded,
        order: section.order,
      }));
      config.sections = [...(config.sections || []), ...convertedSections];
    }

    // Merge extension-registered nav items
    const extensionItems = featureRegistry.getNavItems();
    if (extensionItems.length > 0) {
      for (const item of extensionItems) {
        const converted = {
          id: item.label.toLowerCase().replace(/\s+/g, '-'),
          name: item.label,
          href: item.path,
          icon: item.icon || 'Puzzle',
          description: '',
          permissions: item.permission ? [item.permission] : [],
          order: item.order,
        };

        // Items with a section property get injected into matching sections
        if (item.section && config.sections) {
          const targetSection = config.sections.find(s => s.id === item.section);
          if (targetSection) {
            targetSection.items.push(converted);
            continue;
          }
        }

        // Top-level items (no section, or section not found)
        config.items = [...config.items, converted];
      }
    }

    // Filter extension-gated items at all levels
    if (config.sections) {
      config.sections = filterExtensionSections(config.sections);
    }
    config.items = filterExtensionItems(config.items);
    config.userMenuItems = filterExtensionItems(config.userMenuItems);
    config.quickActions = filterExtensionItems(config.quickActions);

    // Sort items by order
    config.items.sort((a, b) => (a.order || 99) - (b.order || 99));

    // Sort sections by order
    if (config.sections) {
      config.sections.sort((a, b) => (a.order || 99) - (b.order || 99));
    }

    return config;
  }, [hasAdminPermissions, filterExtensionItems, filterExtensionSections]);

  // Permission checker - ONLY use permissions, ignore roles
  const hasPermission = useCallback((permissions?: string[]): boolean => {
    return hasAccess(user, permissions);
  }, [user]);

  // Update active path when location changes
  useEffect(() => {
    dispatch({ type: 'SET_ACTIVE_PATH', payload: location.pathname });
    localStorage.setItem('powernode_last_path', location.pathname);
  }, [location.pathname]);

  // Auto-expand sections based on active path (only on navigation, not on user toggle)
  useEffect(() => {
    const config = buildNavigationConfig();
    if (!config.sections) return;

    // Find which section contains the current active path
    const activeSectionIds: string[] = [];

    config.sections.forEach(section => {
      const hasActiveItem = section.items.some(item => {
        // Check if current path matches item href exactly or is a sub-path
        const itemPath = item.href.replace(/\/$/, ''); // Remove trailing slash
        const currentPath = location.pathname.replace(/\/$/, ''); // Remove trailing slash

        return currentPath === itemPath ||
               currentPath.startsWith(itemPath + '/') ||
               // Handle special cases like admin-settings matching admin-settings/*
               (item.href.includes('admin-settings') && currentPath.includes('admin-settings'));
      });

      if (hasActiveItem) {
        activeSectionIds.push(section.id);
      }
    });

    // Auto-expand sections that contain active items (only add, won't re-expand user-collapsed sections)
    if (activeSectionIds.length > 0) {
      dispatch({ type: 'EXPAND_SECTIONS', payload: activeSectionIds });
    }
     
  }, [location.pathname, buildNavigationConfig]); // Only run on navigation, not on expandedSections changes

  // Clean up old navigation state and load saved state
  useEffect(() => {
    const userId = user?.id || 'anonymous';
    const storageKey = `powernode_menu_state_${userId}`;
    
    // Clean up old generic storage key
    const oldKey = 'powernode_menu_state';
    if (localStorage.getItem(oldKey)) {
      localStorage.removeItem(oldKey);
    }
    
    const savedState = localStorage.getItem(storageKey);
    
    if (savedState) {
      try {
        const parsed = JSON.parse(savedState);
        
        // Check if saved state is recent (within 30 days)
        const isRecent = !parsed.timestamp || (Date.now() - parsed.timestamp) < (30 * 24 * 60 * 60 * 1000);
        
        if (isRecent) {
          // Validate that saved sections still exist in current config
          const config = buildNavigationConfig();
          const validSections = parsed.expandedSections?.filter((sectionId: string) => 
            config.sections?.some(section => section.id === sectionId)
          ) || [];
          
          dispatch({ type: 'UPDATE_STATE', payload: {
            isCollapsed: parsed.isCollapsed || false,
            expandedSections: validSections
          }});
        } else {
          // Clear old state and use defaults (all collapsed)
          localStorage.removeItem(storageKey);
          dispatch({ type: 'UPDATE_STATE', payload: {
            expandedSections: []
          }});
        }
      } catch (_error) {
        localStorage.removeItem(storageKey);
        dispatch({ type: 'UPDATE_STATE', payload: {
          expandedSections: []
        }});
      }
    } else {
      // Set default state if no saved state (all sections collapsed)
      dispatch({ type: 'UPDATE_STATE', payload: {
        expandedSections: []
      }});
    }
  }, [user?.id, buildNavigationConfig]);

  // Save state to localStorage with user-specific key and debouncing
  useEffect(() => {
    const userId = user?.id || 'anonymous';
    const storageKey = `powernode_menu_state_${userId}`;
    
    // Debounce saves to avoid excessive localStorage writes
    const saveTimeout = setTimeout(() => {
      const stateToSave = {
        isCollapsed: menuState.isCollapsed,
        expandedSections: menuState.expandedSections,
        timestamp: Date.now()
      };
      localStorage.setItem(storageKey, JSON.stringify(stateToSave));
    }, 300); // 300ms debounce
    
    return () => clearTimeout(saveTimeout);
  }, [menuState.isCollapsed, menuState.expandedSections, user?.id]);

  // Update state function
  const updateState = useCallback((updates: Partial<MenuState>) => {
    dispatch({ type: 'UPDATE_STATE', payload: updates });
  }, []);

  // Memoize config to avoid rebuilding every render
  const config = useMemo(() => buildNavigationConfig(), [buildNavigationConfig]);

  // Memoize context value to prevent unnecessary consumer re-renders
  const contextValue = useMemo<NavigationContext>(() => ({
    config,
    state: menuState,
    theme,
    updateState,
    hasPermission
  }), [config, menuState, theme, updateState, hasPermission]);

  return (
    <NavigationContextProvider.Provider value={contextValue}>
      {children}
    </NavigationContextProvider.Provider>
  );
};

// Hook to use navigation context
export const useNavigation = (): NavigationContext => {
  const context = useContext(NavigationContextProvider);
  if (!context) {
    throw new Error('useNavigation must be used within a NavigationProvider');
  }
  return context;
};

export default NavigationProvider;