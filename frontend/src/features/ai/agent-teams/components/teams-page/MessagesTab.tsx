import React from 'react';
import { MessageSquare, ArrowRightLeft } from 'lucide-react';
import { TeamExecution, TeamMessage } from '@/shared/services/ai/TeamsApiService';

interface MessagesTabProps {
  selectedExecution: TeamExecution | null;
  messages: TeamMessage[];
}

export const MessagesTab: React.FC<MessagesTabProps> = ({ selectedExecution, messages }) => {
  if (!selectedExecution) {
    return (
      <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
        <MessageSquare size={48} className="mx-auto text-theme-secondary mb-4" />
        <h3 className="text-lg font-semibold text-theme-primary mb-2">Select an execution</h3>
        <p className="text-theme-secondary">Go to the Executions tab and click on an execution to view messages</p>
      </div>
    );
  }

  if (messages.length === 0) {
    return (
      <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
        <MessageSquare size={48} className="mx-auto text-theme-secondary mb-4" />
        <h3 className="text-lg font-semibold text-theme-primary mb-2">No messages</h3>
        <p className="text-theme-secondary">Messages will appear as agents communicate</p>
      </div>
    );
  }

  return (
    <div className="space-y-3">
      {messages.map(msg => (
        <div key={msg.id} className="bg-theme-surface border border-theme rounded-lg p-4">
          <div className="flex items-center gap-2 mb-2">
            <span className="text-sm font-medium text-theme-accent">{msg.from_role_name || 'System'}</span>
            {msg.to_role_name && (
              <>
                <ArrowRightLeft size={12} className="text-theme-secondary" />
                <span className="text-sm font-medium text-theme-info">{msg.to_role_name}</span>
              </>
            )}
            <span className="text-xs text-theme-secondary ml-auto">{new Date(msg.created_at).toLocaleTimeString()}</span>
          </div>
          <p className="text-sm text-theme-primary">{msg.content}</p>
          {msg.message_type && (
            <span className="inline-block mt-1 px-2 py-0.5 text-xs bg-theme-accent/10 text-theme-accent rounded">{msg.message_type}</span>
          )}
        </div>
      ))}
    </div>
  );
};
