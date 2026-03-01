import React, { useState, useEffect, useCallback } from 'react';
import { ArrowLeft } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { useNotification } from '@/shared/hooks/useNotification';
import { ParallelSessionListPanel } from '../components/ParallelSessionListPanel';
import { ParallelSessionDetailPanel } from '../components/ParallelSessionDetailPanel';
import { CreateSessionModal } from '../components/CreateSessionModal';
import { useParallelExecution } from '../hooks/useParallelExecution';
import type { ParallelSession, ParallelSessionConfig } from '../types';

interface ParallelExecutionContentProps {
  refreshKey?: number;
}

export const ParallelExecutionContent: React.FC<ParallelExecutionContentProps> = ({ refreshKey: externalRefreshKey }) => {
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [mobileShowDetail, setMobileShowDetail] = useState(false);
  const { showNotification } = useNotification();

  const {
    sessions,
    selectedSession,
    loading,
    error,
    isConnected,
    loadSessions,
    loadSession,
    createSession,
    retryMerge,
  } = useParallelExecution();

  useEffect(() => {
    loadSessions();
  }, [loadSessions]);

  useEffect(() => {
    if (externalRefreshKey && externalRefreshKey > 0) {
      loadSessions();
    }
  }, [externalRefreshKey, loadSessions]);

  const handleSelectSession = useCallback((session: ParallelSession) => {
    loadSession(session.id);
    setMobileShowDetail(true);
  }, [loadSession]);

  const handleCreateSession = useCallback(async (config: ParallelSessionConfig) => {
    const result = await createSession(config);
    if (result) {
      setShowCreateModal(false);
      showNotification('Parallel session created', 'success');
      if (result.session?.id) {
        loadSession(result.session.id);
        setMobileShowDetail(true);
      }
    }
  }, [createSession, showNotification, loadSession]);

  const handleRetryMerge = useCallback(async () => {
    if (!selectedSession) return;
    await retryMerge(selectedSession.id);
    showNotification('Merge retry started', 'success');
  }, [selectedSession, retryMerge, showNotification]);

  const handleBackToList = useCallback(() => {
    setMobileShowDetail(false);
  }, []);

  return (
    <>
      <div className="flex h-[calc(100vh-280px)]">
        {/* List panel - hidden on mobile when detail is shown */}
        <div className={`${mobileShowDetail ? 'hidden lg:flex' : 'flex'}`}>
          <ParallelSessionListPanel
            sessions={sessions}
            loading={loading}
            selectedSessionId={selectedSession?.id || null}
            onSelectSession={handleSelectSession}
            onCreateSession={() => setShowCreateModal(true)}
            refreshKey={externalRefreshKey}
          />
        </div>

        {/* Detail panel */}
        <div className={`flex-1 flex flex-col min-w-0 ${mobileShowDetail ? 'flex' : 'hidden lg:flex'}`}>
          {/* Mobile back button */}
          {mobileShowDetail && (
            <div className="lg:hidden px-4 py-2 border-b border-theme">
              <button
                onClick={handleBackToList}
                className="flex items-center gap-1 text-sm text-theme-secondary hover:text-theme-primary transition-colors"
              >
                <ArrowLeft className="h-4 w-4" />
                Back to sessions
              </button>
            </div>
          )}

          <ParallelSessionDetailPanel
            session={selectedSession}
            loading={loading}
            error={error}
            isConnected={isConnected}
            onRetryMerge={handleRetryMerge}
          />
        </div>
      </div>

      <CreateSessionModal
        isOpen={showCreateModal}
        onClose={() => setShowCreateModal(false)}
        onSubmit={handleCreateSession}
        loading={loading}
      />
    </>
  );
};

export const ParallelExecutionPage: React.FC = () => {
  return (
    <PageContainer
      title="Parallel Execution"
      description="AI agents working in parallel using isolated git worktrees"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'AI', href: '/app/ai' },
        { label: 'Parallel Execution' },
      ]}
    >
      <ParallelExecutionContent />
    </PageContainer>
  );
};

export default ParallelExecutionPage;
