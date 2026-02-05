import React, { useState, useEffect, useCallback } from 'react';
import { XCircle } from 'lucide-react';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { useNotification } from '@/shared/hooks/useNotification';
import { SessionList } from '../components/SessionList';
import { SessionDetailView } from '../components/SessionDetailView';
import { CreateSessionModal } from '../components/CreateSessionModal';
import { useParallelExecution } from '../hooks/useParallelExecution';
import type { ParallelSession, ParallelSessionConfig } from '../types';

export const ParallelExecutionPage: React.FC = () => {
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
    cancelSession,
    retryMerge,
    setSelectedSession,
  } = useParallelExecution();

  useEffect(() => {
    loadSessions();
  }, [loadSessions]);

  const handleSelectSession = useCallback((session: ParallelSession) => {
    loadSession(session.id);
  }, [loadSession]);

  const handleBack = useCallback(() => {
    setSelectedSession(null);
    loadSessions();
  }, [setSelectedSession, loadSessions]);

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

  const handleCancelSession = useCallback(async () => {
    if (!selectedSession) return;
    await cancelSession(selectedSession.id, 'User cancelled');
    showNotification('Session cancelled', 'success');
  }, [selectedSession, cancelSession, showNotification]);

  const handleRetryMerge = useCallback(async () => {
    if (!selectedSession) return;
    await retryMerge(selectedSession.id);
    showNotification('Merge retry started', 'success');
  }, [selectedSession, retryMerge, showNotification]);

  const getBreadcrumbs = () => {
    const base = [
      { label: 'Dashboard', href: '/app' },
      { label: 'AI', href: '/app/ai' },
    ];

    if (selectedSession) {
      return [
        ...base,
        { label: 'Parallel Execution', href: '/app/ai/parallel-execution' },
        { label: `Session ${selectedSession.id.substring(0, 8)}` },
      ];
    }
    return [...base, { label: 'Parallel Execution' }];
  };

  const getActions = (): PageAction[] => {
    if (selectedSession) {
      const actions: PageAction[] = [
        {
          id: 'back',
          label: 'Back to List',
          onClick: handleBack,
          variant: 'secondary',
        },
      ];

      const isActive = ['pending', 'provisioning', 'active'].includes(selectedSession.status);
      if (isActive) {
        actions.push({
          id: 'cancel',
          label: 'Cancel',
          onClick: handleCancelSession,
          variant: 'outline',
          icon: XCircle,
        });
      }

      return actions;
    }
    return [];
  };

  const getPageInfo = () => {
    if (selectedSession) {
      return {
        title: `Session ${selectedSession.id.substring(0, 8)}`,
        description: `${selectedSession.base_branch} - ${selectedSession.merge_strategy} merge`,
      };
    }
    return {
      title: 'Parallel Execution',
      description: 'AI agents working in parallel using isolated git worktrees',
    };
  };

  const pageInfo = getPageInfo();

  return (
    <PageContainer
      title={pageInfo.title}
      description={pageInfo.description}
      breadcrumbs={getBreadcrumbs()}
      actions={getActions()}
    >
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
    </PageContainer>
  );
};

export default ParallelExecutionPage;
