import React, { useState } from 'react';
import { Radio, Plus, ArrowLeft } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { ResizableListPanel } from '@/shared/components/layout/ResizableListPanel';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useCreateAguiSession, useGetAguiSession, useListAguiEvents, useListAguiSessions } from '../api/aguiApi';
import { AguiSessionList } from '../components/AguiSessionList';
import { AguiSessionDetailPanel } from '../components/AguiSessionDetailPanel';
import type { AguiSession } from '../types/agui';

export const AguiPage: React.FC = () => {
  const { hasPermission } = usePermissions();
  const { addNotification } = useNotifications();
  const [selectedSessionId, setSelectedSessionId] = useState<string | null>(null);
  const [mobileShowDetail, setMobileShowDetail] = useState(false);
  const createSession = useCreateAguiSession();

  const canView = hasPermission('ai.agents.read');
  const canManage = hasPermission('ai.agents.manage');

  const { data: selectedSession } = useGetAguiSession(selectedSessionId || '');
  const { data: events } = useListAguiEvents(selectedSessionId || '');
  const { data: sessions } = useListAguiSessions({});

  const handleSelectSession = (session: AguiSession) => {
    setSelectedSessionId(session.id);
    setMobileShowDetail(true);
  };

  const handleCreateSession = () => {
    createSession.mutate(
      {},
      {
        onSuccess: (session) => {
          setSelectedSessionId(session.id);
          setMobileShowDetail(true);
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
  const sessionList = sessions || [];

  const collapsedIcons = sessionList.slice(0, 8).map((s) => (
    <button
      key={s.id}
      onClick={() => handleSelectSession(s)}
      className={`p-1.5 rounded transition-colors ${
        selectedSessionId === s.id
          ? 'bg-theme-interactive-primary/20 text-theme-interactive-primary'
          : 'text-theme-muted hover:text-theme-primary hover:bg-theme-surface-hover'
      }`}
      title={s.thread_id}
    >
      <Radio className="h-4 w-4" />
    </button>
  ));

  return (
    <div className="flex h-[calc(100vh-280px)]">
      {/* Mobile back button */}
      {mobileShowDetail && (
        <div className="lg:hidden absolute top-2 left-2 z-10">
          <button
            onClick={() => setMobileShowDetail(false)}
            className="flex items-center gap-1 text-sm text-theme-secondary hover:text-theme-primary"
          >
            <ArrowLeft className="h-4 w-4" />
            Sessions
          </button>
        </div>
      )}

      {/* Left Panel */}
      <div className={`${mobileShowDetail ? 'hidden lg:flex' : 'flex'} h-full`}>
        <ResizableListPanel
          storageKeyPrefix="agui-panel"
          title="Sessions"
          headerAction={
            canManage ? (
              <button
                onClick={handleCreateSession}
                className="p-1 rounded text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-hover transition-colors"
                title="New Session"
              >
                <Plus className="h-4 w-4" />
              </button>
            ) : undefined
          }
          collapsedContent={<>{collapsedIcons}</>}
        >
          <AguiSessionList
            selectedSessionId={selectedSessionId}
            onSelectSession={handleSelectSession}
          />
        </ResizableListPanel>
      </div>

      {/* Right Panel */}
      <div className={`${mobileShowDetail ? 'flex' : 'hidden lg:flex'} flex-1 flex-col min-w-0`}>
        <AguiSessionDetailPanel
          session={selectedSession || null}
          events={eventList}
        />
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
