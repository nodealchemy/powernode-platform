import React, { useState, useCallback } from 'react';
import { MessageSquare, Settings, ArrowLeft } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { ChannelMetrics } from './ChannelMetrics';
import { ChannelSessions } from './ChannelSessions';
import { SessionMessages } from './SessionMessages';
import { SessionTransferModal } from './SessionTransferModal';
import { ChannelSettingsModal } from './ChannelSettingsModal';
import type { ChatChannelSummary, ChatSessionSummary, ChannelStatus } from '@/shared/services/ai';

interface ChannelDetailPanelProps {
  channel: ChatChannelSummary | null;
}

const statusVariant: Record<ChannelStatus, 'success' | 'danger' | 'warning' | 'outline'> = {
  active: 'success',
  inactive: 'outline',
  error: 'danger',
  disconnected: 'warning',
};

const statusLabelMap: Record<ChannelStatus, string> = {
  active: 'Connected',
  inactive: 'Inactive',
  error: 'Error',
  disconnected: 'Disconnected',
};

export const ChannelDetailPanel: React.FC<ChannelDetailPanelProps> = ({ channel }) => {
  const [selectedSession, setSelectedSession] = useState<ChatSessionSummary | null>(null);
  const [transferSession, setTransferSession] = useState<ChatSessionSummary | null>(null);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [refreshKey, setRefreshKey] = useState(0);

  const handleRefresh = useCallback(() => {
    setRefreshKey((prev) => prev + 1);
  }, []);

  const handleBackFromMessages = () => {
    setSelectedSession(null);
  };

  if (!channel) {
    return (
      <div className="flex-1 flex items-center justify-center bg-theme-bg">
        <div className="text-center">
          <MessageSquare className="w-12 h-12 mx-auto text-theme-secondary/30 mb-3" />
          <p className="text-sm text-theme-secondary">Select a channel to view details</p>
        </div>
      </div>
    );
  }

  if (selectedSession) {
    return (
      <div className="flex-1 flex flex-col overflow-hidden bg-theme-bg">
        <div className="flex items-center gap-3 px-4 py-3 border-b border-theme bg-theme-surface">
          <Button variant="ghost" size="sm" onClick={handleBackFromMessages}>
            <ArrowLeft className="w-4 h-4" />
          </Button>
          <div className="min-w-0">
            <h3 className="text-sm font-medium text-theme-primary truncate">
              Session: {selectedSession.platform_user_id}
            </h3>
            <p className="text-xs text-theme-secondary">
              {channel.name} · {selectedSession.status}
            </p>
          </div>
        </div>
        <div className="flex-1 overflow-y-auto p-4">
          <SessionMessages
            sessionId={selectedSession.id}
            sessionStatus={selectedSession.status}
            onBack={handleBackFromMessages}
          />
        </div>
      </div>
    );
  }

  return (
    <div className="flex-1 flex flex-col overflow-hidden bg-theme-bg">
      <div className="flex items-center justify-between px-4 py-3 border-b border-theme bg-theme-surface">
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <h3 className="text-sm font-semibold text-theme-primary truncate">
              {channel.name}
            </h3>
            <Badge
              variant={statusVariant[channel.status] || 'outline'}
              size="sm"
            >
              {statusLabelMap[channel.status] || channel.status}
            </Badge>
          </div>
          <p className="text-xs text-theme-secondary capitalize mt-0.5">
            {channel.platform} · {channel.active_sessions} active sessions · {channel.total_sessions} total
          </p>
        </div>
        <Button
          variant="ghost"
          size="sm"
          onClick={() => setSettingsOpen(true)}
          title="Channel settings"
        >
          <Settings className="w-4 h-4" />
        </Button>
      </div>

      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        <ChannelMetrics channelId={channel.id} key={`metrics-${refreshKey}`} />

        <ChannelSessions
          channelId={channel.id}
          key={`sessions-${refreshKey}`}
          onSelectSession={(session) => setSelectedSession(session)}
          onTransferSession={(session) => setTransferSession(session)}
        />
      </div>

      <SessionTransferModal
        isOpen={!!transferSession}
        onClose={() => setTransferSession(null)}
        session={transferSession}
        onTransferred={handleRefresh}
      />

      <ChannelSettingsModal
        isOpen={settingsOpen}
        onClose={() => setSettingsOpen(false)}
        channelId={channel.id}
        onSaved={handleRefresh}
      />
    </div>
  );
};

export default ChannelDetailPanel;
