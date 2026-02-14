import React from 'react';
import { Hash } from 'lucide-react';
import { Team, TeamChannel } from '@/shared/services/ai/TeamsApiService';

interface ChannelsTabProps {
  selectedTeam: Team | null;
  channels: TeamChannel[];
}

export const ChannelsTab: React.FC<ChannelsTabProps> = ({ selectedTeam, channels }) => {
  if (!selectedTeam) {
    return (
      <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
        <p className="text-theme-secondary">Select a team to view channels</p>
      </div>
    );
  }

  if (channels.length === 0) {
    return (
      <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
        <Hash size={48} className="mx-auto text-theme-secondary mb-4" />
        <h3 className="text-lg font-semibold text-theme-primary mb-2">No channels</h3>
        <p className="text-theme-secondary mb-6">Create communication channels for team coordination</p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {channels.map(channel => (
        <div key={channel.id} className="bg-theme-surface border border-theme rounded-lg p-4">
          <div className="flex items-center justify-between mb-2">
            <div className="flex items-center gap-3">
              <Hash size={16} className="text-theme-accent" />
              <h3 className="font-medium text-theme-primary">{channel.name}</h3>
              <span className="px-2 py-1 text-xs bg-theme-accent/10 text-theme-accent rounded">{channel.channel_type}</span>
              {channel.is_persistent && <span className="px-2 py-1 text-xs bg-theme-info/10 text-theme-info rounded">Persistent</span>}
            </div>
            <span className="text-sm text-theme-secondary">{channel.message_count} messages</span>
          </div>
          {channel.description && <p className="text-sm text-theme-secondary mb-2">{channel.description}</p>}
          <div className="flex gap-2 text-xs text-theme-secondary">
            <span>{channel.participant_roles.length} participants</span>
            {channel.message_retention_hours && <span>Retention: {channel.message_retention_hours}h</span>}
          </div>
        </div>
      ))}
    </div>
  );
};
