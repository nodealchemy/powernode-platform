import React, { useState } from 'react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { ChannelListPanel } from '../components/ChannelListPanel';
import { ChannelDetailPanel } from '../components/ChannelDetailPanel';
import type { ChatChannelSummary } from '@/shared/services/ai';

export const ChatChannelsPage: React.FC = () => {
  const [selectedChannel, setSelectedChannel] = useState<ChatChannelSummary | null>(null);

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'AI', href: '/app/ai' },
    { label: 'Chat Channels' },
  ];

  return (
    <PageContainer
      title="Chat Channels"
      description="Manage external chat platform integrations"
      breadcrumbs={breadcrumbs}
    >
      <div className="flex h-[calc(100vh-12rem)]">
        <ChannelListPanel
          selectedChannelId={selectedChannel?.id ?? null}
          onSelectChannel={setSelectedChannel}
        />
        <ChannelDetailPanel channel={selectedChannel} />
      </div>
    </PageContainer>
  );
};

export default ChatChannelsPage;
