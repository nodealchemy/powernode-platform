import React, { useState, useEffect, useCallback } from 'react';
import { useLocation } from 'react-router-dom';
import { Database, Brain, BookOpen } from 'lucide-react';
import { PageContainer, type PageAction } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { MemoryExplorerContent } from './MemoryExplorerPage';
import { AgentMemoryContent } from '../components/AgentMemoryContent';
import { ContextsContent } from '@/pages/app/ai/ContextsPage';

const tabs = [
  { id: 'tiers', label: 'Tier Explorer', icon: <Database size={16} />, path: '/' },
  { id: 'agent-memory', label: 'Agent Memory', icon: <Brain size={16} />, path: '/agent-memory' },
  { id: 'contexts', label: 'Contexts & Search', icon: <BookOpen size={16} />, path: '/contexts' },
];

/**
 * Content-only component for embedding in parent pages (e.g., KnowledgePage).
 * No PageContainer wrapper — avoids double headers when nested.
 */
export const KnowledgeMemoryContent: React.FC<{ onActionsReady?: (actions: PageAction[]) => void }> = ({ onActionsReady }) => {
  const location = useLocation();

  const getActiveTab = () => {
    const path = location.pathname;
    if (path.includes('/memory/agent-memory') || path.includes('/knowledge/memory/agent-memory')) return 'agent-memory';
    if (path.includes('/memory/contexts') || path.includes('/knowledge/memory/contexts')) return 'contexts';
    return 'tiers';
  };

  const [activeTab, setActiveTab] = useState(getActiveTab());

  useEffect(() => {
    const newTab = getActiveTab();
    if (newTab !== activeTab) setActiveTab(newTab);
  }, [location.pathname]);

  const handleActionsReady = useCallback((newActions: PageAction[]) => {
    onActionsReady?.(newActions);
  }, [onActionsReady]);

  return (
    <TabContainer
      tabs={tabs}
      activeTab={activeTab}
      onTabChange={setActiveTab}
      basePath="/app/ai/knowledge/memory"
      variant="underline"
      className="mb-6"
    >
      <TabPanel tabId="tiers" activeTab={activeTab}>
        <MemoryExplorerContent onActionsReady={handleActionsReady} />
      </TabPanel>
      <TabPanel tabId="agent-memory" activeTab={activeTab}>
        <AgentMemoryContent onActionsReady={handleActionsReady} />
      </TabPanel>
      <TabPanel tabId="contexts" activeTab={activeTab}>
        <ContextsContent onActionsReady={handleActionsReady} />
      </TabPanel>
    </TabContainer>
  );
};

export const KnowledgeMemoryPage: React.FC = () => {
  const [actions, setActions] = useState<PageAction[]>([]);

  const getBreadcrumbs = () => {
    const base: Array<{ label: string; href?: string }> = [
      { label: 'Dashboard', href: '/app' },
      { label: 'AI', href: '/app/ai' },
    ];
    base.push({ label: 'Knowledge & Memory' });
    return base;
  };

  return (
    <PageContainer
      title="Knowledge & Memory"
      description="Manage agent memory tiers, persistent contexts, and shared knowledge"
      breadcrumbs={getBreadcrumbs()}
      actions={actions}
    >
      <KnowledgeMemoryContent onActionsReady={setActions} />
    </PageContainer>
  );
};
