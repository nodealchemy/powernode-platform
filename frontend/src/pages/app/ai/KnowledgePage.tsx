import React, { useState, useEffect, useCallback } from 'react';
import { useLocation } from 'react-router-dom';
import { BookOpen, MessageSquare, Puzzle, Database, Share2, Layers, Lightbulb } from 'lucide-react';
import { PageContainer, type PageAction } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { ContextsContent } from '@/pages/app/ai/ContextsPage';
import { PromptsContent } from '@/features/ai/prompts/pages/PromptsPage';
import { SkillsContent } from '@/pages/app/ai/SkillsPage';
import { RagContent } from '@/pages/app/ai/RagPage';
import { KnowledgeGraphContent } from '@/features/ai/knowledge-graph';
import { KnowledgeMemoryContent } from '@/features/ai/memory';
import { CompoundLearningContent } from '@/pages/app/ai/CompoundLearningPage';

const tabs = [
  { id: 'contexts', label: 'Contexts', icon: <BookOpen size={16} />, path: '/contexts' },
  { id: 'prompts', label: 'Prompts', icon: <MessageSquare size={16} />, path: '/prompts' },
  { id: 'skills', label: 'Skills', icon: <Puzzle size={16} />, path: '/skills' },
  { id: 'rag', label: 'RAG', icon: <Database size={16} />, path: '/rag' },
  { id: 'graph', label: 'Knowledge Graph', icon: <Share2 size={16} />, path: '/graph' },
  { id: 'memory', label: 'Memory Tiers', icon: <Layers size={16} />, path: '/memory' },
  { id: 'learning', label: 'Learning', icon: <Lightbulb size={16} />, path: '/learning' },
];

export const KnowledgePage: React.FC = () => {
  const location = useLocation();
  const [actions, setActions] = useState<PageAction[]>([]);

  const getActiveTab = () => {
    const path = location.pathname;
    if (path.includes('/knowledge/prompts')) return 'prompts';
    if (path.includes('/knowledge/skills')) return 'skills';
    if (path.includes('/knowledge/rag')) return 'rag';
    if (path.includes('/knowledge/graph')) return 'graph';
    if (path.includes('/knowledge/memory')) return 'memory';
    if (path.includes('/knowledge/learning')) return 'learning';
    return 'contexts';
  };

  const [activeTab, setActiveTab] = useState(getActiveTab());

  useEffect(() => {
    const newTab = getActiveTab();
    if (newTab !== activeTab) setActiveTab(newTab);
  }, [location.pathname]);

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
    ];
    const activeTabInfo = tabs.find(t => t.id === activeTab);
    if (activeTab === 'contexts') {
      base.push({ label: 'Knowledge' });
    } else {
      base.push({ label: 'Knowledge', href: '/app/ai/knowledge' });
      if (activeTabInfo) base.push({ label: activeTabInfo.label });
    }
    return base;
  };

  return (
    <PageContainer
      title="Knowledge"
      description="Manage agent knowledge, prompts, skills, and document bases"
      breadcrumbs={getBreadcrumbs()}
      actions={actions}
    >
      <TabContainer
        tabs={tabs}
        activeTab={activeTab}
        onTabChange={setActiveTab}
        basePath="/app/ai/knowledge"
        variant="underline"
        className="mb-6"
      >
        <TabPanel tabId="contexts" activeTab={activeTab}>
          <ContextsContent onActionsReady={handleActionsReady} />
        </TabPanel>
        <TabPanel tabId="prompts" activeTab={activeTab}>
          <PromptsContent onActionsReady={handleActionsReady} />
        </TabPanel>
        <TabPanel tabId="skills" activeTab={activeTab}>
          <SkillsContent onActionsReady={handleActionsReady} />
        </TabPanel>
        <TabPanel tabId="rag" activeTab={activeTab}>
          <RagContent onActionsReady={handleActionsReady} />
        </TabPanel>
        <TabPanel tabId="graph" activeTab={activeTab}>
          <KnowledgeGraphContent />
        </TabPanel>
        <TabPanel tabId="memory" activeTab={activeTab}>
          <KnowledgeMemoryContent onActionsReady={handleActionsReady} />
        </TabPanel>
        <TabPanel tabId="learning" activeTab={activeTab}>
          <CompoundLearningContent />
        </TabPanel>
      </TabContainer>
    </PageContainer>
  );
};

export default KnowledgePage;
