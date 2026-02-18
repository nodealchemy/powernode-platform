import React, { useState } from 'react';
import { GitBranch, Search, Network, Wrench } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TabContainer } from '@/shared/components/ui/TabContainer';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { KnowledgeGraphVisualization } from '../components/KnowledgeGraphVisualization';
import { SkillGraphVisualization } from '../components/SkillGraphVisualization';
import { HybridSearchResults } from '../components/HybridSearchResults';

export const KnowledgeGraphContent: React.FC = () => {
  const { hasPermission } = usePermissions();
  const [activeTab, setActiveTab] = useState('graph-explorer');

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
      content: <KnowledgeGraphVisualization />,
    },
    {
      id: 'skill-graph',
      label: 'Skill Graph',
      icon: <Wrench className="h-4 w-4" />,
      content: <SkillGraphVisualization />,
    },
    {
      id: 'hybrid-search',
      label: 'Hybrid Search',
      icon: <Search className="h-4 w-4" />,
      content: <HybridSearchResults />,
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
