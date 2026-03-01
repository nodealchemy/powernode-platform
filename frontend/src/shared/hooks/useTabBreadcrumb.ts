import { useEffect, useCallback } from 'react';
import { useLocation } from 'react-router-dom';
import { useBreadcrumb } from '@/shared/hooks/BreadcrumbContext';

interface TabConfig {
  id: string;
  label: string;
  path?: string;
}

interface UseTabBreadcrumbProps {
  pageId: string;
  tabs: readonly TabConfig[];
  activeTab: string;
  basePath?: string;
}

/**
 * Hook to synchronize tab selection with global breadcrumb state
 */
export const useTabBreadcrumb = ({ 
  pageId, 
  tabs, 
  activeTab, 
  basePath 
}: UseTabBreadcrumbProps) => {
  const { setActiveTab, setCurrentPage, clearPageTab } = useBreadcrumb();
  const location = useLocation();

  // Find the current tab configuration
  const currentTab = tabs.find(tab => tab.id === activeTab);
  
  // Generate tab href
  const getTabHref = useCallback((tab: TabConfig): string | undefined => {
    if (tab.path) return tab.path;
    if (basePath) return `${basePath}?tab=${tab.id}`;
    return `${location.pathname}?tab=${tab.id}`;
  }, [basePath, location.pathname]);

  // Update breadcrumb when tab changes
  useEffect(() => {
    if (currentTab) {
      const tabHref = getTabHref(currentTab);
      setActiveTab(pageId, currentTab.id, currentTab.label, tabHref);
    }
  }, [pageId, currentTab, setActiveTab, getTabHref]);

  // Set current page when component mounts
  useEffect(() => {
    setCurrentPage(pageId);
    
    // Cleanup when component unmounts
    return () => {
      clearPageTab(pageId);
    };
  }, [pageId, setCurrentPage, clearPageTab]);

  return {
    currentTab,
    updateTab: useCallback((tabId: string) => {
      const tab = tabs.find(t => t.id === tabId);
      if (tab) {
        const tabHref = getTabHref(tab);
        setActiveTab(pageId, tab.id, tab.label, tabHref);
      }
    }, [tabs, pageId, setActiveTab, getTabHref])
  };
};