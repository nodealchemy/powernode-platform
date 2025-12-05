import React, { useState, useEffect, useCallback } from 'react';
import { useSelector } from 'react-redux';
import { useLocation } from 'react-router-dom';
import { RootState } from '@/shared/services';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { RefreshCw } from 'lucide-react';
import { useAuth } from '@/shared/hooks/useAuth';

// Import individual AI pages
import { AIProvidersPage } from './AIProvidersPage';
import { AIAgentsPage } from './AIAgentsPage';
import { WorkflowsPage } from './WorkflowsPage';
import { AIConversationsPage } from './AIConversationsPage';
import { WorkflowAnalyticsPage } from './WorkflowAnalyticsPage';
import { EnhancedAIOverview } from '@/features/ai-orchestration/components/EnhancedAIOverview';
import { AuthenticationCheck } from '@/shared/components/ai/AuthenticationCheck';
// Note: PluginsPage moved to unified marketplace at /app/marketplace
// import { PluginsPage } from '@/features/ai-plugins/components/PluginsPage';

export const AIOrchestrationPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  const { currentUser } = useAuth();
  const location = useLocation();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Check permissions for tab visibility
  const canViewProviders = currentUser?.permissions?.includes('ai.providers.read') || false;
  const canViewAgents = currentUser?.permissions?.includes('ai.agents.read') || false;
  const canViewWorkflows = currentUser?.permissions?.includes('ai.workflows.read') || false;
  const canViewConversations = currentUser?.permissions?.includes('ai.conversations.read') || false;
  const canViewAnalytics = currentUser?.permissions?.includes('ai.analytics.read') || false;
  // Note: Plugins functionality moved to unified marketplace at /app/marketplace
  // const canViewPlugins = currentUser?.permissions?.includes('ai.plugins.browse') || false;

  // Load initial data
  const loadData = useCallback(async (force = false) => {
    try {
      if (!force && !loading) return; // Don't reload unless forced or initial load
      
      setLoading(true);
      setError(null);
      
      // Load AI system overview data here
      // For now, just simulate loading
      await new Promise(resolve => setTimeout(resolve, 500));
      
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load AI system data');
    } finally {
      setLoading(false);
    }
  }, [loading]);

  // Load data on mount
  useEffect(() => {
    loadData();
  }, []);

  // Define tabs based on permissions
  const tabs = [
    { id: 'overview', label: 'Overview', icon: '📊', path: '/' },
    ...(canViewProviders ? [{ id: 'providers', label: 'AI Providers', icon: '⚙️', path: '/providers' }] : []),
    ...(canViewAgents ? [{ id: 'agents', label: 'AI Agents', icon: '🤖', path: '/agents' }] : []),
    ...(canViewWorkflows ? [{ id: 'workflows', label: 'Workflows', icon: '⚡', path: '/workflows' }] : []),
    ...(canViewConversations ? [{ id: 'conversations', label: 'Conversations', icon: '💬', path: '/conversations' }] : []),
    // Note: Plugins tab removed - functionality moved to unified marketplace at /app/marketplace
    // ...(canViewPlugins ? [{ id: 'plugins', label: 'Plugins', icon: '📦', path: '/plugins' }] : []),
    ...(canViewAnalytics ? [{ id: 'analytics', label: 'Analytics', icon: '📈', path: '/analytics' }] : [])
  ];

  // Get active tab from URL
  const getActiveTab = () => {
    const path = location.pathname;
    if (path === '/app/ai') return 'overview';
    if (path.includes('/providers')) return 'providers';
    if (path.includes('/agents')) return 'agents';
    if (path.includes('/conversations')) return 'conversations';
    if (path.includes('/plugins')) return 'plugins';
    if (path.includes('/analytics')) return 'analytics';
    if (path.includes('/workflows')) return 'workflows';
    return 'overview';
  };

  const [activeTab, setActiveTab] = useState(getActiveTab());
  
  // Update active tab when URL changes
  useEffect(() => {
    const timeoutId = setTimeout(() => {
      const newActiveTab = getActiveTab();
      if (newActiveTab !== activeTab) {
        setActiveTab(newActiveTab);
      }
    }, 50);

    return () => clearTimeout(timeoutId);
  }, [location.pathname]);

  const pageActions: PageAction[] = [
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: () => loadData(true),
      variant: 'secondary',
      icon: RefreshCw,
      disabled: loading
    }
  ];

  // Dynamic breadcrumbs based on active tab
  const getBreadcrumbs = () => {
    const baseBreadcrumbs = [
      { label: 'Dashboard', href: '/app' },
      { label: 'AI Orchestration' }
    ];
    
    const activeTabInfo = tabs.find(tab => tab.id === activeTab);
    if (activeTabInfo && activeTab !== 'overview') {
      baseBreadcrumbs.push({
        label: activeTabInfo.label
      });
    }
    
    return baseBreadcrumbs;
  };

  const getPageDescription = () => {
    if (loading) return "Loading AI system...";
    if (error) return "Error loading AI system";
    return `Manage AI providers, agents, and workflows for ${user?.account?.name || 'your account'}`;
  };

  const getPageActions = () => {
    if (error) {
      return [{
        id: 'retry',
        label: 'Try Again',
        onClick: () => loadData(true),
        variant: 'primary' as const
      }];
    }
    return pageActions;
  };

  return (
    <AuthenticationCheck
      requiredPermissions={['ai.providers.read', 'ai.agents.read', 'ai.workflows.read', 'ai.conversations.read', 'ai.plugins.browse', 'ai.analytics.read']}
    >
      <PageContainer
        title="AI Orchestration"
        description={getPageDescription()}
        breadcrumbs={getBreadcrumbs()}
        actions={getPageActions()}
      >
        {loading && (
          <LoadingSpinner size="lg" message="Loading AI system..." />
        )}
        
        {error && (
          <div className="alert-theme alert-theme-error">
            <div className="flex items-center">
              <div className="flex-shrink-0">
                <span className="text-xl">⚠️</span>
              </div>
              <div className="ml-3">
                <h3 className="text-sm font-medium">Error Loading AI System</h3>
                <p className="mt-1 text-sm">{error}</p>
              </div>
            </div>
          </div>
        )}
        
        {!loading && !error && (
          <TabContainer
            tabs={tabs}
            activeTab={activeTab}
            onTabChange={setActiveTab}
            basePath="/app/ai"
            variant="underline"
            className="mb-6"
          >
            <TabPanel tabId="overview" activeTab={activeTab}>
              <EnhancedAIOverview />
            </TabPanel>

            {canViewProviders && (
              <TabPanel tabId="providers" activeTab={activeTab}>
                <AuthenticationCheck requiredPermissions={['ai.providers.read']}>
                  <AIProvidersPage />
                </AuthenticationCheck>
              </TabPanel>
            )}

            {canViewAgents && (
              <TabPanel tabId="agents" activeTab={activeTab}>
                <AuthenticationCheck requiredPermissions={['ai.agents.read']}>
                  <AIAgentsPage />
                </AuthenticationCheck>
              </TabPanel>
            )}

            {canViewWorkflows && (
              <TabPanel tabId="workflows" activeTab={activeTab}>
                <AuthenticationCheck requiredPermissions={['ai.workflows.read']}>
                  <WorkflowsPage />
                </AuthenticationCheck>
              </TabPanel>
            )}

            {canViewConversations && (
              <TabPanel tabId="conversations" activeTab={activeTab}>
                <AuthenticationCheck requiredPermissions={['ai.conversations.read']}>
                  <AIConversationsPage />
                </AuthenticationCheck>
              </TabPanel>
            )}

            {/* Note: Plugins tab removed - functionality moved to unified marketplace at /app/marketplace */}

            {canViewAnalytics && (
              <TabPanel tabId="analytics" activeTab={activeTab}>
                <AuthenticationCheck requiredPermissions={['ai.analytics.read']}>
                  <WorkflowAnalyticsPage />
                </AuthenticationCheck>
              </TabPanel>
            )}

          </TabContainer>
        )}
      </PageContainer>
    </AuthenticationCheck>
  );
};