import React, { useState, useEffect, useCallback } from 'react';
import { useLocation } from 'react-router-dom';
import { BookOpen, Database, Share2, Layers, Lightbulb } from 'lucide-react';
import { PageContainer, type PageAction } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { KNOWLEDGE_TAB_PERMISSIONS } from '@/shared/constants/knowledgePermissions';
import { ContextsContent } from '@/pages/app/ai/ContextsPage';
import { RagContent } from '@/pages/app/ai/RagPage';
import { KnowledgeGraphContent } from '@/features/ai/knowledge-graph';
import { KnowledgeMemoryContent } from '@/features/ai/memory';
import { LearningContent } from '@/features/ai/learning/components/LearningContent';

const P = KNOWLEDGE_TAB_PERMISSIONS;
const tabs = [
  { id: 'contexts', label: 'Contexts', icon: <BookOpen size={16} />, path: '/contexts', permissions: [P.contexts] },
  { id: 'memory', label: 'Tiered Memory', icon: <Layers size={16} />, path: '/memory', permissions: [P.memory] },
  { id: 'rag', label: 'RAG', icon: <Database size={16} />, path: '/rag', permissions: [P.rag] },
  { id: 'graph', label: 'Graph', icon: <Share2 size={16} />, path: '/graph', permissions: [P.graph] },
  { id: 'learning', label: 'Learning', icon: <Lightbulb size={16} />, path: '/learning', permissions: [P.learning] },
];

// fc-43: Knowledge is what agents know. Prompts and Skills are their own AI
// Agents items (/app/ai/prompts, /app/ai/skills), and Learning Insights
// folded in under Learning.
export const KnowledgePage: React.FC = () => {
  const location = useLocation();
  const { hasPermission } = usePermissions();
  const [actions, setActions] = useState<PageAction[]>([]);

  const visibleTabs = tabs.filter((t) => t.permissions.every((p) => hasPermission(p)));
  const segment = location.pathname.replace(/^\/app\/ai\/knowledge/, '').split('/')[1] || '';
  // The bare path opens the first tab the viewer may read; a tab reached by
  // URL that the viewer may not read does the same.
  const activeTab = visibleTabs.find((t) => t.path === `/${segment}`)?.id ?? visibleTabs[0]?.id ?? '';

  // Clear actions on tab change so stale actions don't persist
  useEffect(() => {
    setActions([]);
  }, [activeTab]);

  const handleActionsReady = useCallback((newActions: PageAction[]) => {
    setActions(newActions);
  }, []);

  const getBreadcrumbs = () => {
    const base: Array<{ label: string; href?: string }> = [
      { label: 'Dashboard', href: '/app' },
      { label: 'AI', href: '/app/ai' },
      { label: 'Knowledge', href: '/app/ai/knowledge' },
    ];
    const activeTabInfo = tabs.find(t => t.id === activeTab);
    if (activeTabInfo) base.push({ label: activeTabInfo.label });
    return base;
  };

  return (
    <PageContainer
      title="Knowledge"
      description="Contexts, tiered memory, document bases, the knowledge graph and compound learning"
      breadcrumbs={getBreadcrumbs()}
      actions={actions}
    >
      <TabContainer
        tabs={tabs}
        activeTab={activeTab}
        basePath="/app/ai/knowledge"
        variant="underline"
        className="mb-6"
      >
        <TabPanel tabId="contexts" activeTab={activeTab}>
          <ContextsContent onActionsReady={handleActionsReady} />
        </TabPanel>
        <TabPanel tabId="memory" activeTab={activeTab}>
          <KnowledgeMemoryContent onActionsReady={handleActionsReady} />
        </TabPanel>
        <TabPanel tabId="rag" activeTab={activeTab}>
          <RagContent onActionsReady={handleActionsReady} />
        </TabPanel>
        <TabPanel tabId="graph" activeTab={activeTab}>
          <KnowledgeGraphContent onActionsReady={handleActionsReady} />
        </TabPanel>
        <TabPanel tabId="learning" activeTab={activeTab}>
          <LearningContent onActionsReady={handleActionsReady} />
        </TabPanel>
      </TabContainer>
    </PageContainer>
  );
};

export default KnowledgePage;
