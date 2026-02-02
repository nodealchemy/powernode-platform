import React, { useState } from 'react';
import {
  Settings,
} from 'lucide-react';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { ChannelList } from '../components/ChannelList';
import { ChannelSessions } from '../components/ChannelSessions';
import { ChannelMetrics } from '../components/ChannelMetrics';
import type { ChatChannelSummary } from '@/shared/services/ai';

interface ChatChannelsPageProps {
  onCreateChannel?: () => void;
  onConfigureChannel?: (channel: ChatChannelSummary) => void;
}

export const ChatChannelsPage: React.FC<ChatChannelsPageProps> = ({
  onCreateChannel,
  onConfigureChannel,
}) => {
  const [selectedChannel, setSelectedChannel] = useState<ChatChannelSummary | null>(null);

  const handleSelectChannel = (channel: ChatChannelSummary) => {
    setSelectedChannel(channel);
  };

  const handleBack = () => {
    setSelectedChannel(null);
  };

  // Build breadcrumbs based on current view
  const getBreadcrumbs = () => {
    const base = [
      { label: 'Dashboard', href: '/app' },
      { label: 'AI', href: '/app/ai' },
    ];

    if (selectedChannel) {
      return [
        ...base,
        { label: 'Chat Channels', href: '/app/ai/chat-channels' },
        { label: selectedChannel.name },
      ];
    }
    return [...base, { label: 'Chat Channels' }];
  };

  // Build actions based on current view
  const getActions = (): PageAction[] => {
    if (selectedChannel) {
      return [
        {
          id: 'back',
          label: 'Back to List',
          onClick: handleBack,
          variant: 'secondary',
        },
        {
          id: 'settings',
          label: 'Settings',
          onClick: () => onConfigureChannel?.(selectedChannel),
          variant: 'outline',
          icon: Settings,
        },
      ];
    }
    return [];
  };

  // Get page info based on current view
  const getPageInfo = () => {
    if (selectedChannel) {
      return {
        title: selectedChannel.name,
        description: `${selectedChannel.platform} · ${selectedChannel.status}`,
      };
    }
    return {
      title: 'Chat Channels',
      description: 'Manage external chat platform integrations',
    };
  };

  const pageInfo = getPageInfo();

  if (selectedChannel) {
    return (
      <PageContainer
        title={pageInfo.title}
        description={pageInfo.description}
        breadcrumbs={getBreadcrumbs()}
        actions={getActions()}
      >
        {/* Metrics */}
        <ChannelMetrics channelId={selectedChannel.id} />

        {/* Sessions */}
        <ChannelSessions
          channelId={selectedChannel.id}
          onSelectSession={() => {
            // Handle session selection - could open a detail modal
          }}
        />
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title={pageInfo.title}
      description={pageInfo.description}
      breadcrumbs={getBreadcrumbs()}
      actions={getActions()}
    >
      <ChannelList
        onSelectChannel={handleSelectChannel}
        onCreateChannel={onCreateChannel}
      />
    </PageContainer>
  );
};

export default ChatChannelsPage;
