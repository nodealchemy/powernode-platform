import React, { useState, useEffect, useCallback } from 'react';
import { useLocation } from 'react-router-dom';
import { GitBranch, Search, Network } from 'lucide-react';
import { type PageAction } from '@/shared/components/layout/PageContainer';
import { TabContainer } from '@/shared/components/layout/TabContainer';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useRefreshAction } from '@/shared/hooks/useRefreshAction';
import { KnowledgeGraphVisualization } from '../components/KnowledgeGraphVisualization';
import { HybridSearchResults } from '../components/HybridSearchResults';

interface KnowledgeGraphContentProps {
  onActionsReady?: (actions: PageAction[]) => void;
}

const KNOWLEDGE_GRAPH_BASE_PATH = '/app/ai/knowledge/graph';

const getActiveKnowledgeGraphTab = (pathname: string): string =>
  pathname.includes('/graph/hybrid-search') ? 'hybrid-search' : 'graph-explorer';

export const KnowledgeGraphContent: React.FC<KnowledgeGraphContentProps> = ({ onActionsReady }) => {
  const location = useLocation();
  const { hasPermission } = usePermissions();
  const [activeTab, setActiveTab] = useState(getActiveKnowledgeGraphTab(location.pathname));
  const [refreshKey, setRefreshKey] = useState(0);

  useEffect(() => {
    const newTab = getActiveKnowledgeGraphTab(location.pathname);
    if (newTab !== activeTab) setActiveTab(newTab);
  }, [location.pathname]);

  const { refreshAction } = useRefreshAction({
    onRefresh: useCallback(() => {
      setRefreshKey((k) => k + 1);
    }, []),
  });

  useEffect(() => {
    onActionsReady?.([refreshAction]);
  }, [onActionsReady, refreshAction]);

  const canView = hasPermission('ai.knowledge_graph.read');

  if (!canView) {
    return (
      <div className="text-center py-12">
        <Network className="h-12 w-12 text-theme-tertiary mx-auto mb-4 opacity-50" />
        <p className="text-theme-secondary">You do not have permission to view the knowledge graph.</p>
      </div>
    );
  }

  const tabs = [
    {
      id: 'graph-explorer',
      label: 'Graph Explorer',
      icon: <GitBranch className="h-4 w-4" />,
      path: '/',
      content: <KnowledgeGraphVisualization key={`graph-${refreshKey}`} />,
    },
    {
      id: 'hybrid-search',
      label: 'Hybrid Search',
      icon: <Search className="h-4 w-4" />,
      path: '/hybrid-search',
      content: <HybridSearchResults key={`search-${refreshKey}`} />,
    },
  ];

  return (
    <TabContainer
      tabs={tabs}
      activeTab={activeTab}
      onTabChange={setActiveTab}
      basePath={KNOWLEDGE_GRAPH_BASE_PATH}
      renderContent={(tabId) => tabs.find((tab) => tab.id === tabId)?.content}
      variant="underline"
    />
  );
};

