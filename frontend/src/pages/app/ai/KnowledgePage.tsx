import React, { useState, useEffect } from 'react';
import { useLocation } from 'react-router-dom';
import { BookOpen, MessageSquare, Puzzle, Database } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { ContextsContent } from '@/pages/app/ai/ContextsPage';
import { PromptsContent } from '@/features/ai/prompts/pages/PromptsPage';
import { SkillsContent } from '@/pages/app/ai/SkillsPage';
import { RagContent } from '@/pages/app/ai/RagPage';

const tabs = [
  { id: 'contexts', label: 'Contexts', icon: <BookOpen size={16} />, path: '/contexts' },
  { id: 'prompts', label: 'Prompts', icon: <MessageSquare size={16} />, path: '/prompts' },
  { id: 'skills', label: 'Skills', icon: <Puzzle size={16} />, path: '/skills' },
  { id: 'rag', label: 'RAG', icon: <Database size={16} />, path: '/rag' },
];

export const KnowledgePage: React.FC = () => {
  const location = useLocation();

  const getActiveTab = () => {
    const path = location.pathname;
    if (path.includes('/knowledge/prompts')) return 'prompts';
    if (path.includes('/knowledge/skills')) return 'skills';
    if (path.includes('/knowledge/rag')) return 'rag';
    return 'contexts';
  };

  const [activeTab, setActiveTab] = useState(getActiveTab());

  useEffect(() => {
    const newTab = getActiveTab();
    if (newTab !== activeTab) setActiveTab(newTab);
  }, [location.pathname]);

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
          <ContextsContent />
        </TabPanel>
        <TabPanel tabId="prompts" activeTab={activeTab}>
          <PromptsContent />
        </TabPanel>
        <TabPanel tabId="skills" activeTab={activeTab}>
          <SkillsContent />
        </TabPanel>
        <TabPanel tabId="rag" activeTab={activeTab}>
          <RagContent />
        </TabPanel>
      </TabContainer>
    </PageContainer>
  );
};

export default KnowledgePage;
