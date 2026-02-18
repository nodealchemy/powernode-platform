import React, { useState } from 'react';
import { Activity, MessageSquare, Wrench, List } from 'lucide-react';
import { TabContainer } from '@/shared/components/ui/TabContainer';
import { AguiRunStatus } from './AguiRunStatus';
import { AguiTextStream } from './AguiTextStream';
import { AguiToolCallPanel } from './AguiToolCallPanel';
import { AguiEventLog } from './AguiEventLog';
import type { AguiSession, AguiEvent } from '../types/agui';

interface AguiSessionDetailPanelProps {
  session: AguiSession | null;
  events: AguiEvent[];
}

export const AguiSessionDetailPanel: React.FC<AguiSessionDetailPanelProps> = ({
  session,
  events,
}) => {
  const [detailTab, setDetailTab] = useState('text');

  if (!session) {
    return (
      <div className="flex-1 flex items-center justify-center">
        <div className="text-center">
          <Activity className="h-10 w-10 text-theme-muted mx-auto mb-3 opacity-50" />
          <p className="text-theme-secondary">
            Select a session to view its events and state.
          </p>
        </div>
      </div>
    );
  }

  const detailTabs = [
    {
      id: 'text',
      label: 'Messages',
      icon: <MessageSquare className="h-4 w-4" />,
      content: <AguiTextStream events={events} />,
    },
    {
      id: 'tools',
      label: 'Tool Calls',
      icon: <Wrench className="h-4 w-4" />,
      content: <AguiToolCallPanel events={events} />,
    },
    {
      id: 'events',
      label: 'Event Log',
      icon: <List className="h-4 w-4" />,
      content: <AguiEventLog events={events} />,
    },
  ];

  return (
    <div className="flex-1 overflow-y-auto p-6 space-y-4">
      <AguiRunStatus session={session} />
      <div className="bg-theme-card border border-theme rounded-lg p-4">
        <TabContainer
          tabs={detailTabs}
          activeTab={detailTab}
          onTabChange={setDetailTab}
          variant="underline"
        />
      </div>
    </div>
  );
};
