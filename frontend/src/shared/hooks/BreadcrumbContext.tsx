import React, { createContext, useContext, useReducer, ReactNode } from 'react';

export interface BreadcrumbItem {
  label: string;
  href?: string;
  icon?: React.ComponentType<any> | string;
  isActive?: boolean;
}

export interface TabInfo {
  pageId: string;
  activeTabId: string;
  tabLabel: string;
  tabHref?: string;
}

interface BreadcrumbState {
  items: BreadcrumbItem[];
  activeTabs: Record<string, TabInfo>; // pageId -> TabInfo
  currentPageId: string | null;
}

type BreadcrumbAction =
  | { type: 'SET_BREADCRUMBS'; payload: BreadcrumbItem[] }
  | { type: 'SET_ACTIVE_TAB'; payload: { pageId: string; tabInfo: TabInfo } }
  | { type: 'SET_CURRENT_PAGE'; payload: string }
  | { type: 'UPDATE_TAB_BREADCRUMB'; payload: { pageId: string; tabLabel: string; tabHref?: string } }
  | { type: 'CLEAR_PAGE_TAB'; payload: string }
  | { type: 'RESET_BREADCRUMBS' };

const initialState: BreadcrumbState = {
  items: [],
  activeTabs: {},
  currentPageId: null
};

const breadcrumbReducer = (state: BreadcrumbState, action: BreadcrumbAction): BreadcrumbState => {
  switch (action.type) {
    case 'SET_BREADCRUMBS':
      return { ...state, items: action.payload };
      
    case 'SET_ACTIVE_TAB': {
      const { pageId, tabInfo } = action.payload;
      return {
        ...state,
        // eslint-disable-next-line security/detect-object-injection
        activeTabs: { ...state.activeTabs, [pageId]: tabInfo }
      };
    }
    
    case 'SET_CURRENT_PAGE':
      return { ...state, currentPageId: action.payload };
      
    case 'UPDATE_TAB_BREADCRUMB': {
      const { pageId, tabLabel, tabHref } = action.payload;
      // eslint-disable-next-line security/detect-object-injection
      const currentTab = state.activeTabs[pageId];
      
      if (!currentTab) return state;
      
      // Update breadcrumbs to include active tab
      const baseBreadcrumbs = state.items.filter(item => !item.isActive);
      const tabBreadcrumb: BreadcrumbItem = {
        label: tabLabel,
        href: tabHref,
        isActive: true
      };
      
      return {
        ...state,
        items: [...baseBreadcrumbs, tabBreadcrumb],
        activeTabs: {
          ...state.activeTabs,
          [pageId]: { ...currentTab, tabLabel, tabHref }
        }
      };
    }
    
    case 'CLEAR_PAGE_TAB': {
      const newActiveTabs = { ...state.activeTabs };
      delete newActiveTabs[action.payload];
      
      // Remove active tab breadcrumb
      const filteredItems = state.items.filter(item => !item.isActive);
      
      return {
        ...state,
        activeTabs: newActiveTabs,
        items: filteredItems
      };
    }
    
    case 'RESET_BREADCRUMBS':
      return initialState;
      
    default:
      return state;
  }
};

interface BreadcrumbContextType {
  state: BreadcrumbState;
  setBreadcrumbs: (items: BreadcrumbItem[]) => void;
  setActiveTab: (pageId: string, tabId: string, tabLabel: string, tabHref?: string) => void;
  setCurrentPage: (pageId: string) => void;
  updateTabBreadcrumb: (pageId: string, tabLabel: string, tabHref?: string) => void;
  clearPageTab: (pageId: string) => void;
  resetBreadcrumbs: () => void;
  getCurrentBreadcrumbs: () => BreadcrumbItem[];
}

const BreadcrumbContext = createContext<BreadcrumbContextType | undefined>(undefined);

export const BreadcrumbProvider: React.FC<{ children: ReactNode }> = ({ children }) => {
  const [state, dispatch] = useReducer(breadcrumbReducer, initialState);

  const setBreadcrumbs = (items: BreadcrumbItem[]) => {
    dispatch({ type: 'SET_BREADCRUMBS', payload: items });
  };

  const setActiveTab = (pageId: string, tabId: string, tabLabel: string, tabHref?: string) => {
    const tabInfo: TabInfo = { pageId, activeTabId: tabId, tabLabel, tabHref };
    dispatch({ type: 'SET_ACTIVE_TAB', payload: { pageId, tabInfo } });
    
    // Auto-update breadcrumb if this is the current page
    if (state.currentPageId === pageId) {
      dispatch({ type: 'UPDATE_TAB_BREADCRUMB', payload: { pageId, tabLabel, tabHref } });
    }
  };

  const setCurrentPage = (pageId: string) => {
    dispatch({ type: 'SET_CURRENT_PAGE', payload: pageId });
    
    // Update breadcrumb if there's an active tab for this page
    // eslint-disable-next-line security/detect-object-injection
    const activeTab = state.activeTabs[pageId];
    if (activeTab) {
      dispatch({ 
        type: 'UPDATE_TAB_BREADCRUMB', 
        payload: { pageId, tabLabel: activeTab.tabLabel, tabHref: activeTab.tabHref } 
      });
    }
  };

  const updateTabBreadcrumb = (pageId: string, tabLabel: string, tabHref?: string) => {
    dispatch({ type: 'UPDATE_TAB_BREADCRUMB', payload: { pageId, tabLabel, tabHref } });
  };

  const clearPageTab = (pageId: string) => {
    dispatch({ type: 'CLEAR_PAGE_TAB', payload: pageId });
  };

  const resetBreadcrumbs = () => {
    dispatch({ type: 'RESET_BREADCRUMBS' });
  };

  const getCurrentBreadcrumbs = (): BreadcrumbItem[] => {
    return state.items;
  };

  return (
    <BreadcrumbContext.Provider
      value={{
        state,
        setBreadcrumbs,
        setActiveTab,
        setCurrentPage,
        updateTabBreadcrumb,
        clearPageTab,
        resetBreadcrumbs,
        getCurrentBreadcrumbs
      }}
    >
      {children}
    </BreadcrumbContext.Provider>
  );
};

export const useBreadcrumb = (): BreadcrumbContextType => {
  const context = useContext(BreadcrumbContext);
  if (context === undefined) {
    throw new Error('useBreadcrumb must be used within a BreadcrumbProvider');
  }
  return context;
};