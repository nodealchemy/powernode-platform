import React, { useState, useCallback } from 'react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TaskList, TaskDetail, TaskEventStream } from '@/features/ai/a2a-tasks';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useAiOrchestrationWebSocket } from '@/shared/hooks/useAiOrchestrationWebSocket';
import { useRefreshAction } from '@/shared/hooks/useRefreshAction';
import type { A2aTask } from '@/shared/services/ai/types/a2a-types';

type ViewMode = 'list' | 'detail';

export const A2aTasksPage: React.FC = () => {
  const [viewMode, setViewMode] = useState<ViewMode>('list');
  const [selectedTask, setSelectedTask] = useState<A2aTask | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [listKey, setListKey] = useState(0);

  usePermissions();

  // WebSocket for real-time A2A task updates
  useAiOrchestrationWebSocket({
    onAgentEvent: (event) => {
      // Refresh task list when agent execution events occur (A2A tasks use agent infrastructure)
      if (['agent_execution_started', 'agent_execution_completed', 'agent_execution_failed', 'agent_message_sent', 'agent_message_received'].includes(event.type)) {
        setListKey((k) => k + 1);
      }
    },
  });

  const handleRefresh = useCallback(async () => {
    setIsLoading(true);
    try {
      setListKey((k) => k + 1);
    } finally {
      setIsLoading(false);
    }
  }, []);

  const { refreshAction } = useRefreshAction({
    onRefresh: handleRefresh,
    loading: isLoading,
  });

  const handleSelectTask = (task: A2aTask) => {
    setSelectedTask(task);
    setViewMode('detail');
  };

  const handleBackToList = () => {
    setViewMode('list');
    setSelectedTask(null);
  };

  // Build breadcrumbs based on current view
  const getBreadcrumbs = () => {
    const base = [
      { label: 'Dashboard', href: '/app' },
      { label: 'AI', href: '/app/ai' },
    ];

    switch (viewMode) {
      case 'list':
        return [...base, { label: 'A2A Tasks' }];
      case 'detail':
        return [
          ...base,
          { label: 'A2A Tasks', href: '/app/ai/a2a-tasks', onClick: handleBackToList },
          { label: selectedTask?.task_id?.substring(0, 8) || 'Task Details' },
        ];
      default:
        return base;
    }
  };

  // Build actions based on current view
  const getActions = () => {
    switch (viewMode) {
      case 'list':
        return [refreshAction];
      case 'detail':
        return [
          {
            id: 'back',
            label: 'Back to List',
            onClick: handleBackToList,
            variant: 'secondary' as const,
          },
        ];
      default:
        return [];
    }
  };

  // Get title and description based on current view
  const getPageInfo = () => {
    switch (viewMode) {
      case 'list':
        return {
          title: 'A2A Tasks',
          description: 'Monitor Agent-to-Agent communication tasks',
        };
      case 'detail':
        return {
          title: 'Task Details',
          description: selectedTask?.task_id || 'View task details and events',
        };
      default:
        return { title: 'A2A Tasks', description: '' };
    }
  };

  const pageInfo = getPageInfo();

  return (
    <PageContainer
      title={pageInfo.title}
      description={pageInfo.description}
      breadcrumbs={getBreadcrumbs()}
      actions={getActions()}
    >
      {viewMode === 'list' && (
        <TaskList key={listKey} onSelectTask={handleSelectTask} />
      )}

      {viewMode === 'detail' && selectedTask && (
        <div className="space-y-6">
          <TaskDetail taskId={selectedTask.task_id} onClose={handleBackToList} />
          <TaskEventStream taskId={selectedTask.task_id} autoConnect={selectedTask.status === 'active'} />
        </div>
      )}
    </PageContainer>
  );
};

export default A2aTasksPage;
