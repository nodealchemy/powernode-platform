import React, { useState, useEffect } from 'react';
import { useLocation } from 'react-router-dom';
import { Radio, MessageSquare } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { ChatChannelsPage } from '@/features/ai/chat-channels/pages/ChatChannelsPage';
import { AIConversationsPage } from '@/pages/app/ai/AIConversationsPage';

const tabs = [
  { id: 'channels', label: 'Channels', icon: <Radio size={16} />, path: '/' },
  { id: 'conversations', label: 'Conversations', icon: <MessageSquare size={16} />, path: '/conversations' },
];

export const CommunicationPage: React.FC = () => {
  const location = useLocation();

  const getActiveTab = () => {
    const path = location.pathname;
    if (path.includes('/communication/conversations')) return 'conversations';
    // Auto-switch to conversations tab when ?id= param is present
    if (location.search.includes('id=')) return 'conversations';
    return 'channels';
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
    if (activeTab === 'channels') {
      base.push({ label: 'Communication' });
    } else {
      base.push({ label: 'Communication', href: '/app/ai/communication' });
      const activeTabInfo = tabs.find(t => t.id === activeTab);
      if (activeTabInfo) base.push({ label: activeTabInfo.label });
    }
    return base;
  };

  return (
    <PageContainer
      title="Communication"
      description="Chat channels and conversation management"
      breadcrumbs={getBreadcrumbs()}
    >
      <TabContainer
        tabs={tabs}
        activeTab={activeTab}
        onTabChange={setActiveTab}
        basePath="/app/ai/communication"
        variant="underline"
        className="mb-6"
      >
        <TabPanel tabId="channels" activeTab={activeTab}>
          <ChatChannelsPage />
        </TabPanel>
        <TabPanel tabId="conversations" activeTab={activeTab}>
          <AIConversationsPage />
        </TabPanel>
      </TabContainer>
    </PageContainer>
  );
};

export default CommunicationPage;
