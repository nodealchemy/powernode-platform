import React, { useState } from 'react';
import { Radio, MessageSquare, Wrench, List, Activity, Plus } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TabContainer } from '@/shared/components/ui/TabContainer';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useCreateAguiSession, useGetAguiSession, useListAguiEvents } from '../api/aguiApi';
import { AguiSessionList } from '../components/AguiSessionList';
import { AguiTextStream } from '../components/AguiTextStream';
import { AguiToolCallPanel } from '../components/AguiToolCallPanel';
import { AguiEventLog } from '../components/AguiEventLog';
import { AguiRunStatus } from '../components/AguiRunStatus';
import type { AguiSession } from '../types/agui';

export const AguiPage: React.FC = () => {
  const { hasPermission } = usePermissions();
  const { addNotification } = useNotifications();
  const [selectedSessionId, setSelectedSessionId] = useState<string | null>(null);
  const [detailTab, setDetailTab] = useState('text');
  const createSession = useCreateAguiSession();

  const canView = hasPermission('ai.agents.read');
  const canManage = hasPermission('ai.agents.manage');

  const { data: selectedSession } = useGetAguiSession(selectedSessionId || '');
  const { data: events } = useListAguiEvents(selectedSessionId || '');

  const handleSelectSession = (session: AguiSession) => {
    setSelectedSessionId(session.id);
    setDetailTab('text');
  };

  const handleCreateSession = () => {
    createSession.mutate(
      {},
      {
        onSuccess: (session) => {
          setSelectedSessionId(session.id);
          addNotification({ type: 'success', message: 'Session created' });
        },
        onError: () => {
          addNotification({ type: 'error', message: 'Failed to create session' });
        },
      }
    );
  };

  if (!canView) {
    return (
      <div className="text-center py-12">
        <Radio className="h-12 w-12 text-theme-muted mx-auto mb-4 opacity-50" />
        <p className="text-theme-secondary">You do not have permission to view AG-UI sessions.</p>
      </div>
    );
  }

  const eventList = events || [];

  const detailTabs = [
    {
      id: 'text',
      label: 'Messages',
      icon: <MessageSquare className="h-4 w-4" />,
      content: <AguiTextStream events={eventList} />,
    },
    {
      id: 'tools',
      label: 'Tool Calls',
      icon: <Wrench className="h-4 w-4" />,
      content: <AguiToolCallPanel events={eventList} />,
    },
    {
      id: 'events',
      label: 'Event Log',
      icon: <List className="h-4 w-4" />,
      content: <AguiEventLog events={eventList} />,
    },
  ];

  return (
    <div className="space-y-4">
      {canManage && (
        <div className="flex justify-end">
          <button
            onClick={handleCreateSession}
            className="flex items-center gap-2 px-3 py-2 text-sm bg-theme-primary text-theme-on-primary rounded hover:opacity-90"
          >
            <Plus className="h-4 w-4" />
            New Session
          </button>
        </div>
      )}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Left Panel: Session List */}
        <div className="lg:col-span-1">
          <div className="bg-theme-card border border-theme rounded-lg p-4">
            <h3 className="text-sm font-semibold text-theme-primary mb-3 flex items-center gap-2">
              <Radio className="h-4 w-4" />
              Sessions
            </h3>
            <AguiSessionList
              selectedSessionId={selectedSessionId}
              onSelectSession={handleSelectSession}
            />
          </div>
        </div>

        {/* Right Panel: Session Detail */}
        <div className="lg:col-span-2">
          {selectedSession ? (
            <div className="space-y-4">
              {/* Run Status */}
              <AguiRunStatus session={selectedSession} />

              {/* Tabbed Detail View */}
              <div className="bg-theme-card border border-theme rounded-lg p-4">
                <TabContainer
                  tabs={detailTabs}
                  activeTab={detailTab}
                  onTabChange={setDetailTab}
                  variant="underline"
                />
              </div>
            </div>
          ) : (
            <div className="bg-theme-card border border-theme rounded-lg p-12 text-center">
              <Activity className="h-10 w-10 text-theme-muted mx-auto mb-3 opacity-50" />
              <p className="text-theme-secondary">
                Select a session to view its events and state.
              </p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

// Re-export as named content component for embedding
export { AguiPage as AguiContent };

// Standalone page wrapper
const AguiStandalonePage: React.FC = () => (
  <PageContainer
    title="AG-UI Protocol"
    description="Agent-User Interaction protocol sessions, real-time streaming, and event history"
    breadcrumbs={[
      { label: 'Dashboard', href: '/app' },
      { label: 'AI', href: '/app/ai' },
      { label: 'AG-UI' },
    ]}
  >
    <AguiPage />
  </PageContainer>
);

export { AguiStandalonePage };
