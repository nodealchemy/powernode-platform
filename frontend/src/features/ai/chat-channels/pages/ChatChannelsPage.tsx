import React, { useState, useCallback } from 'react';
import { Settings } from 'lucide-react';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { ChannelList } from '../components/ChannelList';
import { ChannelSessions } from '../components/ChannelSessions';
import { ChannelMetrics } from '../components/ChannelMetrics';
import { SessionTransferModal } from '../components/SessionTransferModal';
import { ChannelSettingsModal } from '../components/ChannelSettingsModal';
import { SessionMessages } from '../components/SessionMessages';
import type { ChatChannelSummary, ChatSessionSummary } from '@/shared/services/ai';

export const ChatChannelsPage: React.FC = () => {
  const [selectedChannel, setSelectedChannel] = useState<ChatChannelSummary | null>(null);
  const [selectedSession, setSelectedSession] = useState<ChatSessionSummary | null>(null);
  const [transferSession, setTransferSession] = useState<ChatSessionSummary | null>(null);
  const [settingsChannelId, setSettingsChannelId] = useState<string | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);

  const handleSelectChannel = (channel: ChatChannelSummary) => {
    setSelectedChannel(channel);
    setSelectedSession(null);
  };

  const handleBack = () => {
    if (selectedSession) {
      setSelectedSession(null);
    } else {
      setSelectedChannel(null);
    }
  };

  const handleRefresh = useCallback(() => {
    setRefreshKey(prev => prev + 1);
  }, []);

  // Build breadcrumbs based on current view
  const getBreadcrumbs = () => {
    const base = [
      { label: 'Dashboard', href: '/app' },
      { label: 'AI', href: '/app/ai' },
    ];

    if (selectedSession && selectedChannel) {
      return [
        ...base,
        { label: 'Chat Channels', href: '/app/ai/chat-channels' },
        { label: selectedChannel.name, href: '/app/ai/chat-channels' },
        { label: 'Messages' },
      ];
    }
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
    if (selectedSession) {
      return [
        {
          id: 'back',
          label: 'Back to Sessions',
          onClick: handleBack,
          variant: 'secondary',
        },
      ];
    }
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
          onClick: () => setSettingsChannelId(selectedChannel.id),
          variant: 'outline',
          icon: Settings,
        },
      ];
    }
    return [];
  };

  // Get page info based on current view
  const getPageInfo = () => {
    if (selectedSession && selectedChannel) {
      return {
        title: `Session: ${selectedSession.platform_user_id}`,
        description: `${selectedChannel.name} · ${selectedSession.status}`,
      };
    }
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

  // Session message view
  if (selectedSession && selectedChannel) {
    return (
      <PageContainer
        title={pageInfo.title}
        description={pageInfo.description}
        breadcrumbs={getBreadcrumbs()}
        actions={getActions()}
      >
        <SessionMessages
          sessionId={selectedSession.id}
          sessionStatus={selectedSession.status}
          onBack={handleBack}
        />
      </PageContainer>
    );
  }

  // Channel detail view
  if (selectedChannel) {
    return (
      <PageContainer
        title={pageInfo.title}
        description={pageInfo.description}
        breadcrumbs={getBreadcrumbs()}
        actions={getActions()}
      >
        <ChannelMetrics channelId={selectedChannel.id} key={`metrics-${refreshKey}`} />

        <ChannelSessions
          channelId={selectedChannel.id}
          key={`sessions-${refreshKey}`}
          onSelectSession={(session) => setSelectedSession(session)}
          onTransferSession={(session) => setTransferSession(session)}
        />

        {/* Transfer Modal */}
        <SessionTransferModal
          isOpen={!!transferSession}
          onClose={() => setTransferSession(null)}
          session={transferSession}
          onTransferred={handleRefresh}
        />

        {/* Settings Modal */}
        <ChannelSettingsModal
          isOpen={!!settingsChannelId}
          onClose={() => setSettingsChannelId(null)}
          channelId={settingsChannelId}
          onSaved={handleRefresh}
        />
      </PageContainer>
    );
  }

  // Channel list view
  return (
    <PageContainer
      title={pageInfo.title}
      description={pageInfo.description}
      breadcrumbs={getBreadcrumbs()}
      actions={getActions()}
    >
      <ChannelList
        onSelectChannel={handleSelectChannel}
        onSettingsChannel={(channel) => setSettingsChannelId(channel.id)}
      />

      {/* Settings Modal (accessible from list too) */}
      <ChannelSettingsModal
        isOpen={!!settingsChannelId}
        onClose={() => setSettingsChannelId(null)}
        channelId={settingsChannelId}
        onSaved={handleRefresh}
      />
    </PageContainer>
  );
};

export default ChatChannelsPage;
