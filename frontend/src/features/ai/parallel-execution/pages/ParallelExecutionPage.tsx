import React, { useState, useEffect, useCallback } from 'react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { useNotification } from '@/shared/hooks/useNotification';
import { SessionList } from '../components/SessionList';
import { SessionDetailView } from '../components/SessionDetailView';
import { CreateSessionModal } from '../components/CreateSessionModal';
import { useParallelExecution } from '../hooks/useParallelExecution';
import type { ParallelSession, ParallelSessionConfig } from '../types';

interface ParallelExecutionContentProps {
  refreshKey?: number;
}

export const ParallelExecutionContent: React.FC<ParallelExecutionContentProps> = ({ refreshKey: externalRefreshKey }) => {
  const [showCreateModal, setShowCreateModal] = useState(false);
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
  }, [loadSession]);

  const handleCreateSession = useCallback(async (config: ParallelSessionConfig) => {
    const result = await createSession(config);
    if (result) {
      setShowCreateModal(false);
      showNotification('Parallel session created', 'success');
      if (result.session?.id) {
        loadSession(result.session.id);
      }
    }
  }, [createSession, showNotification, loadSession]);

  const handleRetryMerge = useCallback(async () => {
    if (!selectedSession) return;
    await retryMerge(selectedSession.id);
    showNotification('Merge retry started', 'success');
  }, [selectedSession, retryMerge, showNotification]);

  return (
    <div className="space-y-6">
      {error && (
        <div className="p-4 rounded-lg bg-theme-status-error/10 text-theme-status-error mb-4">
          {error}
        </div>
      )}

      {selectedSession ? (
        <SessionDetailView
          session={selectedSession}
          isConnected={isConnected}
          onRetryMerge={handleRetryMerge}
        />
      ) : (
        <SessionList
          sessions={sessions}
          loading={loading}
          onSelectSession={handleSelectSession}
          onCreateSession={() => setShowCreateModal(true)}
          onRefresh={loadSessions}
        />
      )}

      <CreateSessionModal
        isOpen={showCreateModal}
        onClose={() => setShowCreateModal(false)}
        onSubmit={handleCreateSession}
        loading={loading}
      />
    </div>
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
