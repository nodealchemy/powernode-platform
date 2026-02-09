import React, { useState, useEffect } from 'react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TaskList, TaskDetail, TaskEventStream } from '@/features/ai/a2a-tasks';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useAiOrchestrationWebSocket } from '@/shared/hooks/useAiOrchestrationWebSocket';
import type { A2aTask } from '@/shared/services/ai/types/a2a-types';

type ViewMode = 'list' | 'detail';

interface A2aTasksContentProps {
  refreshKey?: number;
}

export const A2aTasksContent: React.FC<A2aTasksContentProps> = ({ refreshKey: externalRefreshKey }) => {
  const [viewMode, setViewMode] = useState<ViewMode>('list');
  const [selectedTask, setSelectedTask] = useState<A2aTask | null>(null);
  const [listKey, setListKey] = useState(0);

  useEffect(() => {
    if (externalRefreshKey && externalRefreshKey > 0) {
      setListKey(k => k + 1);
    }
  }, [externalRefreshKey]);

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

  const handleSelectTask = (task: A2aTask) => {
    setSelectedTask(task);
    setViewMode('detail');
  };

  const handleBackToList = () => {
    setViewMode('list');
    setSelectedTask(null);
  };

  return (
    <div className="space-y-6">
      {viewMode === 'list' && (
        <TaskList key={listKey} onSelectTask={handleSelectTask} />
      )}

      {viewMode === 'detail' && selectedTask && (
        <div className="space-y-6">
          <TaskDetail taskId={selectedTask.task_id} onClose={handleBackToList} />
          <TaskEventStream taskId={selectedTask.task_id} autoConnect={selectedTask.status === 'active'} />
        </div>
      )}
    </div>
  );
};

export const A2aTasksPage: React.FC = () => {
  return (
    <PageContainer
      title="A2A Tasks"
      description="Monitor Agent-to-Agent communication tasks"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'AI', href: '/app/ai' },
        { label: 'A2A Tasks' },
      ]}
    >
      <A2aTasksContent />
    </PageContainer>
  );
};

export default A2aTasksPage;
