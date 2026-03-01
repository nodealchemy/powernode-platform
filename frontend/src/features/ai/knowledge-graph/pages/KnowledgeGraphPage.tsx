import React, { useState, useEffect, useCallback } from 'react';
import { GitBranch, Search, Network, Wrench } from 'lucide-react';
import { PageContainer, type PageAction } from '@/shared/components/layout/PageContainer';
import { TabContainer } from '@/shared/components/ui/TabContainer';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useRefreshAction } from '@/shared/hooks/useRefreshAction';
import { KnowledgeGraphVisualization } from '../components/KnowledgeGraphVisualization';
import { SkillGraphVisualization } from '../components/SkillGraphVisualization';
import { HybridSearchResults } from '../components/HybridSearchResults';

interface KnowledgeGraphContentProps {
  onActionsReady?: (actions: PageAction[]) => void;
}

export const KnowledgeGraphContent: React.FC<KnowledgeGraphContentProps> = ({ onActionsReady }) => {
  const { hasPermission } = usePermissions();
  const [activeTab, setActiveTab] = useState('graph-explorer');
  const [refreshKey, setRefreshKey] = useState(0);

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
      content: <KnowledgeGraphVisualization key={`graph-${refreshKey}`} />,
    },
    {
      id: 'skill-graph',
      label: 'Skill Graph',
      icon: <Wrench className="h-4 w-4" />,
      content: <SkillGraphVisualization key={`skill-${refreshKey}`} />,
    },
    {
      id: 'hybrid-search',
      label: 'Hybrid Search',
      icon: <Search className="h-4 w-4" />,
      content: <HybridSearchResults key={`search-${refreshKey}`} />,
    },
  ];

  return (
    <TabContainer
      tabs={tabs}
      activeTab={activeTab}
      onTabChange={setActiveTab}
      variant="underline"
    />
  );
};

export const KnowledgeGraphPage: React.FC = () => (
  <PageContainer
    title="Knowledge Graph"
    description="Explore entity relationships, search across vector and keyword indexes"
    breadcrumbs={[
      { label: 'Dashboard', href: '/app' },
      { label: 'AI', href: '/app/ai' },
      { label: 'Knowledge Graph' },
    ]}
  >
    <KnowledgeGraphContent />
  </PageContainer>
);
